source("pre.R")
u <- uint64("0xff00"); i <- int64(-16); U <- uint128(1); I <- int128(-1)
for (n in list(0L, 1L, 63L, 64L, 127L, 128L, -1L, NA_integer_, 1.5, 2^31, Inf, NaN, "3", TRUE, NULL, int64(3), c(a = 1L, b = 2L), 0.0, -0.0, 3.0, 1e10, list(1), factor(2))) {
  cat("--- n =", deparse(n), "\n")
  T(shift_left(u, n)); T(shift_right(i, n)); T(shift_left(U, n)); T(shift_right(I, n))
}
T(shift_left(uint64(1), 0:70)[c(1, 2, 63, 64, 65)]); T(shift_left(uint64(1), 63L)); T(shift_left(int64(1), 63L)); T(shift_left(int64(1), 62L)); T(shift_left(int64(3), 62L)); T(shift_left(int64(-1), 63L)); T(shift_left(uint64("0xffffffffffffffff"), 0L))
T(shift_left(uint128(1), 127L)); T(shift_left(int128(1), 127L)); T(shift_left(uint128("0x7fffffffffffffffffffffffffffffff"), 1L)); T(shift_left(uint64("0x7fffffffffffffff"), 1L)); T(shift_right(uint128("340282366920938463463374607431768211454"), c(0L, 1L, 64L, 127L)))
T(shift_right(int128("-170141183460469231731687303715884105727"), c(0L, 1L, 63L, 64L, 65L, 126L, 127L))); T(shift_right(int64(c(-1, -2, -3, 7)), 1L)); T(shift_right(int64(-1), 63L))
T(shift_left(c(a = uint64(1), b = uint64(2)), 1L)); T(shift_left(uint64(1), c(x = 1L, y = 2L))); T(shift_left(uint64(1:3), 1:2)); T(shift_left(uint64(), 1:3)); T(shift_left(uint64(1:3), integer()))
T(shift_left(5L, 1L)); T(shift_left(NA_uint64_, 1L)); T(shift_left(uint64(0), 64L))
T(bit_and(uint64(5), -1L)); T(bit_and(int64(5), -1L)); T(bit_or(int64(5), uint64(2))); T(bit_xor(int128(-1), int64(-1))); T(bit_and(int64(5), 3)); T(bit_and(int64(5), NA)); T(bit_and(int64(5), TRUE)); T(bit_and(int64(5), "3")); T(bit_and(5L, 3L)); T(bit_or(int64(1:3), int64(1:2))); T(bit_and(int64(), int64(1))); T(bit_and(uint64(1), int128(1))); T(bit_and(int64(1), uint128(1)))
T(bit_not(int64(c(0, -1, 5, NA)))); T(bit_not(int64("9223372036854775807"))); T(bit_not(uint64(0))); T(bit_not(uint64(1))); T(bit_xor(int64("9223372036854775807"), int64(-1))); T(bit_or(uint64("0xfffffffffffffffe"), 1L)); T(bit_not(c(a = int128(0))))
T(bit_xor(int64(c(a=1)), int64(c(b=3))))
T(popcount(int64(c(0, -1, 5, NA)))); T(clz(int64(c(0, -1, 5, NA, 1)))); T(ctz(int64(c(0, -1, 8, NA)))); T(popcount(uint128("340282366920938463463374607431768211454"))); T(clz(uint128(c(0, 1)))); T(ctz(int128(c(0, 1)))); T(ctz(shift_left(uint128(1), 100L))); T(clz(shift_left(uint128(1), 100L))); T(popcount(c(a = int128(-1)))); T(popcount(5L)); T(popcount(int64()))
# differential for bit ops vs gmp
set.seed(3); two <- as.bigz(2)
tc <- function(b, w) { m <- two^w; (b %% m) }  # two's complement as unsigned
for (ty in c("int64", "uint64", "int128", "uint128")) {
  w <- if (grepl("64", ty)) 64 else 128; sg <- !grepl("^u", ty); f <- get(ty)
  hi <- if (sg) two^(w-1) - 1 else two^w - 2
  a <- urand.bigz(400, w) %% (hi + 1); b <- urand.bigz(400, w) %% (hi + 1)
  if (sg) { a <- a * sample(c(-1, 1), 400, TRUE); b <- b * sample(c(-1, 1), 400, TRUE) }
  za <- f(as.character(a)); zb <- f(as.character(b))
  back <- function(v) { if (sg) { neg <- v >= two^(w-1); v[neg] <- v[neg] - two^w }; s <- as.character(v); s[v == (if (sg) -two^(w-1) else two^w - 1)] <- NA; s }
  ua <- tc(a, w); ub <- tc(b, w)
  ops <- list(and = gmp:::`&.bigz`, or = gmp:::`|.bigz`, xor = function(p, q) do.call(c, lapply(seq_along(p), function(k) bigz_xor(p[k], q[k]))))
  rb <- function(v) { s <- vapply(seq_along(v), function(k) as.character(v[k], b = 2), ""); s }
  bin <- function(v) { s <- rb(v); paste0(strrep("0", w - nchar(s)), s) }
  fromb <- function(s) as.bigz(paste0("0b", s))
  A <- strsplit(bin(ua), ""); B <- strsplit(bin(ub), "")
  mk <- function(fn) fromb(vapply(seq_along(A), function(k) paste(as.integer(fn(A[[k]] == "1", B[[k]] == "1")), collapse = ""), ""))
  q <- function(e) suppressWarnings(e)
  ck <- function(nm, got, exp) { g <- as.character(got); e <- back(exp); if (!identical(g, e)) { k <- which(!(is.na(g) & is.na(e)) & (is.na(g) != is.na(e) | g != e))[1]; cat("MISMATCH", nm, ty, as.character(a[k]), as.character(b[k]), g[k], e[k], "\n") } }
  ck("and", q(bit_and(za, zb)), mk(`&`)); ck("or", q(bit_or(za, zb)), mk(`|`)); ck("xor", q(bit_xor(za, zb)), mk(xor)); ck("not", q(bit_not(za)), two^w - 1 - ua)
  n <- sample(0:(w - 1), 400, TRUE)
  ck("shl", q(shift_left(za, n)), (ua * two^n) %% two^w)
  fl <- function(x, d) { qq <- divq.bigz(x, d); r <- x - qq * d; qq[r < 0] <- qq[r < 0] - 1; qq }
  e <- fl(a, two^n); g <- as.character(q(shift_right(za, n))); if (!identical(g, as.character(e))) cat("MISMATCH shr", ty, "\n")
  pc <- vapply(A, function(s) sum(s == "1"), 0L); if (!identical(popcount(za), pc)) cat("MISMATCH popcount", ty, "\n")
  cl <- vapply(A, function(s) { k <- which(s == "1"); if (length(k)) k[1] - 1L else as.integer(w) }, 0L); if (!identical(clz(za), cl)) cat("MISMATCH clz", ty, "\n")
  ct <- vapply(A, function(s) { k <- which(s == "1"); if (length(k)) as.integer(w - max(k)) else as.integer(w) }, 0L); if (!identical(ctz(za), ct)) cat("MISMATCH ctz", ty, "\n")
  # hex/bin round trip
  if (!identical(as.character(f(format_hex(za))), as.character(a))) cat("MISMATCH hex rt", ty, "\n")
  if (!identical(as.character(f(format_bin(za, pad = TRUE))), as.character(a))) cat("MISMATCH bin rt", ty, "\n")
  hx <- paste0(ifelse(a < 0, "-", ""), "0x", vapply(seq_along(a), function(k) as.character(abs(a[k]), b = 16), "")); if (!identical(format_hex(za), hx)) cat("MISMATCH hex", ty, "\n")
}
cat("done\n")
