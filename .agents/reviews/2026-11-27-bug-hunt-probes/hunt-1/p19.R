source("pre.R")
suppressPackageStartupMessages(library(gmp))
set.seed(9)
coef <- function(d) { z <- as.character(d); z[!is.na(z)] <- sub("^(-?)0+(?=[0-9])", "\\1", gsub(".", "", z[!is.na(z)], fixed=TRUE), perl=TRUE); as.bigz(z) }
totext <- function(co, s) { neg <- co < 0; a <- as.character(abs(co)); if (s > 0) { a <- paste0(strrep("0", pmax(0, s - nchar(a) + 1)), a); a <- paste0(substr(a,1,nchar(a)-s), ".", substr(a, nchar(a)-s+1, nchar(a))) }; paste0(ifelse(neg, "-", ""), a) }
nb <- 0; bad <- function(...) { nb <<- nb + 1; if (nb < 15) cat(..., "\n") }
for (it in 1:1500) {
  p <- sample(c(1, 5, 18, 19, 37, 38), 1); s <- sample(c(0, p, sample(0:p, 1)), 1); n <- sample(c(0, 1, 2, 5, 50), 1)
  co <- as.bigz(vapply(seq_len(n), function(i) paste0(sample(c("", "-"), 1), sub("^0+(?=.)", "", paste(sample(0:9, sample(c(p, p, sample(p, 1)), 1), TRUE), collapse = ""), perl = TRUE)), ""))
  if (n == 0) co <- as.bigz(integer())
  x <- if (n) decimal128(totext(co, s), p, s) else decimal128(character(), p, s)
  if (n) stopifnot(all(coef(x) == co))
  lim <- as.bigz(10)^38
  # sum
  r <- suppressWarnings(sum(x)); ex <- if (n) sum(co) else as.bigz(0)
  if (decimal_precision(r) != 38 || decimal_scale(r) != s) bad("sumtype", p, s)
  if (abs(ex) < lim) { if (is.na(r) || coef(r) != ex) bad("sum", p, s, n, as.character(r), as.character(ex)) } else if (!is.na(r)) bad("sum-ovf", p, s, as.character(r))
  if (n) {
    cs <- suppressWarnings(cumsum(x)); ecs <- cumsum(co); okc <- abs(ecs) < lim; firstbad <- which(!okc)[1]; if (!is.na(firstbad)) okc[firstbad:n] <- FALSE
    g <- coef(cs); if (!all(ifelse(okc, !is.na(g) & g == ecs, is.na(g)))) bad("cumsum", p, s, n)
    if (coef(min(x)) != min(co) || coef(max(x)) != max(co)) bad("minmax", p, s)
    if (!all(coef(sort(x)) == sort(co))) bad("sort", p, s)
    if (!identical(order(x), order(as.numeric(rank(co, ties.method = "min"))))) { o <- order(x); if (!all(co[o] == sort(co))) bad("order", p, s) }
    if (!all(coef(-x) == -co)) bad("neg", p, s); if (!all(coef(abs(x)) == abs(co))) bad("abs", p, s)
    ecm <- co; for (i in seq_len(n)[-1]) if (ecm[i - 1] > ecm[i]) ecm[i] <- ecm[i - 1]
    if (!all(coef(cummax(x)) == ecm)) bad("cummax", p, s)
    if (!identical(duplicated(x), duplicated(as.character(co)))) bad("dup", p, s)
    # mean vs exact
    m <- mean(x); em <- as.numeric(as.bigq(sum(co), as.bigz(10)^s * n)); if (abs(m - em) > 4 * abs(em) * .Machine$double.eps) bad("mean", p, s, n, sprintf("%.17g %.17g", m, em))
    md <- median(x); sc <- sort(co); emd <- if (n %% 2) as.bigq(sc[(n + 1) / 2], as.bigz(10)^s) else as.bigq(sc[n / 2] + sc[n / 2 + 1], 2 * as.bigz(10)^s); emd <- as.numeric(emd)
    if (abs(md - emd) > 4 * abs(emd) * .Machine$double.eps) bad("median", p, s, n, sprintf("%.17g %.17g", md, emd), totext(co, s)[seq_len(min(n, 3))])
    # conversions
    i1 <- suppressWarnings(int128(x)); whole <- (co %% (as.bigz(10)^s)) == 0; ev <- co %/% (as.bigz(10)^s)
    gi <- as.bigz(as.character(i1)); if (!all(ifelse(whole, !is.na(gi) & gi == ev, is.na(gi)))) bad("int128", p, s)
    i2 <- suppressWarnings(as.integer(x)); fits <- whole & abs(ev) <= 2147483647; if (!all(ifelse(fits, !is.na(i2) & i2 == as.numeric(ev), is.na(i2)))) bad("as.integer", p, s)
    # rescale to random type vs exact half-away
    p2 <- sample(38, 1); s2 <- sample(0:p2, 1); r2 <- suppressWarnings(decimal128(x, p2, s2))
    num <- co * as.bigz(10)^max(0, s2 - s); den <- as.bigz(10)^max(0, s - s2)
    qd <- abs(num) %/% den; rem <- abs(num) %% den; qd <- qd + (2 * rem >= den); e2 <- sign(num) * qd; ok2 <- abs(e2) < as.bigz(10)^p2
    g2 <- coef(r2); if (!all(ifelse(ok2, !is.na(g2) & g2 == e2, is.na(g2)))) bad("rescale", p, s, "->", p2, s2)
    # mtfrm equals value
    mt <- mtfrm(x); if (!all(as.bigq(sub("\\..*", "", mt)) * 0 == 0)) bad("mt")
    back <- suppressWarnings(decimal128(mt, 38, s)); if (!all(coef(back) == co)) bad("mtfrm-roundtrip", p, s)
    if (s > 0 && any(grepl("\\.$|\\..*0$|^-?\\.", mt))) bad("mtfrm-form", p, s, mt[1])
  }
}
cat("nbad", nb, "\n")
