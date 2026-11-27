source("pre.R")
d <- decimal128(c("100000.00", "1.25", "0.10"), 12, 2)
P(d %in% c(100000, 1.25, 0.1)); P(d == c(100000, 1.25, 0.1)); P(zu_match(d, c(100000, 1.25, 0.1)))
P(int128(100000) %in% 100000)
options(scipen = -5); P(d %in% c(100000, 1.25, 0.1)); P(d %in% c(100000L, 1L))
options(scipen = 0, OutDec = ","); P(d %in% c(100000, 1.25, 0.1))
options(OutDec = ".", scipen = 100); P(d %in% c(100000, 1.25, 0.1))
options(scipen=0)
# data frame merge / factor / table with double key
P(merge(data.frame(k = decimal128(c("100000","2"), 10, 0), a = 1:2), data.frame(k = c(100000, 2), b = 3:4)))
# mean accuracy
suppressPackageStartupMessages(library(gmp))
set.seed(5)
bad <- 0; badm <- 0
for (i in 1:3000) { s <- sample(0:38, 1); n <- sample(1:38, 1); co <- paste(sample(0:9, n, TRUE), collapse = ""); co <- sub("^0+(?=.)", "", co, perl = TRUE)
  txt <- if (s == 0) co else { c2 <- paste0(strrep("0", max(0, s + 1 - nchar(co))), co); paste0(substr(c2, 1, nchar(c2) - s), ".", substr(c2, nchar(c2) - s + 1, nchar(c2))) }
  x <- decimal128(txt, 38, s)
  want <- as.numeric(txt)   # R's strtod: correctly rounded? compare to gmp
  wq <- as.numeric(as.bigq(as.bigz(co), as.bigz(10)^s))
  got <- as.double(x)
  if (!identical(got, wq)) { bad <- bad + 1; if (bad <= 5) cat("as.double", txt, s, sprintf("%.17g %.17g %.17g", got, wq, want), "\n") }
  m <- mean(x); if (!identical(m, got)) { badm <- badm + 1; if (badm <= 5) cat("mean != as.double", txt, s, sprintf("%.17g %.17g", m, got), "\n") }
}
cat("as.double bad", bad, " mean!=as.double", badm, "\n")
