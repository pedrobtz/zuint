# zuint reaches Arrow only through zuarrow's registry (design 9). These
# helpers skip without zuarrow, and the engine ones without the engines.

skip_without_zuarrow <- function() {
  testthat::skip_if_not_installed("zuarrow")
  # loading zuarrow runs zuint's registration hook
  loadNamespace("zuarrow")
}

skip_without_engines <- function() {
  skip_without_zuarrow()
  # DBI::dbGetQueryArrow() needs nanoarrow
  for (pkg in c("duckdb", "DBI", "nanoarrow")) {
    testthat::skip_if_not_installed(pkg)
  }
}

# A DuckDB connection whose state stays in a temporary directory (#74),
# closed when the calling test ends.
local_duckdb <- function(lossless = TRUE, env = parent.frame()) {
  skip_without_engines()
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  if (lossless) {
    DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
  }
  con
}

# A query's result through DuckDB's Arrow export and zuarrow.
duckdb_to_r <- function(con, sql, ...) {
  zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql), ...)
}

# A data frame registered with DuckDB through an Arrow Table: DuckDB scans
# a registered reader only once. The table is built from zuarrow's IPC
# stream, so arrow never makes an R object of the arrow.opaque type
# (apache/arrow#53951).
duckdb_register_df <- function(con, name, df) {
  testthat::skip_if_not_installed("arrow")
  table <- arrow_table_of(df)
  duckdb::duckdb_register_arrow(con, name, table)
}

arrow_table_of <- function(df) {
  testthat::skip_if_not_installed("arrow")
  raw <- zuarrow::arrow_write(df, NULL, format = "stream")
  arrow::read_ipc_stream(raw, as_data_frame = FALSE)
}

# An arrow Table back through zuarrow, by the same IPC route.
arrow_table_to_r <- function(table) {
  zuarrow::arrow_read(arrow::write_to_raw(table, format = "stream"))
}

# Collect until the Arrow release count stops moving, so that a count taken
# afterwards sees no finalizers from earlier tests.
settled_releases <- function() {
  repeat {
    before <- .Call(zu_arrow_releases_c)
    invisible(gc(full = TRUE))
    after <- .Call(zu_arrow_releases_c)
    if (after == before) {
      return(after)
    }
  }
}

# The engine types the round-trip matrix covers (design 0, 12), with each
# one's zuint type.
engine_types <- c(
  BIGINT = "int64",
  UBIGINT = "uint64",
  HUGEINT = "int128",
  UHUGEINT = "uint128"
)

# Values for the matrix: every edge of the type's range, nulls and random
# fills, as decimal strings; 60 for every type, so they fit one table.
matrix_values <- function(type) {
  v <- c(oracle_edges(type), NA, oracle_random(type, 40, seed = 12))
  c(v, rep(NA, 60L - length(v)))
}

# A DuckDB connection with a table `src` holding one column per engine type,
# filled from matrix_values(); closed when the calling test ends.
duckdb_matrix_source <- function(env = parent.frame()) {
  con <- local_duckdb(env = env)
  vals <- lapply(structure(engine_types, names = engine_types), matrix_values)
  n <- length(vals[[1L]])
  cols <- vapply(
    names(engine_types),
    function(t) {
      v <- vals[[engine_types[[t]]]]
      lits <- ifelse(is.na(v), "NULL", paste0("'", v, "'"))
      sprintf(
        "CAST(%s AS %s)",
        paste0("[", paste(lits, collapse = ", "), "][i]"),
        t
      )
    },
    character(1)
  )
  sql <- sprintf(
    "CREATE TABLE src AS SELECT i, %s FROM range(1, %d) t(i) ORDER BY i",
    paste(
      sprintf("%s AS %s", cols, tolower(names(engine_types))),
      collapse = ", "
    ),
    n + 1L
  )
  DBI::dbExecute(con, sql)
  list(con = con, values = vals)
}
