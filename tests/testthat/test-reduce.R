test_that("sum is type stable: exact, or NA with a warning when it does not fit", {
  expect_warning(
    s <- sum(int64(c(2^62, 2^62))),
    class = "zuint_overflow_warning"
  )
  expect_identical(s, NA_int64_)
  expect_identical(sum(int128(c(2^62, 2^62))), int128("9223372036854775808"))
  # a total that passes beyond the range and comes back is exact
  max128 <- "170141183460469231731687303715884105727"
  expect_identical(sum(int128(c(max128, "1", "-1"))), int128(max128))
  expect_identical(
    sum(uint128(c("340282366920938463463374607431768211454", "1")) - 1L),
    uint128(NA)
  )
  for (type in zu_all_types) {
    v <- oracle_random(type, 40, seed = 6)
    exact <- sum(gmp::as.bigz(v))
    fits <- oracle_fits(type, as.character(exact))
    x <- zu_ctor(type)(v)
    if (fits) {
      expect_identical(as.character(sum(x)), as.character(exact), label = type)
    } else {
      expect_warning(r <- sum(x), class = "zuint_overflow_warning")
      expect_identical(r, zu_na(type), label = type)
    }
    small <- zu_ctor(type)(c(1, 2, NA, 3))
    expect_identical(sum(small), zu_ctor(type)(NA), label = type)
    expect_identical(sum(small, na.rm = TRUE), zu_ctor(type)(6), label = type)
    expect_identical(sum(zu_ctor(type)()), zu_ctor(type)(0), label = type)
  }
})

test_that("prod is exact, zero wins, and overflow is NA with a warning", {
  expect_identical(prod(int64(c(-3, 4, 5))), int64(-60))
  expect_identical(
    prod(int64(c("9223372036854775807", "9223372036854775807", "0"))),
    int64(0)
  )
  expect_warning(
    p <- prod(uint64(c(2^40, 2^40))),
    class = "zuint_overflow_warning"
  )
  expect_identical(p, NA_uint64_)
  expect_identical(prod(int128(c(2, NA)), na.rm = TRUE), int128(2))
  expect_identical(prod(uint128()), uint128(1))
})

test_that("cumsum and cumprod are NA from the first NA or overflow on", {
  for (type in zu_all_types) {
    v <- c("5", "7", "11", "13")
    x <- zu_ctor(type)(v)
    expect_identical(
      as.character(cumsum(x)),
      as.character(cumsum(gmp::as.bigz(v))),
      label = type
    )
    cp <- vapply(
      seq_along(v),
      function(i) as.character(prod(gmp::as.bigz(v[seq_len(i)]))),
      character(1)
    )
    expect_identical(as.character(cumprod(x)), cp, label = type)
    expect_identical(
      is.na(cumsum(zu_ctor(type)(c(1, NA, 2)))),
      c(FALSE, TRUE, TRUE),
      label = type
    )
  }
  expect_warning(
    r <- cumsum(int64(c("9223372036854775807", "1", "-1"))),
    class = "zuint_overflow_warning"
  )
  expect_identical(as.character(r), c("9223372036854775807", NA, NA))
  expect_identical(cummax(int128(c(3, 1, 5, 2))), int128(c(3, 3, 5, 5)))
  expect_identical(
    cummin(uint64(c(3, 1, 5, NA, 0))),
    uint64(c(3, 1, 1, NA, NA))
  )
})

test_that("min, max and range are exact, with base R's empty case", {
  for (type in zu_all_types) {
    v <- c(oracle_edges(type), NA)
    x <- zu_ctor(type)(v)
    r <- oracle_range(type)
    expect_identical(
      as.character(min(x, na.rm = TRUE)),
      as.character(r$min),
      label = type
    )
    expect_identical(
      as.character(max(x, na.rm = TRUE)),
      as.character(r$max),
      label = type
    )
    expect_identical(
      as.character(range(x, na.rm = TRUE)),
      as.character(c(r$min, r$max)),
      label = type
    )
    expect_identical(max(x), zu_na(type), label = type)
    expect_warning(m <- min(zu_ctor(type)()), class = "zuint_empty_warning")
    expect_identical(m, Inf, label = type)
    expect_warning(
      m <- max(zu_ctor(type)(NA), na.rm = TRUE),
      class = "zuint_empty_warning"
    )
    expect_identical(m, -Inf, label = type)
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
    expect_equal(mean(zu_ctor(type)(v)), mean(v), label = type)
    expect_equal(median(zu_ctor(type)(v)), median(v), label = type)
  }
  # sums beyond 128 bits do not overflow the mean
  big <- uint128(rep("340282366920938463463374607431768211454", 5))
  expect_equal(mean(big), 2^128)
  max128 <- "170141183460469231731687303715884105727"
  expect_equal(mean(int128(c(max128, max128, paste0("-", max128)))), 2^127 / 3)
  expect_equal(
    mean(int64(c("9223372036854775807", "9223372036854775807"))),
    2^63
  )
})

test_that("mean and median are the exact value, rounded once (#148)", {
  skip_if_not_installed("gmp")
  # random vectors across each type's whole range, against gmp's exact
  # rational, correctly rounded
  for (type in zu_all_types) {
    for (k in 1:60) {
      v <- oracle_random(type, 2L + k %% 9L, seed = k)
      x <- zu_ctor(type)(v)
      expect_identical(mean(x), oracle_mean(v), label = paste(type, k))
      s <- as.character(sort(gmp::as.bigz(v)))
      mid <- s[unique(c((length(s) + 1L) %/% 2L, (length(s) + 2L) %/% 2L))]
      expect_identical(median(x), oracle_mean(mid), label = paste(type, k))
    }
  }
  # n copies of one value: the mean is the value, rounded, and never above
  # max()
  one <- c(
    int64 = "9007199254740993",
    uint64 = "18446744073709551613",
    int128 = "-170141183460469231731687303715884105727",
    uint128 = "340282366920938463463374607431768211453"
  )
  for (type in names(one)) {
    v <- rep(one[[type]], 3)
    expect_identical(mean(zu_ctor(type)(v)), oracle_mean(v), label = type)
  }
  x <- int64(rep("9007199254740993", 3))
  expect_false(mean(x) > x[1])
  u <- uint64(c("18446744073709551614", "18446744073709551612"))
  expect_identical(mean(u), oracle_mean(as.character(u)))
  expect_identical(median(u), oracle_mean(as.character(u)))
  # a small total over a large n, where the remainder is all there is
  for (type in c("int64", "int128")) {
    v <- c(rep("2", 600000), rep("-3", 399999))
    expect_identical(mean(zu_ctor(type)(v)), oracle_mean(v), label = type)
    v <- c(rep("-2", 600000), rep("3", 399999))
    expect_identical(mean(zu_ctor(type)(v)), oracle_mean(v), label = type)
  }
  expect_identical(mean(int128(c(0, 2, 3))), oracle_mean(c("0", "2", "3")))
  expect_identical(mean(int128(c(0, 2, 3))), mean(c(0, 2, 3)))
  # exactly halfway in the bits kept, with a remainder beyond them: the
  # remainder decides, rounding up
  half <- c("9007199254740993", "1267650600228229542234191560704")
  for (type in c("int64", "int128", "uint128")) {
    h <- half[[if (type == "int64") 1L else 2L]]
    up <- as.character(gmp::as.bigz(h) + 1)
    v <- c(rep(h, 2999), up)
    expect_identical(mean(zu_ctor(type)(v)), oracle_mean(v), label = type)
    expect_gt(mean(zu_ctor(type)(v)), as.double(gmp::as.bigz(h)))
    if (type != "uint128") {
      v <- paste0("-", v)
      expect_identical(mean(zu_ctor(type)(v)), oracle_mean(v), label = type)
    }
  }
  # quotient and remainder of opposite signs, and a zero mean
  for (type in c("int64", "int128")) {
    v <- c("-7", "1", "1")
    expect_identical(mean(zu_ctor(type)(v)), oracle_mean(v), label = type)
    v <- c("5", "-5")
    expect_identical(mean(zu_ctor(type)(v)), 0, label = type)
  }
})

test_that("a decimal's mean and median are the exact value, rounded once (#148)", {
  skip_if_not_installed("gmp")
  x <- decimal128(c(rep("0.02", 600000), rep("-0.03", 399999)), 5, 2)
  coefs <- c(rep("2", 600000), rep("-3", 399999))
  expect_identical(mean(x), oracle_mean(coefs, 2L))
  for (type in list(
    c(5L, 2L),
    c(18L, 9L),
    c(38L, 0L),
    c(38L, 30L),
    c(38L, 38L)
  )) {
    p <- type[[1L]]
    s <- type[[2L]]
    for (k in 1:10) {
      coefs <- fx_coefs(3L + k, p, seed = 100L * p + k)
      x <- decimal128(fx_format(coefs, p, s), p, s)
      label <- sprintf("DECIMAL(%d, %d) %d", p, s, k)
      expect_identical(mean(x), oracle_mean(coefs, s), label = label)
      o <- as.character(sort(gmp::as.bigz(coefs)))
      n <- length(o)
      mid <- o[unique(c((n + 1L) %/% 2L, (n + 2L) %/% 2L))]
      expect_identical(median(x), oracle_mean(mid, s), label = label)
    }
  }
})

test_that("any and all use the logical values", {
  expect_true(any(int64(c(0, 3))))
  expect_false(all(uint128(c(0, 3))))
})

test_that("diff and seq_zu are exact", {
  expect_identical(diff(int64(c(1, 4, 9, 16))), int64(c(3, 5, 7)))
  expect_identical(
    diff(int64(c(1, 4, 9, 16)), differences = 2L),
    int64(c(2, 2))
  )
  expect_identical(diff(uint64(1)), uint64())
  expect_warning(diff(uint64(c(5, 3))), class = "zuint_overflow_warning")
  expect_identical(
    seq_zu(
      uint64("18446744073709551600"),
      uint64("18446744073709551614"),
      by = 7L
    ),
    uint64(c(
      "18446744073709551600",
      "18446744073709551607",
      "18446744073709551614"
    ))
  )
  expect_identical(seq_zu(int64(10), int64(1), by = -3L), int64(c(10, 7, 4, 1)))
  expect_identical(
    seq_zu(int128(-2), by = int128(5), length.out = 3),
    int128(c(-2, 3, 8))
  )
  expect_error(seq_zu(int64(1), int64(5), by = -1L), class = "zuint_type_error")
  expect_error(seq_zu(int64(1), int64(5), by = 0L), class = "zuint_type_error")
})

test_that("summary reports the exact extremes", {
  expect_snapshot(summary(int64(c(
    "-9223372036854775807",
    "0",
    "9223372036854775807",
    NA
  ))))
})

test_that("the 64-bit sum is exact at the edges of the range", {
  max64 <- "9223372036854775807"
  expect_identical(sum(int64(c(max64, paste0("-", max64)))), int64(0))
  expect_identical(sum(int64(c(max64, "-1", "1"))), int64(max64))
  expect_warning(
    s <- sum(int64(c(max64, max64))),
    class = "zuint_overflow_warning"
  )
  expect_identical(s, NA_int64_)
  expect_warning(
    sum(int64(c(paste0("-", max64), "-1"))),
    class = "zuint_overflow_warning"
  )
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
    expect_identical(
      as.character(r),
      if (fits) as.character(exact) else NA_character_,
      label = type
    )
  }
})

test_that("seq_zu runs downwards in unsigned types and across whole ranges", {
  expect_identical(
    seq_zu(uint64(10), uint64(1), by = -3L),
    uint64(c(10, 7, 4, 1))
  )
  expect_identical(
    seq_zu(uint128(9), uint128(0), by = int64(-3)),
    uint128(c(9, 6, 3, 0))
  )
  for (type in zu_all_types) {
    r <- oracle_range(type)
    lo <- as.character(r$min)
    hi <- as.character(r$max)
    half <- as.character((r$max - r$min) %/% 2)
    up <- seq_zu(
      zu_ctor(type)(lo),
      zu_ctor(type)(hi),
      by = zu_ctor(if (type %in% c("int64", "int128")) type else type)(half)
    )
    expect_identical(
      as.character(up),
      as.character(c(
        r$min,
        r$min + gmp::as.bigz(half),
        r$min + 2 * gmp::as.bigz(half)
      )),
      label = type
    )
    expect_identical(as.character(utils::tail(up, 1)), hi, label = type)
    steps <- seq_zu(
      zu_ctor(type)(hi),
      zu_ctor(type)(lo),
      by = -2L,
      length.out = 3
    )
    expect_identical(
      as.character(steps),
      as.character(r$max - c(0, 2, 4)),
      label = type
    )
  }
  expect_error(seq_zu(int64(1), int64(5), by = -1L), class = "zuint_type_error")
  expect_error(
    seq_zu(uint64(0), uint64("18446744073709551614"), by = 1L),
    class = "zuint_type_error"
  )
  expect_error(
    seq_zu(
      int64(1),
      int64(5),
      by = int128("170141183460469231731687303715884105727")
    ),
    class = "zuint_type_error"
  )
})

test_that("mean with trim is unsupported rather than ignored", {
  expect_error(mean(int64(1:4), trim = 0.1), class = "zuint_unsupported_error")
  expect_identical(mean(int64(1:4), trim = 0), 2.5)
})

test_that("short and long sorts agree", {
  withr::local_seed(3)
  v <- c(round(runif(70000, -2^52, 2^52)), NA)
  x <- int64(v)
  expect_identical(as.double(sort(x)), sort(v))
  expect_identical(
    as.double(sort(x[1:50], decreasing = TRUE)),
    sort(v[1:50], decreasing = TRUE)
  )
})

test_that("range()'s finite is an argument, not data (#56)", {
  for (type in zu_all_types) {
    x <- zu_ctor(type)(c(5, NA, 7))
    expect_identical(
      range(x, finite = TRUE),
      zu_ctor(type)(c(5, 7)),
      label = type
    )
    expect_identical(range(x, finite = FALSE), zu_na(type, 2), label = type)
    expect_identical(
      range(zu_ctor(type)(c(5, 7)), na.rm = TRUE, finite = TRUE),
      zu_ctor(type)(c(5, 7)),
      label = type
    )
  }
})

test_that("zu_match() and %zin% give base match()'s answers for lost values (#58)", {
  cases <- list(
    list(1.5, int64(c(1, NA)), c(1, NA)),
    list(-1L, uint64(c(3, NA)), c(3, NA)),
    list(c(NA, 1.5, 2), int64(c(2, NA)), c(2, NA)),
    # a table value the type can't hold must not match an NA either
    list(int64(c(NA, 1)), c(1.5, NA, 1), c(1.5, NA, 1)),
    list(int64(NA), c(1.5, 2), c(1.5, 2))
  )
  for (cs in cases) {
    x <- cs[[1]]
    want <- match(if (is.object(x)) as.double(x) else x, cs[[3]])
    expect_no_warning(got <- zu_match(x, cs[[2]]))
    expect_identical(got, want)
    expect_identical(x %zin% cs[[2]], !is.na(want))
  }
  expect_identical(zu_match(1.5, int64(1), nomatch = 0L), 0L)
})

test_that("seq_zu() runs to the top of each unsigned range (#59)", {
  for (type in c("uint64", "uint128")) {
    top <- as.character(oracle_range(type)$max)
    to <- zu_ctor(type)(top)
    from <- to - 3L
    expect_identical(
      as.character(seq_zu(from, to)),
      as.character(gmp::as.bigz(top) - 3:0),
      label = type
    )
    expect_identical(
      seq_zu(to, from, by = -1L),
      rev(seq_zu(from, to)),
      label = type
    )
  }
  expect_error(
    seq_zu(uint128(0), uint128("340282366920938463463374607431768211454")),
    class = "zuint_type_error"
  )
})

test_that("Summary methods give base R's answer when zuint.double allows double (#60)", {
  withr::local_options(zuint.double = "allow")
  expect_warning(r <- sum(int64(1), 0.5), class = "zuint_double_warning")
  expect_identical(r, 1.5)
  expect_warning(r <- prod(int64(3), 0.5), class = "zuint_double_warning")
  expect_identical(r, 1.5)
  expect_warning(r <- min(uint64(1), 0.5), class = "zuint_double_warning")
  expect_identical(r, 0.5)
  expect_warning(r <- max(int128(1), 2.5), class = "zuint_double_warning")
  expect_identical(r, 2.5)
  expect_warning(
    r <- range(int64(c(1, NA)), 2.5, finite = TRUE),
    class = "zuint_double_warning"
  )
  expect_identical(r, c(1, 2.5))
})

test_that("prod() and median() with NA and nothing to reduce (#64)", {
  for (type in zu_all_types) {
    expect_identical(prod(zu_ctor(type)(c(2, NA))), zu_na(type), label = type)
    expect_identical(
      prod(zu_ctor(type)(c(2, NA)), na.rm = TRUE),
      zu_ctor(type)(2),
      label = type
    )
    expect_identical(median(zu_ctor(type)(c(1, NA, 3))), median(c(1, NA, 3)))
    expect_identical(median(zu_ctor(type)()), median(numeric()))
  }
})

test_that("seq_zu() refuses what it can't step and stops at length.out = 0 (#64)", {
  bad <- list(
    list(int64(1:2), int64(5)),
    list(int64(NA), int64(5)),
    list(int64(1), int64(NA)),
    list(int64(1), int64(5), by = NA_integer_),
    list(int64(0), int64("9000000000000000000"))
  )
  for (args in bad) {
    expect_error(do.call(seq_zu, args), class = "zuint_type_error")
  }
  expect_identical(seq_zu(uint64(1), length.out = 0), uint64())
})
