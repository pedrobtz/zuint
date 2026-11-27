source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
duck <- function(schema, data, n) {
  # via arrow IPC -> arrow Table -> duckdb
  st <- basic_array_stream(list(mk(na_struct(list(x = schema)), NULL, n) -> s0), validate = FALSE)
  NULL
}
vals <- c("1", "-2")
data <- bytes(vals, 16)
mdraw <- function(pairs) { # list of key=value (raw or chr), allow repeated
  out <- writeBin(length(pairs), raw(), size = 4, endian = "little")
  for (p in pairs) { k <- charToRaw(p[[1]]); v <- if (is.raw(p[[2]])) p[[2]] else charToRaw(p[[2]])
    out <- c(out, writeBin(length(k), raw(), size = 4, endian = "little"), k, writeBin(length(v), raw(), size = 4, endian = "little"), v) }
  out
}
cases <- list(
  canonical = '{"type_name":"hugeint","vendor_name":"DuckDB"}',
  vendor_first = '{"vendor_name":"DuckDB","type_name":"hugeint"}',
  wrong_vendor = '{"type_name":"hugeint","vendor_name":"Other"}',
  no_vendor = '{"type_name":"hugeint"}',
  spaces = '{ "type_name" : "hugeint" , "vendor_name" : "DuckDB" }',
  upper = '{"type_name":"HUGEINT","vendor_name":"DuckDB"}',
  uuid = '{"type_name":"uuid","vendor_name":"DuckDB"}',
  nested = '{"extra":{"type_name":"hugeint"},"type_name":"uuid","vendor_name":"DuckDB"}',
  value_is_key = '{"vendor_name":"type_name","type_name":"hugeint"}',
  escaped = '{"type_name":"huge\\u0069nt","vendor_name":"DuckDB"}',
  repeated_json = '{"type_name":"hugeint","type_name":"uhugeint","vendor_name":"DuckDB"}',
  truncated = '{"type_name":"hugeint',
  truncated2 = '{"type_name":"hugeint"',
  empty = '', notjson = 'type_name hugeint', array = '["type_name","hugeint"]',
  prefix = '{"type_name":"hugeint128","vendor_name":"DuckDB"}',
  uh = '{"type_name":"uhugeint","vendor_name":"DuckDB"}',
  key_suffix = '{"my_type_name":"x","type_name":"hugeint"}',
  key_in_string = '{"note":"a \\"type_name\\":\\"hugeint\\" b","type_name":"uuid","vendor_name":"DuckDB"}'
)
for (nm in names(cases)) {
  cat(sprintf("%-14s", nm))
  s <- opaque(json = cases[[nm]])
  r <- tryCatch(zuarrow::arrow_to_r(mk(s, data, 2)), error = function(e) e)
  if (inherits(r, "error")) cat(" zuint: ERR", class(r)[1], substr(conditionMessage(r), 1, 90)) else cat(" zuint:", class(r)[1], paste(format(r), collapse = ","))
  # duckdb's view
  d <- tryCatch({ r <- duck_view(con, to_arrow_tbl(struct1(s, mk(s, data, 2), 2))); paste(r$t_x[1], paste(r$v_x, collapse = ",")) }, error = function(e) paste("ERR", substr(conditionMessage(e), 1, 100)))
  cat(" | duckdb:", d, "\n")
}
