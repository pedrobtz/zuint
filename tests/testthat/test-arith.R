# Each operator x each policy x each pair of operand kinds, against gmp.

test_that("+, -, *, %/% and %% are exact or NA with a warning, for every kind pair", {
  for (ka in zu_all_kinds) {
    for (kb in zu_all_kinds) {
      if (ka == "integer" && kb == "integer") next
      type <- oracle_common(ka, kb)
      va <- oracle_kind_values(ka)
      vb <- oracle_kind_values(kb)
      grid <- expand.grid(a = va, b = vb, stringsAsFactors = FALSE)
      x <- oracle_make(ka, grid$a)
      y <- oracle_make(kb, grid$b)
      label <- paste(ka, kb)
      if (is.na(type)) {
        expect_error(x + y, class = "zuint_incompatible_error", label = label)
        next
      }
      ok_operands <- oracle_fits(type, grid$a) & oracle_fits(type, grid$b)
      for (op in c("+", "-", "*", "%/%", "%%")) {
        exact <- oracle_op(op, gmp::as.bigz(grid$a), gmp::as.bigz(grid$b))
        fits <- !is.na(exact) & oracle_fits(type, oracle_chr(exact)) & ok_operands
        expected <- ifelse(fits, oracle_chr(exact), NA_character_)
        overflow <- !fits & !is.na(exact)
        f <- get(op, baseenv())
        if (any(overflow)) {
          expect_warning(res <- f(x, y), class = "zuint_overflow_warning")
        } else {
          expect_no_warning(res <- f(x, y))
        }
        expect_s3_class(res, paste0("zu_", type))
        expect_identical(as.character(res), expected, label = paste(label, op))
      }
    }
  }
})

test_that("checked_* errors exactly when a result is out of range", {
  for (ka in zu_all_kinds) {
    for (kb in zu_all_types) {
      type <- oracle_common(ka, kb)
      if (is.na(type)) next
      grid <- expand.grid(a = oracle_kind_values(ka), b = oracle_kind_values(kb), stringsAsFactors = FALSE)
      ok_operands <- oracle_fits(type, grid$a) & oracle_fits(type, grid$b)
      for (op in c("+", "-", "*")) {
        f <- switch(op, "+" = checked_add, "-" = checked_sub, "*" = checked_mul)
        exact <- oracle_op(op, gmp::as.bigz(grid$a), gmp::as.bigz(grid$b))
        fits <- oracle_fits(type, oracle_chr(exact)) & ok_operands
        x <- oracle_make(ka, grid$a)
        y <- oracle_make(kb, grid$b)
        label <- paste(ka, op, kb)
        expect_identical(as.character(f(x[fits], y[fits])), oracle_chr(exact[fits]), label = label)
        if (any(!fits)) {
          expect_error(f(x, y), class = "zuint_overflow_error", label = label)
          i <- which(!fits)[[1L]]
          expect_error(f(x[i], y[i]), class = "zuint_overflow_error", label = label)
        }
      }
    }
  }
})

test_that("wrapping_* computes modulo 2^width, with the NA pattern as NA", {
  for (ka in zu_all_kinds) {
    for (kb in zu_all_types) {
      type <- oracle_common(ka, kb)
      if (is.na(type)) next
      grid <- expand.grid(a = oracle_kind_values(ka), b = oracle_kind_values(kb), stringsAsFactors = FALSE)
      x <- oracle_make(ka, grid$a)
      y <- oracle_make(kb, grid$b)
      for (op in c("+", "-", "*")) {
        f <- switch(op, "+" = wrapping_add, "-" = wrapping_sub, "*" = wrapping_mul)
        exact <- oracle_op(op, gmp::as.bigz(grid$a), gmp::as.bigz(grid$b))
        expect_no_warning(res <- f(x, y))
        expect_identical(as.character(res), oracle_chr(oracle_wrap(exact, type)), label = paste(ka, op, kb))
      }
    }
  }
})

test_that("NA in gives NA out under every policy, silently", {
  for (type in zu_all_types) {
    x <- zu_ctor(type)(c(NA, 1, NA))
    y <- zu_ctor(type)(c(1, NA, NA))
    for (f in list(`+`, `-`, `*`, `%/%`, `%%`, checked_add, wrapping_mul, checked_pow, wrapping_pow)) {
      expect_no_warning(res <- f(x, y))
      expect_true(all(is.na(res)))
    }
  }
})

test_that("division by zero is NA without a warning", {
  for (type in zu_all_types) {
    x <- zu_ctor(type)(c(5, 0))
    expect_no_warning(q <- x %/% 0L)
    expect_identical(is.na(q), c(TRUE, TRUE))
    expect_true(all(is.na(x %% zu_ctor(type)(0))))
  }
})

test_that("unary minus negates, and an unsigned non-zero follows the policy", {
  for (type in c("int64", "int128")) {
    edges <- oracle_edges(type)
    expect_identical(as.character(-zu_ctor(type)(edges)), oracle_chr(-gmp::as.bigz(edges)))
  }
  for (type in c("uint64", "uint128")) {
    x <- zu_ctor(type)(c(0, 1, 5))
    expect_warning(res <- -x, class = "zuint_overflow_warning")
    expect_identical(as.character(res), c("0", NA, NA))
    expect_error(checked_neg(x), class = "zuint_overflow_error")
    expect_identical(as.character(checked_neg(x[1])), "0")
    max <- oracle_range(type)$max
    # -1 wraps onto the NA pattern; -5 wraps to MAX - 3
    expect_identical(as.character(wrapping_neg(x)), c("0", NA, as.character(max - 3)))
  }
  expect_identical(+int64(3), int64(3))
})

test_that("^ is exact for non-negative integer exponents", {
  bases <- list(int64 = c("0", "1", "-1", "2", "-2", "3", "-7", "10"), uint64 = c("0", "1", "2", "3", "10"))
  bases$int128 <- bases$int64
  bases$uint128 <- bases$uint64
  exps <- c(0L, 1L, 2L, 5L, 31L, 62L, 63L, 64L, 126L, 127L, 128L, 200L)
  for (type in zu_all_types) {
    grid <- expand.grid(a = bases[[type]], e = exps, stringsAsFactors = FALSE)
    exact <- gmp::as.bigz(grid$a)^grid$e
    fits <- oracle_fits(type, oracle_chr(exact))
    x <- zu_ctor(type)(grid$a)
    if (any(!fits)) {
      expect_warning(res <- x^grid$e, class = "zuint_overflow_warning")
    } else {
      res <- x^grid$e
    }
    expect_identical(as.character(res), ifelse(fits, oracle_chr(exact), NA_character_), label = type)
    expect_identical(as.character(checked_pow(x[fits], grid$e[fits])), oracle_chr(exact[fits]))
    expect_error(checked_pow(x[!fits], grid$e[!fits]), class = "zuint_overflow_error")
    expect_identical(as.character(wrapping_pow(x, grid$e)), oracle_chr(oracle_wrap(exact, type)), label = type)
  }
  # exponents of any integer kind, and integral doubles
  expect_identical(int64(3)^uint128(4), int64(81))
  expect_identical(int64(3)^4, int64(81))
  expect_identical(2L^uint64(10), uint64(1024))
})

test_that("^ with a negative or fractional exponent is computed in double", {
  expect_identical(int64(2)^-1L, 0.5)
  expect_identical(int64(4)^0.5, 2)
  expect_identical(int128(2)^int64(c(-1, 2)), c(0.5, 4))
})

test_that("/ divides in double", {
  expect_identical(int64(7) / 2L, 3.5)
  expect_identical(uint128(1) / uint128(0), Inf)
  expect_identical(names(int64(c(a = 1)) / 2), "a")
})

test_that("mixing types follows the promotion order", {
  expect_s3_class(int64(1) + 1L, "zu_int64")
  expect_s3_class(uint64(1) + 1L, "zu_uint64")
  expect_s3_class(int64(1) + uint64(1), "zu_int128")
  expect_s3_class(uint64(1) + int128(1), "zu_int128")
  expect_s3_class(uint64(1) + uint128(1), "zu_uint128")
  expect_s3_class(1L + uint128(1), "zu_uint128")
  expect_s3_class(TRUE + int64(1), "zu_int64")
  expect_error(int64(1) + uint128(1), class = "zuint_incompatible_error")
  expect_error(int128(1) - uint128(1), class = "zuint_incompatible_error")
  expect_identical(zu_common_type(int64(1), uint64(1)), "int128")
  expect_identical(zu_common_type(uint64(1), 1L, TRUE), "uint64")
  expect_identical(zu_common_type(uint128(1)), "uint128")
  expect_error(zu_common_type(int128(1), uint128(1)), class = "zuint_incompatible_error")
  expect_error(zu_common_type(1L, 2L), class = "zuint_type_error")
  expect_error(zu_common_type(int64(1), 1.5), class = "zuint_type_error")
})

test_that("a negative integer meeting an unsigned type follows the policy", {
  expect_warning(x <- uint64(5) + -1L, class = "zuint_overflow_warning")
  expect_true(is.na(x))
  expect_error(checked_add(uint64(5), -1L), class = "zuint_overflow_error")
  expect_identical(wrapping_add(uint64(5), -1L), uint64(4))
  expect_identical(wrapping_add(uint128(5), -6L), uint128(NA))
  expect_identical(wrapping_mul(uint128(1), -2L), uint128("340282366920938463463374607431768211454"))
})

test_that("doubles must be integral and in range, unless zuint.double allows them", {
  expect_identical(int64(1) + 2, int64(3))
  expect_identical(uint128(1) + 2^100, uint128("1267650600228229401496703205377"))
  expect_error(int64(1) + 1.5, class = "zuint_double_error")
  expect_error(int64(1) * 2^63, class = "zuint_double_error")
  expect_error(uint64(1) + -1, class = "zuint_double_error")
  expect_error(int64(1) + Inf, class = "zuint_double_error")
  expect_identical(int64(1) + NA_real_, int64(NA))
  withr::local_options(zuint.double = "allow")
  expect_warning(r <- int64(3) + 0.5, class = "zuint_double_warning")
  expect_identical(r, 3.5)
  expect_warning(r <- c(int64(1), 0.5), class = "zuint_double_warning")
  expect_identical(r, c(1, 0.5))
})

test_that("an invalid zuint.double option is an error", {
  withr::local_options(zuint.double = "yes")
  expect_error(int64(1) + 1.5, class = "zuint_type_error")
})

test_that("operands that are not numbers are type errors", {
  expect_error(int64(1) + "1", class = "zuint_type_error")
  expect_error(int64(1) == "1", class = "zuint_type_error")
  expect_error(int64(1) + list(1), class = "zuint_type_error")
  expect_error(checked_add(1L, 2L), class = "zuint_type_error")
  expect_error(wrapping_neg(1L), class = "zuint_type_error")
})

test_that("operands recycle, with base R's warning for uneven lengths", {
  expect_identical(int64(1:4) + 1L, int64(2:5))
  expect_identical(1L + int64(1:2) * int64(c(10, 20, 30, 40)), int64(c(11, 41, 31, 81)))
  expect_warning(int64(1:3) + int64(1:2), class = "zuint_recycling_warning")
  expect_identical(int64(1:3) + int64(), int64())
  expect_identical(names(int64(c(a = 1, b = 2)) + 1L), c("a", "b"))
  expect_identical(names(1L + int64(c(a = 1, b = 2))), c("a", "b"))
})

test_that("abs and sign stay in the type; other Math functions use doubles", {
  for (type in zu_all_types) {
    edges <- oracle_edges(type)
    x <- zu_ctor(type)(c(edges, NA))
    expect_identical(as.character(abs(x)), c(oracle_chr(abs(gmp::as.bigz(edges))), NA))
    expect_identical(as.character(sign(x)), c(as.character(sign(gmp::as.bigz(edges))), NA))
    expect_identical(floor(x), x)
    expect_identical(round(x), x)
  }
  expect_identical(sqrt(int64(16)), 4)
  expect_warning(log(int64("9007199254740993")), class = "zuint_precision_warning")
  expect_identical(cumsum(int64(1:3)), int64(c(1, 3, 6)))
})

test_that("!, & and | work on the logical values", {
  x <- int128(c(0, 2, NA))
  expect_identical(!x, c(TRUE, FALSE, NA))
  expect_identical(x & TRUE, c(FALSE, TRUE, NA))
  expect_identical(x | FALSE, c(FALSE, TRUE, NA))
})

test_that("c() takes the common type", {
  x <- c(int64(1), uint64(2), 3L)
  expect_s3_class(x, "zu_int128")
  expect_identical(as.character(x), c("1", "2", "3"))
  expect_error(c(int64(1), uint128(1)), class = "zuint_incompatible_error")
  expect_error(c(int64(1), 1.5), class = "zuint_double_error")
  expect_error(c(int64(1), list()), class = "zuint_type_error")
  expect_warning(y <- c(uint64(1), -1L), class = "zuint_cast_warning")
  expect_identical(is.na(y), c(FALSE, TRUE))
})

test_that("round and signif with negative digits round half to even, as base R", {
  withr::local_seed(17)
  v <- c(round(runif(200, -1e15, 1e15)), 1250, 1350, -1250, -1350, 1249, 15, 25, -15, 0, NA)
  for (type in c("int64", "int128")) {
    x <- zu_ctor(type)(v)
    for (d in c(-1, -2, -3, -7)) {
      expect_identical(as.double(round(x, d)), round(v, d), label = paste(type, d))
    }
    for (d in c(1, 2, 5)) {
      expect_identical(as.double(signif(x, d)), signif(v, d), label = paste(type, "signif", d))
    }
    expect_identical(round(x, 2), x)
  }
  expect_identical(round(int64(1234), digits = -2), int64(1200))
  expect_identical(round(uint64(c(1250, 1350)), -2), uint64(c(1200, 1400)))
  expect_identical(round(uint128("340282366920938463463374607431768211454"), -40), uint128(0))
  expect_warning(r <- round(int64("9223372036854775807"), -1), class = "zuint_overflow_warning")
  expect_true(is.na(r))
  expect_error(round(int64(1), c(1, 2)), class = "zuint_type_error")
})

test_that("checked_idiv and checked_mod error on a zero divisor", {
  for (type in zu_all_types) {
    x <- zu_ctor(type)(c(7, 9))
    expect_identical(checked_idiv(x, 2L), zu_ctor(type)(c(3, 4)))
    expect_identical(checked_mod(x, zu_ctor(type)(4)), zu_ctor(type)(c(3, 1)))
    expect_error(checked_idiv(x, 0L), class = "zuint_division_error")
    expect_error(checked_mod(x, zu_ctor(type)(c(1, 0))), class = "zuint_division_error")
    expect_identical(checked_idiv(zu_ctor(type)(NA), 2L), zu_ctor(type)(NA))
  }
  expect_true(is.na(int64(5) %/% 0L))
})
