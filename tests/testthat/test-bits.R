test_that("bit_and, bit_or, bit_xor and bit_not match a bit-string oracle", {
  ops <- list(
    and = list(bit_and, function(a, b) ifelse(a == "1" & b == "1", "1", "0")),
    or = list(bit_or, function(a, b) ifelse(a == "1" | b == "1", "1", "0")),
    xor = list(bit_xor, function(a, b) ifelse(a != b, "1", "0"))
  )
  for (type in zu_all_types) {
    v <- c(oracle_edges(type), oracle_random(type, 40, seed = 11))
    grid <- expand.grid(a = v, b = v[1:12], stringsAsFactors = FALSE)
    x <- zu_ctor(type)(grid$a)
    y <- zu_ctor(type)(grid$b)
    ba <- oracle_bits(gmp::as.bigz(grid$a), type)
    bb <- oracle_bits(gmp::as.bigz(grid$b), type)
    for (name in names(ops)) {
      expected <- oracle_chr(oracle_from_bits(oracle_bitop(ba, bb, ops[[name]][[2L]]), type))
      res <- withCallingHandlers(
        ops[[name]][[1L]](x, y),
        zuint_overflow_warning = function(w) invokeRestart("muffleWarning")
      )
      expect_identical(as.character(res), expected, label = paste(type, name))
    }
    notb <- oracle_chr(oracle_from_bits(chartr("01", "10", ba), type))
    res <- suppressWarnings(bit_not(x))
    expect_identical(as.character(res), notb, label = paste(type, "not"))
  }
})

test_that("a result on the NA pattern is NA with an overflow warning", {
  expect_warning(x <- bit_not(int64("9223372036854775807")), class = "zuint_overflow_warning")
  expect_identical(x, NA_int64_)
  expect_warning(x <- bit_or(uint64("0xffffffff00000000"), uint64("0xffffffff")), class = "zuint_overflow_warning")
  expect_identical(x, NA_uint64_)
  expect_warning(shift_left(int128(1), 127L), class = "zuint_overflow_warning")
})

test_that("shifts match multiplication and floor division by powers of two", {
  for (type in zu_all_types) {
    w <- zu_width(type)
    v <- c(oracle_edges(type), oracle_random(type, 20, seed = 5))
    grid <- expand.grid(a = v, n = c(0L, 1L, 7L, 31L, 63L, w - 1L), stringsAsFactors = FALSE)
    grid <- grid[grid$n < w, ]
    x <- zu_ctor(type)(grid$a)
    big <- gmp::as.bigz(grid$a)
    p <- gmp::as.bigz(2)^grid$n
    # left: the low `w` bits of a * 2^n, read in the type
    left <- oracle_wrap(big * p, type)
    res <- suppressWarnings(shift_left(x, grid$n))
    expect_identical(as.character(res), oracle_chr(left), label = paste(type, "left"))
    right <- big %/% p
    expect_identical(as.character(shift_right(x, grid$n)), oracle_chr(right), label = paste(type, "right"))
  }
})

test_that("shifts by a negative amount or by the width are NA", {
  for (type in zu_all_types) {
    x <- zu_ctor(type)(1)
    w <- zu_width(type)
    expect_no_warning(r <- shift_left(x, c(-1L, w, w + 1L, NA)))
    expect_identical(r, zu_na(type, 4), label = type)
    expect_identical(shift_right(x, c(-1L, w)), zu_na(type, 2), label = type)
  }
  expect_identical(shift_left(uint64(1), 3), uint64(8))
  expect_identical(shift_left(uint64(c(1, 2)), int64(1)), uint64(c(2, 4)))
})

test_that("popcount, clz and ctz count over the full width", {
  for (type in zu_all_types) {
    w <- zu_width(type)
    v <- c(oracle_edges(type), oracle_random(type, 40, seed = 9))
    bits <- oracle_bits(gmp::as.bigz(v), type)
    x <- zu_ctor(type)(v)
    ones <- nchar(gsub("0", "", bits))
    lead <- nchar(sub("1.*$", "", bits))
    trail <- nchar(sub("^.*1", "", bits))
    trail[ones == 0L] <- w
    expect_identical(popcount(x), as.integer(ones), label = type)
    expect_identical(clz(x), as.integer(lead), label = type)
    expect_identical(ctz(x), as.integer(trail), label = type)
    expect_identical(popcount(zu_ctor(type)(NA)), NA_integer_, label = type)
  }
})

test_that("bit operations mix types by the promotion order and reject doubles", {
  expect_s3_class(bit_and(int64(1), uint64(3)), "zu_int128")
  expect_identical(bit_or(uint64(4), 1L), uint64(5))
  expect_error(bit_and(int64(1), 1), class = "zuint_type_error")
  expect_error(bit_and(int128(1), uint128(1)), class = "zuint_incompatible_error")
  expect_error(popcount(1L), class = "zuint_type_error")
  expect_identical(names(bit_xor(uint64(c(a = 1, b = 2)), 1L)), c("a", "b"))
})
