# DuckDB 2.0.1, Arrow and nanoarrow are oracles (design 12), not
# dependencies. Their answers were recorded once into fixtures/engines.rds
# by tools/oracle/record, and the tests replay them: the suite loads none of
# them. Recording runs the same tests against the live engines
# (tools/oracle/live.R), and CI's oracle job records afresh and compares,
# so the fixture cannot drift from the engines (tools/oracle/README.md).
#
# Every answer is keyed by everything it depends on: the SQL, the
# connection's setup statements and the inputs. What zuint sends to an
# engine enters the key as the fingerprint of zuint's own Arrow export, so
# a change to what zuint writes finds no recorded answer and fails until it
# is recorded, and so checked, again.

engine_recording <- function() {
  identical(Sys.getenv("ZUINT_ORACLE_RECORD"), "true")
}

engine_state <- new.env(parent = emptyenv())

# The live functions, only when recording; the path is the source tree's.
engine_live <- function() {
  if (is.null(engine_state$live)) {
    root <- normalizePath(testthat::test_path("..", ".."))
    live <- new.env(parent = globalenv())
    sys.source(file.path(root, "tools", "oracle", "live.R"), envir = live)
    engine_state$live <- live
    engine_state$recorded <- list()
    engine_state$root <- root
    withr::defer(engine_save(), envir = testthat::teardown_env())
  }
  engine_state$live
}

engine_fixture <- function() {
  if (is.null(engine_state$fixture)) {
    engine_state$fixture <- readRDS(testthat::test_path(
      "fixtures",
      "engines.rds"
    ))
  }
  engine_state$fixture
}

# Text that determines a value exactly and is the same on every platform:
# numbers by their bytes, strings with their lengths, zuint vectors by class
# and text.
engine_canon <- function(x) {
  if (inherits(x, "zu_decimal")) {
    return(paste0(
      "dec(",
      decimal_precision(x),
      ",",
      decimal_scale(x),
      ")",
      engine_canon(as.character(x))
    ))
  }
  if (inherits(x, c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128"))) {
    return(paste0(class(x)[[1L]], engine_canon(as.character(x))))
  }
  if (is.list(x)) {
    return(paste0(
      "list",
      length(x),
      "[",
      paste(
        paste0(
          engine_canon(if (is.null(names(x))) character() else names(x)),
          "=",
          vapply(x, engine_canon, "")
        ),
        collapse = ";"
      ),
      "]"
    ))
  }
  body <- if (is.null(x)) {
    ""
  } else if (is.character(x)) {
    paste(
      ifelse(is.na(x), "NA", paste0(nchar(x, "bytes"), ":", enc2utf8(x))),
      collapse = ","
    )
  } else if (is.raw(x)) {
    paste(as.character(x), collapse = "")
  } else if (is.atomic(x)) {
    # the bits, little-endian: the same on every platform, where sprintf("%a")
    # writes a subnormal differently on glibc and macOS
    if (is.factor(x)) {
      return(paste0("factor", engine_canon(as.character(x))))
    }
    v <- as.vector(unclass(x))
    paste(
      as.character(writeBin(v, raw(), endian = "little")),
      collapse = ""
    )
  } else {
    stop("engine_canon() cannot key a ", typeof(x))
  }
  paste0(typeof(x), length(x), "(", body, ")")
}

engine_key <- function(parts) {
  f <- tempfile()
  on.exit(unlink(f))
  writeBin(charToRaw(enc2utf8(engine_canon(parts))), f)
  unname(tools::md5sum(f))
}

# The recorded answer to one engine call, or, when recording, the live one.
engine_answer <- function(parts, compute) {
  key <- engine_key(parts)
  if (engine_recording()) {
    engine_live()
    value <- compute(engine_state$live)
    old <- engine_state$recorded[[key]]
    if (!is.null(old) && !identical(old, value)) {
      stop("the engine gave two answers to one call: ", key)
    }
    engine_state$recorded[[key]] <- value
    return(value)
  }
  store <- engine_fixture()
  if (!key %in% names(store)) {
    stop(
      "no recorded engine answer for this call; zuint's output or the test ",
      "changed, so record again with tools/oracle/record (",
      key,
      ")",
      call. = FALSE
    )
  }
  store[[key]]
}

engine_save <- function() {
  rec <- engine_state$recorded
  rec <- rec[order(names(rec))]
  live <- engine_state$live
  attr(rec, "provenance") <- live$provenance()
  out <- Sys.getenv("ZUINT_ORACLE_OUT")
  if (!nzchar(out)) {
    out <- file.path(
      engine_state$root,
      "tests",
      "testthat",
      "fixtures",
      "engines.rds"
    )
  }
  saveRDS(rec, out, version = 3L, compress = "xz")
}

# What zuint hands an engine for each column: its class, the Arrow format
# and type of zuint's export, and the bits.
engine_fingerprint <- function(df) {
  lapply(df, function(x) {
    if (!inherits(x, c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128"))) {
      return(list(class(x), x))
    }
    s <- zu_arrow_tag(zu_arrow_from(x))
    list(class(x), zu_arrow_format(s), zu_arrow_type(s), zu_storage(x))
  })
}

# ---- DuckDB ------------------------------------------------------------------

# A DuckDB connection: its setup statements, and when recording the live
# connection, closed when the calling test ends.
local_duckdb_plain <- function(env = parent.frame()) {
  con <- new.env(parent = emptyenv())
  con$setup <- character()
  if (engine_recording()) {
    con$db <- engine_live()$connect()
    withr::defer(engine_state$live$disconnect(con$db), envir = env)
  }
  con
}

# The same, for the Arrow paths through zuarrow, with
# arrow_lossless_conversion on unless asked otherwise.
local_duckdb <- function(lossless = TRUE, env = parent.frame()) {
  skip_without_zuarrow()
  con <- local_duckdb_plain(env = env)
  if (lossless) {
    duck_setup(con, "SET arrow_lossless_conversion = true")
  }
  con
}

duck_setup <- function(con, sql) {
  con$setup <- c(con$setup, sql)
  if (engine_recording()) {
    engine_state$live$execute(con$db, sql)
  }
  invisible(con)
}

# A query's result as a data frame.
duck_query <- function(con, sql) {
  engine_answer(list("query", con$setup, sql), function(live) {
    live$query(con$db, sql)
  })
}

# DuckDB's type of an expression, as "DECIMAL(p,s)", or "ERROR" when it
# refuses the types (a binder or out-of-range error); any other error is
# the test's own bug (#136) and is raised when recording.
duck_typeof <- function(con, expr) {
  engine_answer(list("typeof", con$setup, expr), function(live) {
    live$type_of(con$db, expr)
  })
}

# expr over a data frame registered as a table, one row per row of df, in
# order.
duck_df <- function(con, df, expr) {
  engine_answer(list("df", con$setup, df, expr), function(live) {
    live$over_df(con$db, df, expr)
  })
}

# One SQL expression over a column `x` of `values`, in their order (NA
# where DuckDB's TRY_CAST gives NULL).
duck_eval <- function(con, values, expr) {
  df <- data.frame(x = values, stringsAsFactors = FALSE)
  duck_df(con, df, expr)
}

# A query's result through DuckDB's Arrow export and zuarrow. The export is
# recorded as the Arrow IPC stream nanoarrow writes of it.
duckdb_to_r <- function(con, sql, ...) {
  bytes <- engine_answer(list("arrow", con$setup, sql), function(live) {
    live$arrow_bytes(con$db, sql)
  })
  zuarrow::arrow_read(bytes, ...)
}

# The answers to `queries` once the data frames `tables` are registered
# with DuckDB through zuarrow (R to DuckDB). The key holds each table's
# fingerprint, so what DuckDB answered is about the bytes zuint writes now.
duck_receive <- function(con, tables, queries) {
  skip_without_zuarrow()
  fp <- lapply(tables, engine_fingerprint)
  engine_answer(list("receive", con$setup, fp, queries), function(live) {
    live$receive(con$db, tables, queries)
  })
}

# ---- Arrow and Parquet ---------------------------------------------------------

# A check that runs in the arrow package on a data frame zuint wrote through
# zuarrow (tools/oracle/live.R names them), with its answer recorded.
arrow_check <- function(check, df, ...) {
  skip_without_zuarrow()
  args <- list(...)
  engine_answer(
    list("arrow-check", check, engine_fingerprint(df), args),
    function(live) do.call(live[[check]], c(list(df), args))
  )
}

# An Arrow IPC stream another writer made (tools/oracle/live.R names it).
arrow_bytes <- function(make, ...) {
  args <- list(...)
  engine_answer(list("arrow-bytes", make, args), function(live) {
    do.call(live[[make]], args)
  })
}
