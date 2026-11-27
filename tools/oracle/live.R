# The live engines behind tests/testthat/helper-engines.R, sourced only when
# recording (ZUINT_ORACLE_RECORD=true; see README.md). Everything that loads
# DuckDB, DBI, nanoarrow or arrow is here, so the package's tests and its
# DESCRIPTION name none of them.

stopifnot(
  requireNamespace("DBI", quietly = TRUE),
  requireNamespace("duckdb", quietly = TRUE),
  packageVersion("duckdb") >= "2.0.1",
  requireNamespace("nanoarrow", quietly = TRUE),
  requireNamespace("arrow", quietly = TRUE),
  requireNamespace("zuarrow", quietly = TRUE)
)

provenance <- function() {
  pkgs <- c("duckdb", "DBI", "nanoarrow", "arrow", "zuarrow")
  list(
    recorded = format(Sys.time(), "%Y-%m-%d", tz = "UTC"),
    r = R.version.string,
    packages = vapply(pkgs, function(p) as.character(packageVersion(p)), "")
  )
}

# Table names come from a counter, never from the RNG, so that recording
# draws the same random inputs as replaying.
counter <- 0L
table_name <- function() {
  counter <<- counter + 1L
  sprintf("zu_oracle_%d", counter)
}

connect <- function() DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)) # #74

disconnect <- function(db) DBI::dbDisconnect(db, shutdown = TRUE)

execute <- function(db, sql) invisible(DBI::dbExecute(db, sql))

query <- function(db, sql) DBI::dbGetQuery(db, sql)

type_of <- function(db, expr) {
  tryCatch(
    DBI::dbGetQuery(db, sprintf("SELECT typeof(%s) AS t", expr))$t,
    error = function(e) {
      # only DuckDB refusing the types (a scale past 38 is out of range); a
      # broken query is the test's own bug (#136)
      if (!grepl("^(Binder|Out of Range) Error", conditionMessage(e))) {
        stop(e)
      }
      "ERROR"
    }
  )
}

over_df <- function(db, df, expr) {
  df$i <- seq_len(nrow(df))
  name <- table_name()
  duckdb::duckdb_register(db, name, df)
  on.exit(duckdb::duckdb_unregister(db, name), add = TRUE)
  sql <- sprintf("SELECT %s AS r FROM %s ORDER BY i", expr, name)
  DBI::dbGetQuery(db, sql)$r
}

# DuckDB's Arrow export of a query, as the IPC stream nanoarrow writes. The
# stream must read back through zuarrow exactly as the live export does.
arrow_bytes <- function(db, sql) {
  path <- tempfile(fileext = ".arrows")
  on.exit(unlink(path))
  nanoarrow::write_nanoarrow(DBI::dbGetQueryArrow(db, sql), path)
  bytes <- readBin(path, "raw", file.size(path))
  live <- zuarrow::arrow_to_r(DBI::dbGetQueryArrow(db, sql), lossy = "allow")
  replayed <- zuarrow::arrow_read(bytes, lossy = "allow")
  if (!identical(live, replayed)) {
    stop("the recorded IPC stream reads differently from the live export")
  }
  bytes
}

# An arrow Table of a data frame, from zuarrow's IPC stream, so arrow never
# makes an R object of the arrow.opaque type (apache/arrow#53951).
arrow_table_of <- function(df) {
  raw <- zuarrow::arrow_write(df, NULL, format = "stream")
  arrow::read_ipc_stream(raw, as_data_frame = FALSE)
}

# DuckDB scans a registered reader only once, so a Table is registered.
receive <- function(db, tables, queries) {
  for (name in names(tables)) {
    duckdb::duckdb_register_arrow(db, name, arrow_table_of(tables[[name]]))
  }
  lapply(queries, function(sql) DBI::dbGetQuery(db, sql))
}

# ---- the round-trip matrix (test-roundtrip.R) --------------------------------

# DuckDB's Arrow export of the matrix as arrow writes it to IPC: what the
# Arrow path reads.
matrix_arrow_bytes <- function(setup, sql) {
  db <- connect()
  on.exit(disconnect(db))
  for (s in setup) {
    execute(db, s)
  }
  t0 <- arrow::as_arrow_table(DBI::dbGetQueryArrow(db, sql))
  arrow::write_to_raw(t0, format = "stream")
}

# Does the table zuint wrote equal, schema and values, the one it read?
arrow_same_table <- function(df, bytes) {
  t0 <- arrow::read_ipc_stream(bytes, as_data_frame = FALSE)
  t1 <- arrow_table_of(df)
  list(schema = t1$schema$Equals(t0$schema), values = t1$Equals(t0))
}

# The Parquet file arrow writes of what zuint wrote, read back by arrow, as
# IPC: what the Parquet path reads.
parquet_bytes <- function(df) {
  f <- tempfile(fileext = ".parquet")
  on.exit(unlink(f))
  arrow::write_parquet(arrow_table_of(df), f)
  arrow::write_to_raw(arrow::read_parquet(f, as_data_frame = FALSE), "stream")
}

# Does zuint's data frame, through Parquet again, give the same table?
parquet_same_table <- function(df, bytes) {
  t1 <- arrow::read_ipc_stream(bytes, as_data_frame = FALSE)
  f <- tempfile(fileext = ".parquet")
  on.exit(unlink(f))
  arrow::write_parquet(arrow_table_of(df), f)
  t2 <- arrow::read_parquet(f, as_data_frame = FALSE)
  list(schema = t2$schema$Equals(t1$schema), values = t2$Equals(t1))
}

# ---- decimal128 imports (test-arrow.R) ---------------------------------------

# nanoarrow's decimal128(p, 0) array of `values`, as IPC.
decimal_bytes <- function(values, p) {
  a <- nanoarrow::as_nanoarrow_array(
    data.frame(x = values),
    schema = nanoarrow::na_struct(list(x = nanoarrow::na_decimal128(p, 0L)))
  )
  path <- tempfile(fileext = ".arrows")
  on.exit(unlink(path))
  nanoarrow::write_nanoarrow(a, path)
  readBin(path, "raw", file.size(path))
}
