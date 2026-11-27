source("pre.R")
s <- sort(decimal128(c("0.5", "-0.5", "0", "-99999999999999999999999999999999.999999", "99999999999999999999999999999999.999999", "0.000001", "-0.000001", "0.5"), 38, 6))
P(s[-1] >= s[-8]); P(is.unsorted(s)); P(base:::.gtn(s, FALSE))
P(is.unsorted(decimal128(c("-1","1"),5,0))); P(is.unsorted(decimal128(c("-1","0"),5,0))); P(is.unsorted(decimal128(c("-2","-1"),5,0))); P(is.unsorted(decimal128(c("0","0"),5,0))); P(is.unsorted(decimal128(c("1","1"),5,0)));P(is.unsorted(decimal128(c("1","1"),5,0), strictly=TRUE)); P(is.unsorted(int128(c(-2,-1)))); P(is.unsorted(int128(c(1,1))))
