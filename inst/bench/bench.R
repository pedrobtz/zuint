# zuint's int64 against bit64's integer64 on the five operations of design
# 12: +, sum, sort, match and unique. Run from the package root with zuint
# and bit64 installed:
#
#   Rscript inst/bench/bench.R            # 10^6 and 10^7 elements
#   ZUINT_BENCH_N=1e8 Rscript inst/bench/bench.R
#
# Each figure is the median of `reps` timings in milliseconds; at the
# smaller sizes each timing repeats the operation so that it spans enough
# of the clock to resolve. The data are
# random int64 values across the whole range, the same bits for both
# packages. bit64 is used through its namespace, not attached, so each
# package runs its own methods.

library(zuint)
stopifnot(requireNamespace("bit64", quietly = TRUE))

sizes <- as.numeric(strsplit(Sys.getenv("ZUINT_BENCH_N", "1e6,1e7"), ",")[[1L]])
reps <- 5L

time_ms <- function(expr) {
  expr <- substitute(expr)
  env <- parent.frame()
  k <- max(1L, as.integer(1e7 / get("n", env)))
  t <- vapply(seq_len(reps), function(i) {
    gc(FALSE)
    system.time(for (j in seq_len(k)) eval(expr, env))[["elapsed"]] / k
  }, numeric(1))
  stats::median(t) * 1000
}

rows <- list()
for (n in sizes) {
  set.seed(1)
  z <- int64(round(runif(n, -2^62, 2^62)))
  b <- bit64::as.integer64(z)
  # small enough that the sum fits
  zs <- int64(round(runif(n, -2^40, 2^40)))
  bs <- bit64::as.integer64(zs)
  small_z <- z[sample.int(n, n / 10)]
  small_b <- b[sample.int(n, n / 10)]
  ops <- list(
    "+" = c(time_ms(z + z), time_ms(b + b)),
    sum = c(time_ms(sum(zs)), time_ms(sum(bs))),
    sort = c(time_ms(sort(z)), time_ms(bit64:::sort.integer64(b))),
    match = c(time_ms(zu_match(small_z, z)), time_ms(bit64::match(small_b, b))),
    unique = c(time_ms(unique(z)), time_ms(bit64:::unique.integer64(b)))
  )
  for (op in names(ops)) {
    rows[[length(rows) + 1L]] <- data.frame(
      n = format(n, scientific = TRUE),
      operation = op,
      zuint_ms = round(ops[[op]][[1L]], 2),
      bit64_ms = round(ops[[op]][[2L]], 2)
    )
  }
}
res <- do.call(rbind, rows)
res$ratio <- round(res$zuint_ms / res$bit64_ms, 2)
print(res, row.names = FALSE)
