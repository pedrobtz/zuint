# The first column of a DuckDB query, fetched through DuckDB's Arrow export
# as a nanoarrow array. Skips without duckdb, DBI, arrow and nanoarrow.
duckdb_column <- function(sql, lossless = FALSE) {
  for (pkg in c("duckdb", "DBI", "arrow", "nanoarrow")) {
    testthat::skip_if_not_installed(pkg)
  }
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  if (lossless) {
    DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
  }
  res <- DBI::dbSendQuery(con, sql, arrow = TRUE)
  stream <- nanoarrow::as_nanoarrow_array_stream(duckdb::duckdb_fetch_arrow(
    res
  ))
  batch <- stream$get_next()
  DBI::dbClearResult(res)
  col <- batch$children[[1L]]
  list(array = col, schema = nanoarrow::infer_nanoarrow_schema(col))
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

skip_without_engines <- function() {
  for (pkg in c("duckdb", "DBI", "arrow", "nanoarrow")) {
    testthat::skip_if_not_installed(pkg)
  }
}

# A DuckDB connection with a table `src` holding one column per engine type,
# filled from matrix_values(); closed when the calling test ends.
duckdb_matrix_source <- function(env = parent.frame()) {
  skip_without_engines()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
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
