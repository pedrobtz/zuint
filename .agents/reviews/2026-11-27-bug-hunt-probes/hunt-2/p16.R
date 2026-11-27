source("pre.R")
set.seed(21); two <- as.bigz(2)
R <- list(int64 = c(-(two^63 - 1), two^63 - 1), uint64 = c(as.bigz(0), two^64 - 2), int128 = c(-(two^127 - 1), two^127 - 1), uint128 = c(as.bigz(0), two^128 - 2))
common <- function(a, b) { if (a == b) return(a); s <- sort(c(a, b)); k <- paste(s, collapse = "+"); switch(k, "int64+uint64" = "int128", "int128+int64" = "int128", "int128+uint64" = "int128", "uint128+uint64" = "uint128", NA) }
gen <- function(ty, n) { lo <- R[[ty]][1]; hi <- R[[ty]][2]; w <- if (grepl("64", ty)) 64 else 128
  v <- c(lo, lo + 1, hi, hi - 1, as.bigz(0), 1, 2, 7, urand.bigz(n, sample(1:w, 1)) %% (hi + 1)); if (lo < 0) v <- c(v, -1, -7, -(urand.bigz(n, w) %% (hi + 1))); v[sample(length(v), n, TRUE)] }
fl <- function(a, b) { q <- divq.bigz(a, b); r <- a - q * b; adj <- (r != 0) & ((r < 0) != (b < 0)); q[adj] <- q[adj] - 1; q }
N <- 600; tys <- names(R)
for (ta in tys) for (tb in tys) { cm <- common(ta, tb); a <- gen(ta, N); b <- gen(tb, N); za <- get(ta)(as.character(a)); zb <- get(tb)(as.character(b))
  if (is.na(cm)) { r <- tryCatch(za + zb, error = function(e) class(e)[1]); if (!identical(r, "zuint_incompatible_error")) cat("MISMATCH expected incompat", ta, tb, "\n"); 
    for (op in c("==", "<", ">=")) { g <- get(op)(za, zb); if (!identical(as.logical(g), as.logical(get(op)(a, b)))) cat("MISMATCH xcmp", ta, tb, op, "\n") }; next }
  lo <- R[[cm]][1]; hi <- R[[cm]][2]
  ck <- function(nm, got, exp, sel = TRUE) { e <- as.character(exp); e[exp < lo | exp > hi] <- NA; g <- as.character(got); if (!identical(g, e) || !identical(class(got)[1], paste0("zu_", cm))) { k <- which(!(is.na(g) & is.na(e)) & (is.na(g) != is.na(e) | g != e))[1]; cat("MISMATCH", nm, ta, tb, as.character(a[sel][k]), as.character(b[sel][k]), g[k], e[k], class(got)[1], "\n") } }
  q <- suppressWarnings
  ck("+", q(za + zb), a + b); ck("-", q(za - zb), a - b); ck("*", q(za * zb), a * b); nz <- b != 0
  qq <- fl(a[nz], b[nz]); ck("%/%", q(za[nz] %/% zb[nz]), qq, nz); ck("%%", q(za[nz] %% zb[nz]), a[nz] - qq * b[nz], nz)
  m <- two^(if (grepl("64", cm)) 64 else 128); wr <- function(v) { v <- v %% m; if (lo < 0) { neg <- v >= m / 2; v[neg] <- v[neg] - m }; v }
  ck("wadd", q(wrapping_add(za, zb)), wr(a + b)); ck("wmul", q(wrapping_mul(za, zb)), wr(a * b)); ck("wsub", q(wrapping_sub(za, zb)), wr(a - b))
  for (op in c("==", "<", ">=", "!=", ">", "<=")) { g <- get(op)(za, zb); if (!identical(as.logical(g), as.logical(get(op)(a, b)))) cat("MISMATCH cmp", ta, tb, op, "\n") }
  cc <- c(za, zb); if (!identical(as.character(cc), c(as.character(a), as.character(b))) || class(cc)[1] != paste0("zu_", cm)) cat("MISMATCH c()", ta, tb, "\n")
  # checked agrees with default
  ok <- !is.na(q(za + zb)); if (!identical(as.character(checked_add(za[ok], zb[ok])), as.character(q(za + zb))[ok])) cat("MISMATCH checked_add", ta, tb, "\n")
  r <- tryCatch(checked_mul(za, zb), error = function(e) "err"); if (anyNA(q(za * zb)) != identical(r, "err")) cat("MISMATCH checked_mul err", ta, tb, "\n")
  # doubles as operand: integral in range
  d <- sample(c(0, 1, -1, 2^31, -2^31, 2^53, 2^52 + 1, -2^53, 2^62, -2^62, 2^63 - 1024, 2^64 - 2048, 2^100, -2^100, 2^127 - 2^74), N, TRUE); bd <- as.bigz(d); inr <- bd >= R[[ta]][1] & bd <= R[[ta]][2]
  if (any(inr)) { got <- q(za[inr] + d[inr]); e <- a[inr] + bd[inr]; ee <- as.character(e); ee[e < R[[ta]][1] | e > R[[ta]][2]] <- NA; if (!identical(as.character(got), ee)) cat("MISMATCH +dbl", ta, "\n")
    got <- q(d[inr] * za[inr]); e <- a[inr] * bd[inr]; ee <- as.character(e); ee[e < R[[ta]][1] | e > R[[ta]][2]] <- NA; if (!identical(as.character(got), ee)) cat("MISMATCH dbl*", ta, "\n") }
  if (any(!inr)) { r <- tryCatch(za[!inr][1] + d[!inr][1], error = function(e) class(e)[1]); if (!identical(r, "zuint_double_error")) cat("MISMATCH dbl out of range not error", ta, format(d[!inr][1]), "\n") }
}
# one warning per call
n <- 0; withCallingHandlers(int64(rep("9223372036854775807", 5)) + 1L, warning = function(w) { n <<- n + 1; invokeRestart("muffleWarning") }); cat("warnings:", n, "\n")
# division real: /
a <- gen("int128", 300); b <- gen("int128", 300); b[b == 0] <- 1; g <- int128(as.character(a)) / int128(as.character(b)); e <- as.double(a) / as.double(b); cat("div maxrel:", max(abs(g - e) / pmax(abs(e), 1e-300)), "\n")
x <- int64(c(a = 3, b = 1)); T(print(x, quote = TRUE)); T(print(x, max = 0)); T(print(x, max = NA)); print(x, digits = 3); print(int64(1:30), max = 5); print(x, right = FALSE); T(print(x, width = 10)); print(uint128(1:3)); op <- options(max.print = 3); print(int64(1:10)); options(op); op <- options(width = 30); print(int64(1:30) * 1000000L); options(op)
str(x, vec.len = 1); str(x, vec.len = 0); T(str(x, give.head = FALSE)); T(str(int64(1:30), vec.len = NA)); T(str(1:30, vec.len = 1)); T(str(int64(1:30), vec.len = 1)); str(NA_int128_); T(summary(x, digits = 3)); T(summary(int64(c(1, 2, 4)))); T(summary(c(1, 2, 4))); T(names(summary(int64(1)))); T(class(summary(int64(1)))); T(summary(int64(1:4))[["Mean"]]); T(summary(int64(c(1, 2)), maxsum = 1)); T(format(summary(uint64(c("18446744073709551614", "18446744073709551612")))))
T(int64(2)^int64(c(NA, -1))); T(int64(2)^int64(c(NA, 3))); T(int64(3)^2^128); T(int64(3)^2^127); T(int64(-1)^2^128); T(class(int64(1)^(2^128))); T(class(int64(1)^(2^127)))
