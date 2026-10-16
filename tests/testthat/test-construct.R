test_that("each constructor round-trips its edge values through character", {
  for (type in zu_all_types) {
    edges <- oracle_edges(type)
    x <- zu_ctor(type)(edges)
    expect_s3_class(x, paste0("zu_", type))
    expect_identical(as.character(x), edges, label = type)
    expect_false(anyNA(x), label = type)
  }
})

test_that("random values across each range round-trip through character", {
  for (type in zu_all_types) {
    vals <- oracle_random(type, 500, seed = 20261016)
    expect_identical(as.character(zu_ctor(type)(vals)), vals, label = type)
  }
})

test_that("values just outside each range become NA with a cast warning", {
  for (type in zu_all_types) {
    out <- oracle_outside(type)
    expect_warning(x <- zu_ctor(type)(out), class = "zuint_cast_warning")
    expect_identical(x, zu_na(type, length(out)), label = type)
  }
})

test_that("the NA bit pattern is not a value of any type", {
  # INT64_MIN, UINT64_MAX, INT128_MIN and UINT128_MAX
  sentinels <- c(
    int64 = "-9223372036854775808",
    uint64 = "18446744073709551615",
    int128 = "-170141183460469231731687303715884105728",
    uint128 = "340282366920938463463374607431768211455"
  )
  for (type in names(sentinels)) {
    expect_warning(
      x <- zu_ctor(type)(sentinels[[type]]),
      class = "zuint_cast_warning"
    )
    expect_identical(x, zu_na(type), label = type)
  }
})

test_that("doubles convert when integral and in range, else NA with a warning", {
  for (type in zu_all_types) {
    edges <- oracle_edges(type)
    exact <- edges[gmp::as.bigz(as.double(edges)) == gmp::as.bigz(edges)]
    expect_identical(
      as.character(zu_ctor(type)(as.double(exact))),
      exact,
      label = type
    )
  }
  expect_identical(
    as.character(uint128(2^127)),
    "170141183460469231731687303715884105728"
  )
  expect_identical(
    as.character(int128(-2^126)),
    "-85070591730234615865843651857942052864"
  )
  for (bad in list(1.5, -0.5, Inf, -Inf, 2^63, -2^63)) {
    expect_warning(x <- int64(bad), class = "zuint_cast_warning")
    expect_identical(x, NA_int64_, label = format(bad))
  }
  expect_warning(x <- uint64(-1), class = "zuint_cast_warning")
  expect_identical(x, NA_uint64_)
  expect_identical(as.character(int64(-0)), "0")
})

test_that("NA and NaN convert to NA silently", {
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    expect_no_warning(
      x <- c(
        ctor(NA),
        ctor(NA_integer_),
        ctor(NA_real_),
        ctor(NaN),
        ctor(NA_character_)
      )
    )
    expect_identical(x, zu_na(type, 5), label = type)
  }
})

test_that("logical and integer convert exactly; negatives are lost in unsigned types", {
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    expect_identical(
      as.character(ctor(c(TRUE, FALSE))),
      c("1", "0"),
      label = type
    )
    expect_identical(
      as.character(ctor(.Machine$integer.max)),
      "2147483647",
      label = type
    )
  }
  expect_identical(as.character(int64(-.Machine$integer.max)), "-2147483647")
  expect_identical(as.character(int128(-5L)), "-5")
  expect_warning(x <- uint64(c(1L, -1L)), class = "zuint_cast_warning")
  expect_identical(is.na(x), c(FALSE, TRUE))
  expect_warning(uint128(-1L), class = "zuint_cast_warning")
})

test_that("malformed strings become NA with a warning", {
  bad <- c("-", "1e3", "1.0", "1 2", "+-1", "0x", "1__000", "abc", "--1")
  for (type in zu_all_types) {
    expect_warning(x <- zu_ctor(type)(bad), class = "zuint_cast_warning")
    expect_identical(x, zu_na(type, length(bad)), label = type)
  }
})

test_that("conversion between the types is exact or NA with a warning", {
  for (from in zu_all_types) {
    edges <- oracle_edges(from)
    x <- zu_ctor(from)(edges)
    for (to in zu_all_types) {
      fits <- oracle_fits(to, edges)
      if (all(fits)) {
        expect_no_warning(y <- zu_ctor(to)(x))
      } else {
        expect_warning(y <- zu_ctor(to)(x), class = "zuint_cast_warning")
      }
      expected <- ifelse(fits, edges, NA_character_)
      expect_identical(as.character(y), expected, label = paste(from, "to", to))
    }
  }
})

test_that("constructors keep names and default to length zero", {
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    expect_identical(length(ctor()), 0L, label = type)
    expect_identical(names(ctor(c(a = 1, b = 2))), c("a", "b"), label = type)
    expect_identical(ctor(NULL), ctor(), label = type)
  }
})

test_that("a zuint vector passes through its own constructor unchanged", {
  x <- int128(c(a = 1, b = NA))
  expect_identical(int128(x), x)
})

test_that("unsupported inputs are type errors", {
  expect_error(int64(list(1)), class = "zuint_type_error")
  expect_error(int64(1i), class = "zuint_type_error")
  expect_error(uint64(factor("a")), class = "zuint_type_error")
  expect_error(int128(Sys.Date()), class = "zuint_type_error")
  expect_error(uint128(as.raw(1)), class = "zuint_type_error")
})

test_that("the NA constants are NA of their type", {
  nas <- list(
    int64 = NA_int64_,
    uint64 = NA_uint64_,
    int128 = NA_int128_,
    uint128 = NA_uint128_
  )
  for (type in names(nas)) {
    expect_identical(nas[[type]], zu_ctor(type)(NA), label = type)
    expect_identical(
      zu_storage(nas[[type]]),
      zu_storage(zu_na(type)),
      label = type
    )
  }
})
