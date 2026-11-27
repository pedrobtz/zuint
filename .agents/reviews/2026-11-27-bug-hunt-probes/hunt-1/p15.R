source("pre.R")
suppressPackageStartupMessages(library(gmp))
set.seed(8)
nb <- 0
for (it in 1:6000) {
  s <- sample(0:38, 1); n <- sample(1:38, 1)
  co <- sub("^0+(?=.)", "", paste(sample(0:9, n, TRUE), collapse = ""), perl = TRUE)
  sg <- sample(c("", "-"), 1)
  c2 <- paste0(strrep("0", max(0, s + 1 - nchar(co))), co)
  txt <- paste0(sg, if (s == 0) co else paste0(substr(c2, 1, nchar(c2) - s), ".", substr(c2, nchar(c2) - s + 1, nchar(c2))))
  x <- decimal128(txt, 38, s)
  q <- as.bigq(as.bigz(paste0(sg, co)), as.bigz(10)^s)
  v0 <- as.double(x)
  ulp <- if (v0 == 0) 4.9e-324 else 2^(floor(log2(abs(v0))) - 52)
  vs <- c(v0, v0 + ulp, v0 - ulp, v0 * 2, -v0, trunc(v0), trunc(v0) + 0.5, 0, v0 + sample(c(-1, 1), 1) * runif(1) * abs(v0) * 1e-10, round(v0, s), 1e38, -1e38, 1e39, .Machine$double.xmax, 5e-324, -5e-324, 2^-1074 * 3)
  for (v in vs) {
    want <- sign(q - as.bigq(v)); want <- as.integer(as.numeric(want))
    got <- c(x < v, x == v, x > v); g2 <- c(v > x, v == x, v < x)
    exp <- c(want < 0, want == 0, want > 0)
    if (!identical(got, exp) || !identical(g2, exp)) { nb <- nb + 1; if (nb <= 10) cat("CMP", txt, s, sprintf("%.17g", v), "got", got, "want", exp, "\n") }
  }
}
cat("cmp bad", nb, "\n")
# zu_match with doubles exactness
x <- decimal128(c("0.5", "0.1", "0.25", "123456789.125"), 20, 3)
P(zu_match(x, c(0.25, 0.5, 123456789.125, 0.1))); P(zu_match(c(0.25, 0.5, 123456789.125, 0.1, 1e-320, 1e308, -1e308), x))
