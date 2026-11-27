# zuint reaches Arrow only through zuarrow's registry (design 9). These
# helpers skip without zuarrow; the engines' answers are replayed
# (helper-engines.R).

skip_without_zuarrow <- function() {
  testthat::skip_if_not_installed("zuarrow")
  # loading zuarrow runs zuint's registration hook
  loadNamespace("zuarrow")
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
  duck_setup(con, sql)
  list(con = con, values = vals)
}
