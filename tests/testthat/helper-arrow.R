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

# The column kinds a zuint prototype in `to =` meets (#167): DuckDB's type,
# whether arrow_lossless_conversion is on, the values as text (NA is a
# null), and `seen`, the integer each value is. A prototype gives `seen`
# where its type holds it and loses it otherwise: "lost" marks a value
# that is no integer (a fraction, a word). UHUGEINT's default export is a
# decimal128 of its bits, so its values of 2^127 and above are seen as the
# negative int128 those bits are: that form cannot tell them apart (design
# 9.1).
prototype_kinds <- function() {
  testthat::skip_if_not_installed("gmp")
  two <- gmp::as.bigz(2)
  ten <- gmp::as.bigz(10)
  # each value on its own: c() of a double and a bigz is the bigz's bytes
  s <- function(...) {
    c(vapply(list(...), function(v) as.character(gmp::as.bigz(v)), ""), NA)
  }
  hugeint <- s(
    -(two^127),
    -(two^127) + 1,
    -(two^63) - 1,
    -(two^63),
    -1,
    0,
    two^63,
    two^64 - 1,
    two^64,
    two^127 - 1
  )
  uhugeint <- s(0, two^64, two^127 - 1, two^127, two^128 - 2, two^128 - 1)
  u <- gmp::as.bigz(uhugeint)
  as_int128 <- ifelse(u >= two^127, as.character(u - two^128), uhugeint)
  as_int128[is.na(u)] <- NA
  kinds <- list(
    BIGINT = list(
      sql = "BIGINT",
      values = s(-(two^63), -(two^63) + 1, -1, 0, two^31, two^63 - 1)
    ),
    UBIGINT = list(
      sql = "UBIGINT",
      values = s(0, 1, two^63 - 1, two^63, two^64 - 2, two^64 - 1)
    ),
    HUGEINT = list(sql = "HUGEINT", values = hugeint),
    UHUGEINT = list(sql = "UHUGEINT", values = uhugeint),
    `HUGEINT default` = list(
      sql = "HUGEINT",
      lossless = FALSE,
      values = hugeint
    ),
    `UHUGEINT default` = list(
      sql = "UHUGEINT",
      lossless = FALSE,
      values = uhugeint,
      seen = as_int128
    ),
    INTEGER = list(sql = "INTEGER", values = s(-(two^31), -1, 0, two^31 - 1)),
    DOUBLE = list(
      sql = "DOUBLE",
      values = c(
        "-1",
        "0.5",
        "-9007199254740992",
        "9223372036854775808",
        "18446744073709551616",
        "1e300",
        NA
      ),
      seen = c(
        "-1",
        "lost",
        "-9007199254740992",
        "9223372036854775808",
        "18446744073709551616",
        as.character(gmp::as.bigz(1e300)),
        NA
      )
    ),
    VARCHAR = list(
      sql = "VARCHAR",
      values = c(
        "-1",
        "18446744073709551615",
        "0x10",
        "abc",
        "1.5",
        as.character(two^128),
        NA
      ),
      seen = c(
        "-1",
        "18446744073709551615",
        "16",
        "lost",
        "lost",
        as.character(two^128),
        NA
      )
    ),
    `DECIMAL(38,0)` = list(
      sql = "DECIMAL(38,0)",
      values = s(-(ten^38 - 1), -1, 0, two^64, ten^38 - 1)
    )
  )
  lapply(kinds, function(k) {
    if (is.null(k$lossless)) {
      k$lossless <- TRUE
    }
    if (is.null(k$seen)) {
      k$seen <- k$values
    }
    k
  })
}

# One column `x` of DuckDB type `type` holding `values`, in order.
prototype_sql <- function(type, values) {
  rows <- paste0(
    "(",
    seq_along(values),
    ", ",
    ifelse(is.na(values), "NULL", paste0("'", values, "'")),
    ")",
    collapse = ", "
  )
  sprintf(
    "SELECT CAST(v AS %s) AS x FROM (VALUES %s) t(i, v) ORDER BY i",
    type,
    rows
  )
}

# Column `x` of `sql` read with `to = proto` under `lossy`: its value or
# the error, and the classes of the warnings raised on the way.
read_to <- function(con, sql, proto, lossy) {
  warnings <- character()
  value <- withCallingHandlers(
    tryCatch(
      duckdb_to_r(con, sql, to = list(x = proto), lossy = lossy)$x,
      error = function(e) e
    ),
    warning = function(w) {
      warnings <<- c(warnings, class(w)[[1L]])
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = warnings)
}

# A value as its attributes and exact text, so that a comparison of two
# zuint vectors of different types fails rather than errs (waldo calls Re()
# on a complex payload); anything else, a condition say, as it is.
exactly <- function(x) {
  if (inherits(x, c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128"))) {
    list(attributes(x), as.character(x))
  } else {
    x
  }
}
