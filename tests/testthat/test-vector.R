test_that("[ keeps the class and pads out-of-range positions with the type's NA", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(a = 1, b = 2, c = 3))
    expect_identical(x[2:3], zu_ctor(type)(c(b = 2, c = 3)), label = type)
    expect_identical(x[-1], x[2:3], label = type)
    expect_identical(x[c(TRUE, FALSE, TRUE)], x[c(1, 3)], label = type)
    expect_identical(x["b"], x[2], label = type)
    expect_identical(x[], x, label = type)
    y <- x[c(1, 5, NA)]
    expect_identical(
      is.na(y),
      structure(c(FALSE, TRUE, TRUE), names = c("a", NA, NA)),
      label = type
    )
    expect_identical(as.character(y), c("1", NA, NA), label = type)
  }
})

test_that("[[ extracts one element without its name", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(a = 1, b = 2))
    expect_identical(x[[2]], zu_ctor(type)(2), label = type)
    expect_identical(x[["a"]], zu_ctor(type)(1), label = type)
    expect_error(x[[3]], class = "subscriptOutOfBoundsError")
  }
})

test_that("[<- casts the value to the vector's type", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(1:4)
    x[2] <- 20L
    x[3:4] <- c("30", "40")
    expect_identical(as.character(x), c("1", "20", "30", "40"), label = type)
    x[] <- 0
    expect_identical(as.character(x), rep("0", 4), label = type)
  }
  x <- int64(1:2)
  expect_warning(x[1] <- 1.5, class = "zuint_cast_warning")
  expect_identical(is.na(x), c(TRUE, FALSE))
  x <- int64(1)
  x[1] <- uint64("9223372036854775807")
  expect_identical(as.character(x), "9223372036854775807")
  expect_warning(
    x[1] <- uint64("9223372036854775808"),
    class = "zuint_cast_warning"
  )
})

test_that("[<- beyond the end pads with the type's NA", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(1)
    x[4] <- 4
    expect_identical(as.character(x), c("1", NA, NA, "4"), label = type)
    y <- zu_ctor(type)(c(a = 1))
    y["c"] <- 3
    expect_identical(names(y), c("a", "c"), label = type)
    expect_identical(as.character(y), c("1", "3"), label = type)
    z <- zu_ctor(type)(1)
    z[[3]] <- 3
    expect_identical(as.character(z), c("1", NA, "3"), label = type)
  }
})

test_that("[[<- casts the value", {
  x <- uint128(1:2)
  x[[2]] <- "340282366920938463463374607431768211454"
  expect_identical(
    as.character(x[[2]]),
    "340282366920938463463374607431768211454"
  )
  expect_warning(x[[1]] <- -1L, class = "zuint_cast_warning")
  expect_identical(x[[1]], NA_uint128_)
})

test_that("length<- truncates or pads with NA", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(1:3)
    length(x) <- 5
    expect_identical(as.character(x), c("1", "2", "3", NA, NA), label = type)
    length(x) <- 2
    expect_identical(x, zu_ctor(type)(1:2), label = type)
  }
})

test_that("c() converts every argument to the common type", {
  x <- c(int64(1), 2L, 3, "4", NA, uint64(5), a = int128(6))
  expect_identical(class(x), class(int128()))
  expect_identical(as.character(x), c("1", "2", "3", "4", NA, "5", "6"))
  expect_identical(names(x), c("", "", "", "", "", "", "a"))
  expect_warning(y <- c(uint64(1), -1L), class = "zuint_cast_warning")
  expect_identical(is.na(y), c(FALSE, TRUE))
  expect_identical(c(uint128(1)), uint128(1))
  expect_identical(c(int128(1), NULL), int128(1))
})

test_that("rep and rev keep the type and names", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(a = 1, b = NA))
    expect_identical(
      rep(x, 2),
      zu_ctor(type)(c(a = 1, b = NA, a = 1, b = NA)),
      label = type
    )
    expect_identical(rep(x, each = 2), x[c(1, 1, 2, 2)], label = type)
    expect_identical(rep(x, length.out = 3), x[c(1, 2, 1)], label = type)
    expect_identical(rev(x), x[2:1], label = type)
    expect_identical(rev(zu_ctor(type)()), zu_ctor(type)(), label = type)
  }
})

test_that("is.na, is.na<- and anyNA see only the type's NA", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(a = 0, b = NA, c = 1))
    expect_identical(is.na(x), c(a = FALSE, b = TRUE, c = FALSE), label = type)
    expect_true(anyNA(x), label = type)
    expect_false(anyNA(x[-2]), label = type)
    is.na(x) <- 3
    expect_identical(is.na(x), c(a = FALSE, b = TRUE, c = TRUE), label = type)
  }
  # bits that base R reads as NaN or NA are ordinary values here
  x <- int64(c("-1", "-9223372036854775807"))
  expect_false(any(is.na(x)))
  expect_false(anyNA(uint64("18446744073709551614")))
})

test_that("as.double is exact up to 2^53 and warns when it rounds", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(0, 1, 2^53, NA))
    expect_no_warning(d <- as.double(x))
    expect_identical(d, c(0, 1, 2^53, NA), label = type)
    expect_identical(as.numeric(x), as.double(x), label = type)
  }
  expect_identical(as.double(int64(-2^53)), -2^53)
  expect_warning(
    d <- as.double(int64("9007199254740993")),
    class = "zuint_precision_warning"
  )
  expect_identical(d, 2^53)
  # 2^60 is exact, so no warning
  expect_no_warning(d <- as.double(int64(2^60)))
  expect_identical(d, 2^60)
  expect_warning(
    d <- as.double(uint128("340282366920938463463374607431768211454")),
    class = "zuint_precision_warning"
  )
  expect_identical(d, 2^128)
  # round to nearest, ties to even, from 128 bits
  expect_warning(
    d <- as.double(int128("-170141183460469231731687303715884105727")),
    class = "zuint_precision_warning"
  )
  expect_identical(d, -2^127)
  expect_warning(
    d <- as.double(uint128("18446744073709553665")),
    class = "zuint_precision_warning"
  )
  expect_identical(d, 2^64 + 4096)
})

test_that("as.integer is exact within the integer range, NA with a warning outside", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(0, 2147483647, NA))
    expect_no_warning(i <- as.integer(x))
    expect_identical(i, c(0L, 2147483647L, NA), label = type)
  }
  expect_identical(as.integer(int64(-2147483647)), -2147483647L)
  expect_warning(
    i <- as.integer(int64(c(2^31, -2^31))),
    class = "zuint_cast_warning"
  )
  expect_identical(i, c(NA_integer_, NA_integer_))
})

test_that("as.logical is FALSE for zero and NA for NA", {
  expect_identical(as.logical(int128(c(0, -3, NA))), c(FALSE, TRUE, NA))
})

test_that("as.logical is v != 0 against gmp, names dropped as base does (#81)", {
  for (type in zu_all_types) {
    v <- oracle_edges(type)
    if (zu_width(type) == 128L) {
      # a zero low word under a non-zero high word
      v <- c(
        v,
        "18446744073709551616",
        "340282366920938463463374607431768211454"
      )
      v <- v[oracle_fits(type, v)]
    }
    x <- zu_ctor(type)(c(v, NA))
    names(x) <- seq_along(x)
    want <- c(as.logical(gmp::as.bigz(v) != 0), NA)
    expect_identical(as.logical(x), want, label = type)
  }
  # base as.logical() drops names too
  expect_null(names(as.logical(c(a = 1, b = 0))))
})

test_that("as.character drops names and gives NA_character_ for NA", {
  expect_identical(as.character(uint64(c(a = 1, b = NA))), c("1", NA))
})

test_that("as.list gives one element per value", {
  x <- int128(c(a = 1, b = NA))
  expect_identical(as.list(x), list(a = int128(1), b = int128(NA)))
})

test_that("zuint vectors work as data frame columns", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(1, NA, 3))
    df <- data.frame(id = 1:3, v = x)
    expect_identical(df$v, x, label = type)
    expect_identical(df[2:3, "v"], x[2:3], label = type)
    expect_identical(as.vector(format(df)$v), c(" 1", "NA", " 3"), label = type)
  }
})

test_that("format right-justifies and keeps names", {
  expect_identical(
    format(int64(c(a = 1, b = -100, c = NA))),
    c(a = "   1", b = "-100", c = "  NA")
  )
  expect_identical(format(uint64(1:2), width = 3), c("  1", "  2"))
})

test_that("print, str and summary show exact values", {
  expect_snapshot({
    print(int64(c(a = "1", b = NA, c = "-9223372036854775807")))
    print(uint128(c("340282366920938463463374607431768211454", "0")))
    print(int128())
    str(uint64(c(1, 2, NA)))
    str(int128(-1))
    str(int64(1:20))
    summary(int128(c("-170141183460469231731687303715884105727", "5", NA)))
    summary(uint64(1:3))
  })
})

test_that("multi-dimensional indexing is a type error", {
  x <- int64(1:4)
  expect_error(x[1, 2], class = "zuint_type_error")
  expect_error(x[1, 2] <- 3, class = "zuint_type_error")
})

test_that("each class claims mixed Ops calls", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(1)
    expect_true(chooseOpsMethod(x, 1, NULL, NULL, NULL, FALSE), label = type)
  }
})

test_that("is.nan, is.finite and is.infinite read values, not raw bits", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(a = "1", b = NA, c = "0"))
    expect_identical(
      is.nan(x),
      c(a = FALSE, b = FALSE, c = FALSE),
      label = type
    )
    expect_identical(
      is.finite(x),
      c(a = TRUE, b = FALSE, c = TRUE),
      label = type
    )
    expect_identical(
      is.infinite(x),
      c(a = FALSE, b = FALSE, c = FALSE),
      label = type
    )
    expect_true(is.numeric(x), label = type)
  }
  # -1 is a NaN bit pattern as a double
  expect_false(is.nan(int64(-1)))
  expect_true(is.finite(int64(-1)))
})

test_that("conversions to complex, raw and dates go through the values", {
  # base's own conversion of the doubles, NA included, on every R version
  expect_identical(as.complex(int128(c(-5, NA))), as.complex(c(-5, NA)))
  expect_identical(as.raw(uint64(c(5, 255))), as.raw(c(5, 255)))
  expect_identical(as.Date(int64(1)), as.Date(1))
  expect_identical(as.POSIXct(int64(0), tz = "UTC"), as.POSIXct(0, tz = "UTC"))
  expect_identical(
    as.POSIXlt(uint128(0), tz = "UTC"),
    as.POSIXlt(0, tz = "UTC")
  )
})

test_that("seq() on a zuint from is seq_zu()", {
  expect_identical(seq(int64(1), int64(5)), int64(1:5))
  expect_identical(seq(uint64(2), by = 3L, length.out = 3), uint64(c(2, 5, 8)))
  expect_identical(seq(int128(4), along.with = 1:3), int128(4:6))
  expect_identical(seq(int64(1), int64(5), length.out = 3), int64(c(1, 3, 5)))
})

test_that("all.equal compares exactly", {
  expect_true(all.equal(int64(1:3), int64(1:3)))
  expect_identical(
    all.equal(int64(1:3), int64(c(1, 2, 4))),
    "1 of 3 values differ"
  )
  expect_identical(
    all.equal(int64(1), uint64(1)),
    "Types differ: int64 vs uint64"
  )
  expect_match(all.equal(int64(1), 1), "target is int64")
})

test_that("quantile and matrices are unsupported rather than computed on bits", {
  expect_error(quantile(int64(1:4)), class = "zuint_unsupported_error")
  expect_error(cbind(int64(1:2), 1:2), class = "zuint_unsupported_error")
  expect_error(rbind(uint128(1)), class = "zuint_unsupported_error")
  expect_error(as.matrix(int64(1)), class = "zuint_unsupported_error")
  expect_error(aperm(int128(1)), class = "zuint_unsupported_error")
  expect_error(scale(uint64(1:2)), class = "zuint_unsupported_error")
})

test_that("a zuint vector used as an index is read as a number", {
  x <- int64(c(10, 20, 30))
  expect_identical(x[int64(2)], int64(20))
  expect_identical(x[uint128(c(3, 1))], int64(c(30, 10)))
  expect_identical(x[[int128(2)]], int64(20))
  x[uint64(2)] <- 5L
  expect_identical(x, int64(c(10, 5, 30)))
  x[[int64(1)]] <- 9L
  expect_identical(x, int64(c(9, 5, 30)))
  expect_warning(
    r <- x[int64("9007199254740993")],
    class = "zuint_cast_warning"
  )
  expect_identical(r, NA_int64_)
})

test_that("rep() of an empty vector pads with the type's NA (#55)", {
  for (type in zu_vector_types) {
    e <- zu_ctor(type)()
    expect_identical(rep(e, length.out = 3), zu_na(type, 3), label = type)
    expect_identical(rep(e, times = 0), e, label = type)
    expect_identical(rep(e, length.out = 0), e, label = type)
    # a non-empty vector repeats its own values, NA included
    x <- zu_ctor(type)(c(1, NA))
    expect_identical(rep(x, length.out = 3), zu_ctor(type)(c(1, NA, 1)))
  }
  skip_if_not_installed("vctrs")
  expect_identical(
    zu_ifelse(c(TRUE, FALSE), int64(), int64(1)),
    int64(c(NA, 1))
  )
  expect_identical(
    zu_ifelse(c(FALSE, TRUE), uint128(2), uint128()),
    uint128(c(NA, 2))
  )
})

test_that("Conj(), Re(), Im(), Mod() and Arg() refuse every zuint type (#152)", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(5, 0, NA))
    for (fn in c("Conj", "Re", "Im", "Mod", "Arg")) {
      expect_error(
        get(fn)(x),
        class = "zuint_unsupported_error",
        label = paste(type, fn)
      )
    }
  }
})

test_that("%*%, crossprod() and tcrossprod() refuse every zuint type (#160)", {
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(1:2)
    expect_error(x %*% x, class = "zuint_unsupported_error", label = type)
    expect_error(1:2 %*% x, class = "zuint_unsupported_error", label = type)
    expect_error(x %*% 1:2, class = "zuint_unsupported_error", label = type)
  }
  # S3 generic, through matrixOps, since R 4.4.0
  skip_if(getRversion() < "4.4.0")
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(1:2)
    expect_error(crossprod(x), class = "zuint_unsupported_error", label = type)
    expect_error(
      crossprod(1:2, x),
      class = "zuint_unsupported_error",
      label = type
    )
    expect_error(
      tcrossprod(x, x),
      class = "zuint_unsupported_error",
      label = type
    )
  }
})

test_that("a zuint count is read as the number it stands for (#153)", {
  counts <- list(
    int64 = int64,
    uint64 = uint64,
    int128 = int128,
    uint128 = uint128,
    integer64 = function(v) as_integer64(int64(v))
  )
  # the oracle: the same call with the count as an integer
  for (type in zu_vector_types) {
    x <- zu_ctor(type)(c(1, 4, 9, 16))
    names(x) <- c("a", "b", "c", "d")
    for (ck in names(counts)) {
      k <- counts[[ck]]
      label <- paste(type, "with a count of", ck)
      expect_identical(rep(x, times = k(2)), rep(x, times = 2L), label = label)
      expect_identical(rep(x, k(2)), rep(x, 2L), label = label)
      expect_identical(rep(x, each = k(2)), rep(x, each = 2L), label = label)
      expect_identical(
        rep(x, length.out = k(5)),
        rep(x, length.out = 5L),
        label = label
      )
      expect_identical(diff(x, lag = k(2)), diff(x, lag = 2L), label = label)
      expect_identical(
        diff(x, differences = k(2)),
        diff(x, differences = 2L),
        label = label
      )
      expect_identical(head(x, k(2)), head(x, 2L), label = label)
      expect_identical(tail(x, k(3)), tail(x, 3L), label = label)
      y <- x
      length(y) <- k(6)
      z <- x
      length(z) <- 6L
      expect_identical(y, z, label = label)
      expect_identical(
        format(x, width = k(4)),
        format(x, width = 4L),
        label = label
      )
      expect_identical(
        capture.output(print(x, max = k(2))),
        capture.output(print(x, max = 2L)),
        label = label
      )
      expect_identical(
        capture.output(str(x, vec.len = k(1))),
        capture.output(str(x, vec.len = 1L)),
        label = label
      )
    }
    # a signed count counts from the other end, as an integer does
    expect_identical(head(x, int64(-1)), head(x, -1L), label = type)
    expect_identical(tail(x, int128(-3)), tail(x, -3L), label = type)
  }
  for (ck in names(counts)) {
    k <- counts[[ck]]
    expect_identical(
      seq_zu(int64(1), length.out = k(3)),
      int64(1:3),
      label = ck
    )
    expect_identical(seq(uint64(1), length.out = k(3)), uint64(1:3), label = ck)
  }
  # beyond an integer, as an index is: NA with a warning
  expect_warning(
    try(rep(int64(1), times = int64("9007199254740993")), silent = TRUE),
    class = "zuint_cast_warning"
  )
})
