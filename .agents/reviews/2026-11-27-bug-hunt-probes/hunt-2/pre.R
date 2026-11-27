lib <- Sys.getenv("ZLIB", "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zuint/28dad52f-4719-4564-8f70-fc75a74a7618/scratchpad/hunt/lib")
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages({library(zuint); library(gmp)})
T <- function(expr) {
  cat("> ", deparse(substitute(expr))[1], "\n")
  r <- tryCatch(withCallingHandlers(expr, warning = function(w) {cat("  [W", class(w)[1], "] ", conditionMessage(w), "\n"); invokeRestart("muffleWarning")}),
    error = function(e) {cat("  [E", class(e)[1], "] ", conditionMessage(e), "\n"); invisible(NULL)})
  if (!is.null(r)) print(r)
  invisible(r)
}
