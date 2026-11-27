mode <- commandArgs(TRUE)[1]
source("pre.R")
if (mode == "attached") suppressPackageStartupMessages(library(bit64)) else if (mode == "loaded") invisible(loadNamespace("bit64"))
b <- as_integer64(int64(c(-2,-1,0,3, NA))); u <- uint64(c(5,5,5,5,5)); i8 <- int128(c(5,5,5,5,5)); u8 <- uint128(c(5,5,5,5,5)); z <- int64(c(5,5,5,5,5))
for (op in c("+","-","*","/","%/%","%%","^","==","!=","<","<=",">",">=","&","|")) for (nm in c("z","u","i8","u8")) {
  w <- get(nm); f <- get(op)
  r <- function(e) tryCatch(withCallingHandlers({v <- e; paste0(class(v)[1], ":", paste(if (is.object(v)) format(v) else format(v, digits=6), collapse=","))}, warning=function(w) invokeRestart("muffleWarning")), error=function(e) paste("ERR", class(e)[1]))
  cat(sprintf("%-4s %-3s b op w: %-45s | w op b: %s\n", op, nm, r(f(b, w)), r(f(w, b))))
}
cat("idx:", format(letters[int64(2)]), "|", format((1:10)[uint64(3)]), "|", format(z[int64(2)]), "|", format(u8[uint64(1:2)]), "|", format(int64(1:5)[int128(2)]), "|", tryCatch(format(list(1,2)[[int64(2)]]), error=function(e) "ERR"), "\n")
x <- int64(1:5); x[int64(2)] <- 9L; cat(format(x), "\n")
cat(format(rep(int64(1), times=int64(3))), "|", format(rep_len(int64(1), int64(2))), "|", format(head(int64(1:5), int64(2))), "|", format(seq_len(int64(3))), "\n")
