lib <- Sys.getenv("ZLIB", "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zuint/28dad52f-4719-4564-8f70-fc75a74a7618/scratchpad/hunt/lib")
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(zuint))
P <- function(expr) {
  cat(">> ", deparse(substitute(expr), width.cutoff = 200L)[1], "\n")
  r <- withCallingHandlers(tryCatch({v <- expr; print(v); if (is_decimal128(v)) cat("   type:", decimal_precision(v), decimal_scale(v), "\n"); invisible(v)},
    error = function(e) cat("   ERROR[", class(e)[1], "]:", conditionMessage(e), "\n")),
    warning = function(w) {cat("   WARN[", class(w)[1], "]:", conditionMessage(w), "\n"); invokeRestart("muffleWarning")})
  invisible(r)
}
duck <- function() DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
