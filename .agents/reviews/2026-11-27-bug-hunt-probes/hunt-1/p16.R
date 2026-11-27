source("pre.R")
x <- decimal128(c("1.25","-1.25","99.99", NA), 5, 2)
for (pol in c("allow", "warn", "error", "bogus")) { options(zuint.double = pol); cat("=== zuint.double =", pol, "\n")
  P(x + 1.5); P(c(x, 1.5)); P({y <- x; y[1] <- 1.005; y}); P({y <- x; y[1] <- 1.015; y}); P({y <- x; y[[1]] <- 1e10; y}); P(sum(x, 1.5, na.rm = TRUE)); P(max(x, 1.5, na.rm=TRUE)); P(range(x, 0.5, na.rm = TRUE)); P(zu_ifelse(c(TRUE, FALSE), x[1], 1.5)); P(zu_vapply(1:2, function(i) 1.005, x[1])); P(x * Inf); P(x - NaN); P(c(x, Inf)); P(c(a = x[1], b = 1.5)); P(zu_match(x, 1.5))
}
options(zuint.double = NULL)
# precision only
P(decimal128(x, 1)); P(decimal128(x, 2)); P(decimal128(x, scale = 6)); P(decimal128(x, scale = 0)); P(decimal128(x, 38, 36)); P(decimal128(x, 38, 37))
# names in ops
a <- decimal128(c(p = "1.5", q = "2.5"), 5, 1); b <- decimal128(c(r = "1", s = "2", t = "3", u = "4"), 5, 0)
P(a + b); P(b + a); P(a * 2L); P(a == b); P(a / b); P(a + c(z = 1L)); P(unname(a) + c(z = 1L, y = 2L))
# class / attributes afterwards
P(attributes(a + b)); P(attributes(sum(a))); P(attributes(round(a))); P(attributes(a[1])); P(attributes(c(a, b))); P(attributes(rev(a))); P(attributes(unique(a))); P(attributes(sort(a))); P(attributes(-a)); P(attributes(abs(a))); P(attributes(cumsum(a))); P(attributes(floor(a))); P(attributes(rep(a, 2))); P(attributes(zu_ifelse(c(TRUE, FALSE), a, b[1:2]))); P(attributes(range(a))); P(attributes(min(a))); P(attributes(decimal128(a, 10, 3))); P(attributes(decimal128(a))); P(attributes(diff(a)))
# custom attribute survive?
w <- a; attr(w, "units") <- "EUR"; P(attributes(w[1])); P(attributes(w + 1L)); P(attributes(decimal128(w, 10, 2)))
# saveRDS round trip, identical, all.equal
f <- tempfile(); saveRDS(x, f); P(identical(readRDS(f), x)); P(all.equal(x, x)); P(all.equal(x, x + 0L)); P(all.equal(x, decimal128(c("1.25","-1.25","99.98", NA), 5, 2))); P(all.equal(x, 1)); P(isTRUE(all.equal(decimal128("1.0",5,1), decimal128("1.00",5,2)))); P(all.equal(1, x)); P(identical(x, decimal128(as.character(x), 5, 2))); P(dput(x[1]))
P(all.equal(x, decimal128(c("1.25","-1.25","99.99", "5"), 5, 2))); P(all.equal(x[4], x[4]))
# is.na<- and NA assignment
y <- x; is.na(y) <- 1:2; P(y); y[3] <- NA_real_; P(y); y[3] <- NA_integer_; P(y); P(x[NA_integer_]); P(x[c(NA, 1)]); P(x[10]); P({y <- x; y[10] <- x[1]; y}); P({y <- x[0]; y[3] <- 1L; y}); P({y <- x; length(y) <- 0; y}); P({y <- x; length(y) <- NA; y}); P({y <- x; length(y) <- 2.9; y}); P({y <- x; length(y) <- -1; y})
# sort/order: big/negative and decreasing with ties, xtfrm NA
s <- decimal128(c("0.5", "-0.5", "0", NA, "-99999999999999999999999999999999.999999", "99999999999999999999999999999999.999999", "0.000001", "-0.000001", "0.5"), 38, 6)
P(sort(s)); P(order(s)); P(order(s, decreasing = TRUE)); P(order(s, na.last = NA)); P(sort(s, decreasing = TRUE)); P(sort(s, na.last = FALSE)); P(rank(s)); P(order(s, c(1,1,1,1,1,1,1,1,0))); P(max(s, na.rm = TRUE)); P(min(s, na.rm = TRUE)); P(which.min(s)); P(range(s, na.rm = TRUE)); P(sort(s, method = "radix")); P(sort(s, index.return = TRUE)); P(sort(s, partial = 2)); P(rev(sort(s))[1]); P(is.unsorted(s)); P(is.unsorted(sort(s))); P(median(s, na.rm = TRUE)); P(quantile(s, na.rm = TRUE)); P(cummax(s)); P(cummin(s[-4])); P(unique(s)); P(duplicated(s)); P(duplicated(s, fromLast = TRUE)); P(unique(s, fromLast = TRUE)); P(table(s)); P(rle(s)); P(tabulate(s)); P(findInterval(s, s)); P(max(s[4])); P(max(s[4], na.rm = TRUE)); P(sum(s[4], na.rm=TRUE)); P(mean(s[4], na.rm = TRUE)); P(prod(s[4], na.rm=TRUE))
