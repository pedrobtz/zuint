source("pre.R")
suppressPackageStartupMessages(library(gmp))
set.seed(6)
exq <- function(d) { # exact rational of a double
  e <- floor(log2(abs(d))) - 60; m <- d / 2^e  # m is integer-valued double? no; use frexp-like
  as.bigq(d) }
stopifnot(as.bigq(0.1) == as.bigq(as.bigz("3602879701896397"), as.bigz(2)^55))
bad <- 0
for (i in 1:4000) { s <- sample(0:38, 1); n <- sample(1:38, 1); co <- paste(sample(0:9, n, TRUE), collapse = ""); co <- sub("^0+(?=.)", "", co, perl = TRUE)
  if (co == "0") next
  txt <- if (s == 0) co else { c2 <- paste0(strrep("0", max(0, s + 1 - nchar(co))), co); paste0(substr(c2, 1, nchar(c2) - s), ".", substr(c2, nchar(c2) - s + 1, nchar(c2))) }
  x <- decimal128(paste0("-", txt), 38, s)
  q <- -as.bigq(as.bigz(co), as.bigz(10)^s)
  got <- as.double(x)
  ulp <- 2^(floor(log2(abs(got))) - 52)
  e0 <- abs(as.bigq(got) - q); lo <- abs(as.bigq(got - ulp) - q); hi <- abs(as.bigq(got + ulp) - q)
  if (e0 > lo || e0 > hi) { bad <- bad + 1; if (bad <= 5) cat("as.double not nearest", txt, s, sprintf("%.17g", got), "\n") }
}
cat("bad", bad, "\n")
