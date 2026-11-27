a <- commandArgs(TRUE); .libPaths(c(a[1], .libPaths())); suppressMessages(library(zuint))
mode <- a[2]; if (mode == "attached") suppressMessages(library(bit64))
p <- function(...) cat(mode, ..., "\n")
B <- function(...) as_integer64(int64(c(...)))
p("loaded?", "bit64" %in% loadedNamespaces())
p("F1a", int64(c(1,1,1)) & B(-1,0,NA))
p("F1b", zu_match(int64(NA), B(-1, NA)))
p("F1c", tryCatch(as.character(vctrs::vec_cast(B(1,NA), int64())), error=function(e) "lossy-error"))
p("F1g", as.character(zu_ifelse(B(1,0,NA,-1), int64(1), int64(2))))
if (mode == "attached") {
  b <- bit64::as.integer64(c(-2, 3)); p("F2", as.character(b * uint64(5)), as.character(b / uint64(5)))
  p("F3", tryCatch({setdiff(int64(c(-2,-1,0)), int64(-2)); "ok"}, error=function(e) "error"))
}
p("F4", as.character(int64(1:2) %*% int64(1:2)))
p("F5", length(rep(int64(1:3), times = int64(2))), length(diff(int64(1:4), lag = int64(2))))
p("F7", as.character(cut(int64(5), c(0, 3, 10))), complete.cases(data.frame(k=int64(c(-1,NA,1)))))
p("F8", tryCatch(as.character(seq(int64(10), int64(1))), error=function(e) "error"))
if (requireNamespace("data.table", quietly=TRUE)) { w <- uint64(c("18446744073709551614","1")); r <- data.table::rbindlist(list(data.table::data.table(a=1), data.table::data.table(a=2, k=w[1])), fill=TRUE)$k; p("F6", is.na(r)) }
