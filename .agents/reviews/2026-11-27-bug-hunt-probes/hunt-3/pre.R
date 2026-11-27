LIB <- Sys.getenv("ZLIB", "/private/tmp/claude-501/-Users-pbtz-src-github-com-pedrobtz-zuint/28dad52f-4719-4564-8f70-fc75a74a7618/scratchpad/hunt/lib")
.libPaths(c(LIB, .libPaths()))
suppressPackageStartupMessages(library(zuint))
p <- function(...) { cat(..., "\n") }
show <- function(label, expr) {
  cat("##", label, "\n")
  r <- tryCatch(withCallingHandlers(expr, warning=function(w){cat("  [warning:", class(w)[1], conditionMessage(w), "]\n"); invokeRestart("muffleWarning")}), error=function(e) {cat("  [error:", class(e)[1], conditionMessage(e), "]\n"); invisible(NULL)})
  if (!is.null(r)) { if (inherits(r, c("zu_int64","zu_uint64","zu_int128","zu_uint128","zu_decimal128"))) { cat("  <", class(r)[1], "> ", paste(format(r), collapse=" "), if(!is.null(names(r))) paste(" names:", paste(names(r), collapse=",")), "\n") } else print(r) }
  invisible(r)
}
i64e <- int64(c("-9223372036854775807","-2","-1","0","1","9007199254740993","9223372036854775807",NA))
u64e <- uint64(c("0","1","9007199254740993","18446744073709551614","9223372036854775808","18446744073709549568",NA))
i128e <- int128(c("-170141183460469231731687303715884105727","-2","-1","0","1","18446744073709551616","170141183460469231731687303715884105727",NA))
u128e <- uint128(c("0","1","18446744073709551616","340282366920938463463374607431768211454","170141183460469231731687303715884105728",NA))
