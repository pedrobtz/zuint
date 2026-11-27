H <- "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zuint/28dad52f-4719-4564-8f70-fc75a74a7618/scratchpad/hunt"
lib <- Sys.getenv("ZLIB", file.path(H, "lib"))
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages({library(zuint); library(nanoarrow)})
loadNamespace("zuarrow")
# little-endian bytes of a big integer string (two's complement), width bytes
le <- function(s, width) {
  z <- gmp::as.bigz(s); if (z < 0) z <- z + gmp::as.bigz(2)^(8 * width)
  b <- raw(width)
  for (i in seq_len(width)) { b[i] <- as.raw(as.integer(z %% 256)); z <- z %/% 256 }
  b
}
bytes <- function(v, width) unlist(lapply(v, le, width = width))
bitmap <- function(valid) { n <- length(valid); v <- c(valid, rep(FALSE, (8 - n %% 8) %% 8)); packBits(v, "raw") }
mk <- function(schema, data, length, valid = NULL, offset = 0, null_count = NULL) {
  a <- nanoarrow_array_init(schema)
  if (is.null(null_count)) null_count <- if (is.null(valid)) 0 else -1
  nanoarrow_array_modify(a, list(length = length, null_count = null_count, offset = offset,
    buffers = list(if (is.null(valid)) NULL else valid, data)), validate = FALSE)
}
opaque <- function(type_name = "hugeint", vendor = "DuckDB", json = NULL, storage = na_fixed_size_binary(16)) {
  if (is.null(json)) json <- sprintf('{"type_name":"%s","vendor_name":"%s"}', type_name, vendor)
  na_extension(storage, "arrow.opaque", json)
}
try_ <- function(expr) tryCatch(withCallingHandlers(expr, warning = function(w) {cat("  WARN[", class(w)[1], "]:", conditionMessage(w), "\n"); invokeRestart("muffleWarning")}), error = function(e) {cat("  ERR[", class(e)[1], "]:", conditionMessage(e), "\n"); invisible(NULL)})
show <- function(x) { cat("  <", paste(class(x), collapse = ","), "> ", paste(format(x), collapse = " "), "\n", sep = "") }
# a one-column struct stream -> arrow Table via IPC bytes written by nanoarrow
struct1 <- function(schema, child, n, name = "x") {
  l <- list(child); names(l) <- name; sl <- list(schema); names(sl) <- name
  nanoarrow_array_modify(nanoarrow_array_init(na_struct(sl)), list(length = n, null_count = 0, children = l), validate = FALSE)
}
to_arrow_tbl <- function(batch) { f <- tempfile(); write_nanoarrow(batch, f); arrow::read_ipc_stream(f, as_data_frame = FALSE) }
duck_view <- function(con, tbl, cols = "x") {
  duckdb::duckdb_register_arrow(con, "t", tbl); on.exit(duckdb::duckdb_unregister_arrow(con, "t"))
  DBI::dbGetQuery(con, sprintf("SELECT %s FROM t", paste(sprintf("typeof(%s) t_%s, %s::VARCHAR v_%s", cols, cols, cols, cols), collapse = ", ")))
}
