source("pre.R")
p <- function(x) format(x, digits = 17)
for (f in list(int128, uint128, int64)) {
  cat(p(mean(f(c(0,2,3)))), p(mean(c(0,2,3))), "|", p(mean(f(c(1,1,2)))), p(4/3), "|", p(mean(f(1:7))), "|", p(mean(f(c(1,2,4,4,4,4,4)))), p(23/7), "|",  p(mean(f(c(10,10,11)))), p(31/3), "\n")
}
x <- c(0,2,3); cat(mean(int128(x)) == mean(x), mean(int64(x)) == mean(x), "\n")
set.seed(2); bad <- 0; for (i in 1:2000) { v <- sample(0:1000, sample(2:9,1), TRUE); if (mean(int128(v)) != sum(v)/length(v)) bad <- bad + 1 }; cat("int128 small-value mean != sum/n in", bad, "of 2000\n")
bad <- 0; for (i in 1:2000) { v <- sample(0:1000, sample(2:9,1), TRUE); if (mean(int64(v)) != sum(v)/length(v)) bad <- bad + 1 }; cat("int64:", bad, "\n")
T(median(int128(c(1,2)))); T(p(median(int128(c(0,2,3,4)))))
T(p(mean(uint64(c("4294967296","10","114477108840258782")))))
print(as.bigq(sum(as.bigz(c("4294967296","10","114477108840258782"))), 3))
