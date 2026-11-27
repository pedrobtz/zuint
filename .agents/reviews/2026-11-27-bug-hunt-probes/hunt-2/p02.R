source("pre.R")
set.seed(1)
two <- as.bigz(2)
rng <- list(int64 = c(-(two^63 - 1), two^63 - 1), uint64 = c(as.bigz(0), two^64 - 2),
            int128 = c(-(two^127 - 1), two^127 - 1), uint128 = c(as.bigz(0), two^128 - 2))
ctor <- list(int64 = int64, uint64 = uint64, int128 = int128, uint128 = uint128)
bits <- c(int64 = 64, uint64 = 64, int128 = 128, uint128 = 128)
signed <- c(int64 = TRUE, uint64 = FALSE, int128 = TRUE, uint128 = FALSE)
gen <- function(ty, n) {
  lo <- rng[[ty]][1]; hi <- rng[[ty]][2]
  edge <- c(lo, lo + 1, lo + 2, hi, hi - 1, hi - 2, 0, 1, 2, 3, 10)
  if (signed[[ty]]) edge <- c(edge, -1, -2, -3, -10, two^(bits[[ty]]/2), -two^(bits[[ty]]/2), two^32, -two^32, two^31-1) else edge <- c(edge, two^(bits[[ty]]/2), two^(bits[[ty]]-1), two^(bits[[ty]]-1) - 1, two^32)
  # random magnitudes of random bit lengths
  k <- sample(1:(bits[[ty]] - signed[[ty]]), n, TRUE)
  r <- do.call(c, lapply(k, function(b) urand.bigz(1, b)))
  r <- r %% (hi + 1)
  if (signed[[ty]]) r <- r * sample(c(-1, 1), n, TRUE)
  v <- c(edge, r)
  v[sample(length(v), n, TRUE)]
}
z <- function(b, ty) ctor[[ty]](as.character(b))
chk <- function(what, got, exp, ty, a, b) {
  lo <- rng[[ty]][1]; hi <- rng[[ty]][2]
  e <- as.character(exp); e[is.na(exp) | exp < lo | exp > hi] <- NA
  g <- as.character(got)
  bad <- which(!(is.na(e) & is.na(g)) & (is.na(e) != is.na(g) | e != g))
  if (length(bad)) { i <- bad[1]; cat("MISMATCH", what, ty, "n=", length(bad), " a=", as.character(a[i]), " b=", as.character(b[i]), " got=", g[i], " exp=", e[i], "\n") }
}
wrapv <- function(exp, ty) {
  m <- two^bits[[ty]]; v <- exp %% m
  if (signed[[ty]]) v <- ifelse(v >= m/2, 0, 1) * 0 + v   # placeholder
  v
}
wrapc <- function(exp, ty) { m <- two^bits[[ty]]; v <- exp %% m; if (signed[[ty]]) { neg <- v >= m / 2; v[neg] <- v[neg] - m }; v }
q <- function(e) suppressWarnings(e)
N <- 3000
for (ty in names(ctor)) {
  a <- gen(ty, N); b <- gen(ty, N)
  za <- z(a, ty); zb <- z(b, ty)
  stopifnot(identical(as.character(za), as.character(a)))
  chk("+", q(za + zb), a + b, ty, a, b)
  chk("-", q(za - zb), a - b, ty, a, b)
  chk("*", q(za * zb), a * b, ty, a, b)
  nz <- b != 0
  fq <- a; fq[nz] <- a[nz] %/% b[nz]; # gmp %/% is floor? check below
  fd <- (a[nz] - gmp::mod.bigz(a[nz], abs(b[nz])) ) # not used
  # floor division via gmp: divq.bigz is floor
  fq <- divq.bigz(a[nz], b[nz]); fm <- a[nz] - fq * b[nz]
  # make it floor explicitly
  adj <- (fm != 0) & ((fm < 0) != (b[nz] < 0)); fq[adj] <- fq[adj] - 1; fm <- a[nz] - fq * b[nz]
  chk("%/%", q(za[nz] %/% zb[nz]), fq, ty, a[nz], b[nz])
  chk("%%", q(za[nz] %% zb[nz]), fm, ty, a[nz], b[nz])
  # wrapping
  chk("wadd", q(wrapping_add(za, zb)), wrapc(a + b, ty), ty, a, b)
  chk("wsub", q(wrapping_sub(za, zb)), wrapc(a - b, ty), ty, a, b)
  chk("wmul", q(wrapping_mul(za, zb)), wrapc(a * b, ty), ty, a, b)
  chk("wneg", q(wrapping_neg(za)), wrapc(-a, ty), ty, a, a)
  chk("neg", q(-za), -a, ty, a, a)
  chk("abs", q(abs(za)), abs(a), ty, a, a)
  # comparisons
  for (op in c("==", "<", "<=", ">", ">=", "!=")) {
    g <- get(op)(za, zb); e <- get(op)(a, b)
    if (!identical(as.logical(g), as.logical(e))) cat("MISMATCH cmp", op, ty, "\n")
  }
  # pow
  ex <- sample(0:130, N, TRUE); ex[sample(N, 500)] <- sample(0:3, 500, TRUE)
  pw <- do.call(c, lapply(seq_len(N), function(i) a[i]^ex[i]))
  chk("^", q(za^ex), pw, ty, a, ex)
  chk("wpow", q(wrapping_pow(za, ex)), wrapc(pw, ty), ty, a, ex)
  # integer operand
  ib <- sample(c(-5:5, .Machine$integer.max, -.Machine$integer.max, sample(-1e6:1e6, 20)), N, TRUE)
  chk("+int", q(za + ib), a + ib, ty, a, ib)
  chk("int-", q(ib - za), ib - a, ty, a, ib)
  chk("*int", q(za * ib), a * ib, ty, a, ib)
  chk("w+int", q(wrapping_add(za, ib)), wrapc(a + ib, ty), ty, a, ib)
  chk("w*int", q(wrapping_mul(ib, za)), wrapc(a * ib, ty), ty, a, ib)
  nzi <- ib != 0
  fq <- divq.bigz(a[nzi], ib[nzi]); fm <- a[nzi] - fq * ib[nzi]
  adj <- (fm != 0) & ((fm < 0) != (ib[nzi] < 0)); fq[adj] <- fq[adj] - 1; fm <- a[nzi] - fq * ib[nzi]
  chk("%/%int", q(za[nzi] %/% ib[nzi]), fq, ty, a[nzi], ib[nzi])
  chk("%%int", q(za[nzi] %% ib[nzi]), fm, ty, a[nzi], ib[nzi])
  # sum / cumsum / prod
  s <- z(gen(ty, 50), ty)
  for (rep in 1:200) {
    v <- gen(ty, sample(1:12, 1)); zv <- z(v, ty)
    chk("sum", q(sum(zv)), sum(v), ty, v, v)
    chk("prod", q(prod(zv)), prod(v), ty, v, v)
    cs <- cumsum(v); lo <- rng[[ty]][1]; hi <- rng[[ty]][2]
    bad <- cs < lo | cs > hi; if (any(bad)) cs[which(bad)[1]:length(cs)] <- NA
    g <- as.character(q(cumsum(zv))); e <- as.character(cs); e[is.na(cs)] <- NA
    if (!identical(g, e)) { cat("MISMATCH cumsum", ty, as.character(v), "\n got", g, "\n exp", e, "\n") }
    cp <- v; for (i in seq_along(v)[-1]) cp[i] <- cp[i-1] * v[i]
    bad <- cp < lo | cp > hi; if (any(bad)) cp[which(bad)[1]:length(cp)] <- NA
    g <- as.character(q(cumprod(zv))); e <- as.character(cp); e[is.na(cp)] <- NA
    if (!identical(g, e)) { cat("MISMATCH cumprod", ty, as.character(v), "\n got", g, "\n exp", e, "\n") }
    chk("min", min(zv), min(v), ty, v, v); chk("max", max(zv), max(v), ty, v, v)
    # sort/order
    if (!identical(as.character(sort(zv)), as.character(sort(v)))) cat("MISMATCH sort", ty, "\n")
    if (!identical(as.character(zv[order(zv, decreasing=TRUE)]), as.character(rev(sort(v))))) cat("MISMATCH order", ty, "\n")
    # mean
    m <- mean(zv); qx <- as.bigq(sum(v), length(v))
    ulp <- if (m == 0) 2^-1074 else 2^(floor(log2(abs(m))) - 52)
    d0 <- abs(as.bigq(m) - qx); d1 <- abs(as.bigq(m - ulp) - qx); d2 <- abs(as.bigq(m + ulp) - qx)
    if (d1 < d0 || d2 < d0) cat("MISMATCH mean", ty, as.character(v), " got", format(m, digits=17), "\n")
  }
}
cat("done\n")
