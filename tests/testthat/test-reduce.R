test_that("sum is type stable: exact, or NA with a warning when it does not fit", {
  expect_warning(s <- sum(int64(c(2^62, 2^62))), class = "zuint_overflow_warning")
  expect_true(is.na(s))
  expect_s3_class(s, "zu_int64")
  expect_identical(sum(int128(c(2^62, 2^62))), int128("9223372036854775808"))
  # a total that passes beyond the range and comes back is exact
  max128 <- "170141183460469231731687303715884105727"
  expect_identical(sum(int128(c(max128, "1", "-1"))), int128(max128))
  expect_identical(sum(uint128(c("340282366920938463463374607431768211454", "1")) - 1L), uint128(NA))
  for (type in zu_all_types) {
    v <- oracle_random(type, 40, seed = 6)
    exact <- sum(gmp::as.bigz(v))
    fits <- oracle_fits(type, as.character(exact))
    x <- zu_ctor(type)(v)
    if (fits) {
      expect_identical(as.character(sum(x)), as.character(exact), label = type)
    } else {
      expect_warning(r <- sum(x), class = "zuint_overflow_warning")
      expect_true(is.na(r))
    }
    small <- zu_ctor(type)(c(1, 2, NA, 3))
    expect_identical(sum(small), zu_ctor(type)(NA))
    expect_identical(sum(small, na.rm = TRUE), zu_ctor(type)(6))
    expect_identical(sum(zu_ctor(type)()), zu_ctor(type)(0))
  }
})

test_that("prod is exact, zero wins, and overflow is NA with a warning", {
  expect_identical(prod(int64(c(-3, 4, 5))), int64(-60))
  expect_identical(prod(int64(c("9223372036854775807", "9223372036854775807", "0"))), int64(0))
  expect_warning(p <- prod(uint64(c(2^40, 2^40))), class = "zuint_overflow_warning")
  expect_true(is.na(p))
  expect_identical(prod(int128(c(2, NA)), na.rm = TRUE), int128(2))
  expect_identical(prod(uint128()), uint128(1))
})

test_that("cumsum and cumprod are NA from the first NA or overflow on", {
  for (type in zu_all_types) {
    v <- c("5", "7", "11", "13")
    x <- zu_ctor(type)(v)
    expect_identical(as.character(cumsum(x)), as.character(cumsum(gmp::as.bigz(v))))
    cp <- vapply(seq_along(v), function(i) as.character(prod(gmp::as.bigz(v[seq_len(i)]))), character(1))
    expect_identical(as.character(cumprod(x)), cp)
    expect_identical(is.na(cumsum(zu_ctor(type)(c(1, NA, 2)))), c(FALSE, TRUE, TRUE))
  }
  expect_warning(r <- cumsum(int64(c("9223372036854775807", "1", "-1"))), class = "zuint_overflow_warning")
  expect_identical(as.character(r), c("9223372036854775807", NA, NA))
  expect_identical(cummax(int128(c(3, 1, 5, 2))), int128(c(3, 3, 5, 5)))
  expect_identical(cummin(uint64(c(3, 1, 5, NA, 0))), uint64(c(3, 1, 1, NA, NA)))
})

test_that("min, max and range are exact, with base R's empty case", {
  for (type in zu_all_types) {
    v <- c(oracle_edges(type), NA)
    x <- zu_ctor(type)(v)
    r <- oracle_range(type)
    expect_identical(as.character(min(x, na.rm = TRUE)), as.character(r$min))
    expect_identical(as.character(max(x, na.rm = TRUE)), as.character(r$max))
    expect_identical(as.character(range(x, na.rm = TRUE)), as.character(c(r$min, r$max)))
    expect_true(is.na(max(x)))
    expect_warning(m <- min(zu_ctor(type)()), "no non-missing")
    expect_identical(m, Inf)
    expect_warning(m <- max(zu_ctor(type)(NA), na.rm = TRUE), "no non-missing")
    expect_identical(m, -Inf)
  }
  expect_identical(max(int64(1), int64(5), 3L), int64(5))
})

test_that("mean and median are doubles from the exact values", {
  expect_identical(mean(int64(1:2)), 1.5)
  expect_identical(median(int64(c(1, 2))), 1.5)
  expect_identical(median(uint128(c(5, 1, 9))), 5)
  expect_identical(mean(int64(c(1, NA))), NA_real_)
  expect_identical(mean(int64(c(1, NA)), na.rm = TRUE), 1)
  expect_identical(median(int64(c(1, NA)), na.rm = TRUE), 1)
  expect_true(is.nan(mean(int64())))
  withr::local_seed(8)
  v <- round(runif(200, -2^50, 2^50))
  for (type in c("int64", "int128")) {
    expect_equal(mean(zu_ctor(type)(v)), mean(v))
    expect_equal(median(zu_ctor(type)(v)), median(v))
  }
  # sums beyond 128 bits do not overflow the mean
  big <- uint128(rep("340282366920938463463374607431768211454", 5))
  expect_equal(mean(big), 2^128)
  max128 <- "170141183460469231731687303715884105727"
  expect_equal(mean(int128(c(max128, max128, paste0("-", max128)))), 2^127 / 3)
  expect_equal(mean(int64(c("9223372036854775807", "9223372036854775807"))), 2^63)
})

test_that("any and all use the logical values", {
  expect_true(any(int64(c(0, 3))))
  expect_false(all(uint128(c(0, 3))))
})

test_that("diff and seq_zu are exact", {
  expect_identical(diff(int64(c(1, 4, 9, 16))), int64(c(3, 5, 7)))
  expect_identical(diff(int64(c(1, 4, 9, 16)), differences = 2L), int64(c(2, 2)))
  expect_identical(diff(uint64(1)), uint64())
  expect_warning(diff(uint64(c(5, 3))), class = "zuint_overflow_warning")
  expect_identical(
    seq_zu(uint64("18446744073709551600"), uint64("18446744073709551614"), by = 7L),
    uint64(c("18446744073709551600", "18446744073709551607", "18446744073709551614"))
  )
  expect_identical(seq_zu(int64(10), int64(1), by = -3L), int64(c(10, 7, 4, 1)))
  expect_identical(seq_zu(int128(-2), by = int128(5), length.out = 3), int128(c(-2, 3, 8)))
  expect_error(seq_zu(int64(1), int64(5), by = -1L), class = "zuint_type_error")
  expect_error(seq_zu(int64(1), int64(5), by = 0L), class = "zuint_type_error")
})

test_that("summary reports the exact extremes", {
  expect_snapshot(summary(int64(c("-9223372036854775807", "0", "9223372036854775807", NA))))
})

test_that("the 64-bit sum is exact at the edges of the range", {
  max64 <- "9223372036854775807"
  expect_identical(sum(int64(c(max64, paste0("-", max64)))), int64(0))
  expect_identical(sum(int64(c(max64, "-1", "1"))), int64(max64))
  expect_warning(s <- sum(int64(c(max64, max64))), class = "zuint_overflow_warning")
  expect_true(is.na(s))
  expect_warning(sum(int64(c(paste0("-", max64), "-1"))), class = "zuint_overflow_warning")
  expect_identical(sum(int64(rep("-4294967297", 3))), int64("-12884901891"))
  umax <- "18446744073709551614"
  expect_identical(sum(uint64(c(umax, "0"))), uint64(umax))
  expect_warning(sum(uint64(c(umax, "1"))), class = "zuint_overflow_warning")
  expect_identical(sum(uint64(rep("4294967295", 4))), uint64("17179869180"))
  for (type in c("int64", "uint64")) {
    v <- oracle_random(type, 2000, seed = 33)
    exact <- sum(gmp::as.bigz(v))
    fits <- oracle_fits(type, as.character(exact))
    r <- suppressWarnings(sum(zu_ctor(type)(v)))
    expect_identical(as.character(r), if (fits) as.character(exact) else NA_character_)
  }
})
