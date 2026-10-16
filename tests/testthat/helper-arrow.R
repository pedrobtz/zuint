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
  stream <- nanoarrow::as_nanoarrow_array_stream(duckdb::duckdb_fetch_arrow(res))
  batch <- stream$get_next()
  DBI::dbClearResult(res)
  col <- batch$children[[1L]]
  list(array = col, schema = nanoarrow::infer_nanoarrow_schema(col))
}
