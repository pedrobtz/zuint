source("pre.R")
M <- int64("9223372036854775807"); UM <- uint64("18446744073709551614"); M128 <- int128("170141183460469231731687303715884105727"); U128 <- uint128("340282366920938463463374607431768211454")
T(seq_zu(int64(1), int64(10), by = 3L)); T(seq_zu(int64(10), int64(1), by = -3L)); T(seq_zu(int64(10), int64(1))); T(seq_zu(int64(1), int64(10), length.out = 3)); T(seq_zu(int64(5), length.out = 0)); T(seq_zu(int64(5), length.out = 1)); T(seq_zu(int64(5), length.out = -1)); T(seq_zu(int64(5), length.out = NA)); T(seq_zu(int64(5), length.out = 2.7)); T(seq_zu(int64(5), length.out = c(2, 3))); T(seq_zu(int64(5), length.out = "3")); T(seq_zu(int64(5)))
T(seq_zu(-M, M, by = M)); T(seq_zu(M, -M, by = -M)); T(seq_zu(-M, M, by = UM)); T(seq_zu(-M, M, by = int128("9223372036854775809"))); T(seq_zu(M - 2L, M)); T(seq_zu(M - 2L, by = 1L, length.out = 4)); T(seq_zu(-M, by = -1L, length.out = 2))
T(seq_zu(uint64(0), UM, by = UM)); T(seq_zu(UM, uint64(0), by = -9223372036854775807)); T(seq_zu(UM, uint64(0), by = -UM)); T(seq_zu(UM, 0L, by = int128("-9223372036854775808"))); T(seq_zu(uint64(5), uint64(0), by = -2L)); T(seq_zu(uint64(5), by = -2L, length.out = 3)); T(seq_zu(uint64(5), by = -2L, length.out = 4))
T(seq_zu(1L, 10L)); T(seq_zu(1L, int64(3))); T(seq_zu(1, int64(3))); T(seq_zu(int64(1), 3.5)); T(seq_zu(int64(1), 10, by = 2.5)); T(seq_zu(int64(1), 10, by = 0)); T(seq_zu(int64(1), 10, by = NA)); T(seq_zu(int64(1:2), 10)); T(seq_zu(int64(1), int64(c(5, 6)))); T(seq_zu(int64(1), 10, by = c(1, 2))); T(seq_zu(int64(1), NA)); T(seq_zu(NA_int64_, 3L)); T(seq_zu(int64(1), uint64(3))); T(seq_zu(int64(1), U128)); T(seq_zu(int64(3), int64(3))); T(seq_zu(int64(1), "3")); T(seq_zu(int64(1), TRUE)); T(seq_zu(c(a = int64(1)), 3L)); T(seq_zu(int64(1), 5L, by = TRUE)); T(seq_zu(int64(1), 5L, by = int64(2))); T(seq_zu(uint64(1), 5L, by = int64(-2)))
T(seq_zu(-M128, M128, by = M128)); T(seq_zu(uint128(0), U128, by = uint128("170141183460469231731687303715884105727"))); T(seq_zu(int128(-7), int128(7), by = 3L)); T(seq_zu(int64(-7), int64(8), by = 5L)); T(seq_zu(int64(8), int64(-7), by = -5L)); T(seq_zu(int64(-8), int64(-7), by = 5L)); T(seq_zu(int64(-7), int64(-8), by = -5L))
# random seq vs gmp
set.seed(5); bad <- 0
for (k in 1:3000) {
  ty <- sample(c("int64", "uint64", "int128", "uint128"), 1); f <- get(ty); sg <- !grepl("^u", ty)
  w <- if (grepl("64", ty)) 64 else 128; hi <- if (sg) as.bigz(2)^(w - 1) - 1 else as.bigz(2)^w - 2; lo <- if (sg) -hi else as.bigz(0)
  far <- sample(c(TRUE, FALSE), 1)
  if (far) { a <- urand.bigz(1, w) %% (hi - lo + 1) + lo; b <- urand.bigz(1, w) %% (hi - lo + 1) + lo; st <- abs(b - a) %/% sample(1:30, 1) + sample(0:1, 1); if (st == 0) st <- as.bigz(1) }
  else { a <- sample(c(-50:50), 1) + sample(list(lo + 60, hi - 60, as.bigz(if (sg) 0 else 60)), 1)[[1]]; b <- a + sample(-50:50, 1); st <- as.bigz(sample(1:7, 1)) }
  if (st > hi || b < lo || b > hi || a < lo || a > hi) next
  if (b < a) st <- -st
  n <- as.integer(as.character(abs(b - a) %/% abs(st))) + 1L
  e <- as.character(a + st * (0:(n - 1)))
  byarg <- if (abs(st) <= 2^31 - 1) as.integer(as.character(st)) else if (st < 0) int128(as.character(st)) else f(as.character(st))
  g <- tryCatch(as.character(seq_zu(f(as.character(a)), f(as.character(b)), by = byarg)), error = function(e) paste("ERR", conditionMessage(e)), warning = function(w) paste("WARN", conditionMessage(w)))
  if (!identical(g, e)) { bad <- bad + 1; if (bad < 8) cat("MISMATCH seq", ty, as.character(a), as.character(b), as.character(st), "\n got", head(g, 4), "\n exp", head(e, 4), "n", n, "\n") }
}
cat("seq bad:", bad, "\n")
