test_that("comparison is exact across every pair of kinds", {
  ops <- c("==", "!=", "<", "<=", ">", ">=")
  for (ka in zu_all_kinds) {
    for (kb in zu_all_kinds) {
      if (ka == "integer" && kb == "integer") next
      grid <- expand.grid(a = oracle_kind_values(ka), b = oracle_kind_values(kb), stringsAsFactors = FALSE)
      x <- oracle_make(ka, grid$a)
      y <- oracle_make(kb, grid$b)
      a <- gmp::as.bigz(grid$a)
      b <- gmp::as.bigz(grid$b)
      for (op in ops) {
        f <- get(op, baseenv())
        expect_identical(f(x, y), as.vector(f(a, b)), label = paste(ka, op, kb))
      }
    }
  }
})

test_that("comparison with a double is exact and never an error", {
  doubles <- c(0, 1, -1, 1.5, -1.5, 2^53, 2^53 + 2, 2^63, -2^63, 2^64, 2^127, -2^127, 2^128, 1e300, -1e300, 0.25)
  for (type in zu_all_types) {
    v <- oracle_edges(type)
    grid <- expand.grid(a = v, d = doubles, stringsAsFactors = FALSE)
    x <- zu_ctor(type)(grid$a)
    a <- gmp::as.bigq(gmp::as.bigz(grid$a))
    d <- gmp::as.bigq(grid$d)
    for (op in c("==", "!=", "<", "<=", ">", ">=")) {
      f <- get(op, baseenv())
      expect_identical(f(x, grid$d), as.vector(f(a, d)), label = paste(type, op))
      expect_identical(f(grid$d, x), as.vector(f(d, a)), label = paste(op, type))
    }
  }
  x <- int64(c(-5, 0, 5))
  expect_identical(x < Inf, c(TRUE, TRUE, TRUE))
  expect_identical(x > -Inf, c(TRUE, TRUE, TRUE))
  expect_identical(x == NaN, c(NA, NA, NA))
  expect_identical(int64(1) == 1.5, FALSE)
  expect_identical(int64(1) < 1.5, TRUE)
  # 2^53 + 1 is not a double; the nearest double is 2^53
  expect_identical(int64("9007199254740993") == 2^53, FALSE)
  expect_identical(int64("9007199254740993") > 2^53, TRUE)
})

test_that("comparison handles NA and keeps names", {
  x <- uint128(c(a = 1, b = NA))
  expect_identical(x == uint128(1), c(a = TRUE, b = NA))
  expect_identical(x > NA_integer_, c(a = NA, b = NA))
})

test_that("types without a common type still compare", {
  expect_true(int128(-1) < uint128(0))
  expect_true(int64(-1) != uint128("340282366920938463463374607431768211454"))
  expect_false(int128("170141183460469231731687303715884105727") >= uint128("170141183460469231731687303715884105728"))
})

test_that("comparing with NULL gives logical(0), as in base R", {
  expect_identical(int64(1) == NULL, logical(0))
  expect_identical(NULL < uint128(1:2), logical(0))
})
