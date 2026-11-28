test_that("vctrs combines by the promotion order and casts exactly", {
  skip_if_not_installed("vctrs")
  expect_identical(vctrs::vec_c(int64(1), uint64(2)), int128(c(1, 2)))
  expect_identical(vctrs::vec_c(uint64(1), 2L), uint64(c(1, 2)))
  expect_identical(vctrs::vec_c(1L, uint128(2)), uint128(c(1, 2)))
  expect_identical(vctrs::vec_c(int64(1), 2), int64(c(1, 2)))
  expect_error(
    vctrs::vec_c(int128(1), uint128(1)),
    class = "vctrs_error_ptype2"
  )
  expect_error(
    vctrs::vec_cast(int64(-1), uint64()),
    class = "vctrs_error_cast_lossy"
  )
  expect_error(vctrs::vec_cast(1.5, int64()), class = "vctrs_error_cast_lossy")
  expect_identical(vctrs::vec_cast(uint64(5), int128()), int128(5))
  skip_if_not_installed("bit64")
  expect_identical(
    vctrs::vec_c(int64(1), bit64::as.integer64(2)),
    int64(c(1, 2))
  )
})

test_that("vctrs slices, compares and orders exactly, beyond 2^53 and NaN patterns", {
  skip_if_not_installed("vctrs")
  for (type in zu_all_types) {
    v <- c(oracle_edges(type), NA, oracle_edges(type)[1:3])
    x <- zu_ctor(type)(v)
    expect_identical(vctrs::vec_slice(x, 2:3), x[2:3], label = type)
    expect_identical(vctrs::vec_unique(x), unique(x), label = type)
    expect_identical(
      vctrs::vec_order(x),
      order(oracle_keys(v), method = "radix"),
      label = type
    )
    expect_identical(vctrs::vec_equal(x, rev(x)), x == rev(x), label = type)
  }
  # -1 and -2 are both NaN bit patterns as doubles
  expect_identical(vctrs::vec_unique_count(int64(c(-1, -2, -1))), 2L)
})

# dplyr's verbs are these vctrs calls; dplyr itself runs in CI's oracle job
# (tools/oracle/test-interop.R).
test_that("vctrs orders, groups, binds and deduplicates data frames of every type", {
  skip_if_not_installed("vctrs")
  for (type in zu_all_types) {
    big <- oracle_range(type)$max
    k <- zu_ctor(type)(c(as.character(big), "1", "0", "1"))
    df <- data.frame(k = k, g = c("a", "b", "a", "b"))
    arranged <- vctrs::vec_slice(df, vctrs::vec_order(df["k"]))
    expect_identical(arranged$k, k[c(3, 2, 4, 1)], label = type)
    groups <- vctrs::vec_split(df$k, df$g)
    expect_identical(
      sum(groups$val[[which(groups$key == "b")]], na.rm = TRUE),
      zu_ctor(type)(2),
      label = type
    )
    expect_identical(vctrs::vec_rbind(df, df)$k, c(k, k), label = type)
    expect_identical(nrow(vctrs::vec_unique(df["k"])), 3L, label = type)
  }
  expect_error(
    vctrs::vec_rbind(data.frame(x = int128(1)), data.frame(x = uint128(1))),
    class = "vctrs_error_ptype2"
  )
})

test_that("tibbles print exact values with short type names", {
  df <- data.frame(
    i64 = int64(c("-9223372036854775807", NA)),
    u64 = uint64(c("18446744073709551614", "0")),
    i128 = int128(c("-1", "170141183460469231731687303715884105727")),
    u128 = uint128(c(NA, "340282366920938463463374607431768211454"))
  )
  expect_snapshot(print(pillar_tbl(df)))
})

test_that("zu_ifelse and zu_vapply keep the type", {
  x <- int64(c("-9223372036854775807", "5", NA))
  expect_identical(zu_ifelse(x > 0L, x, int64(0)), int64(c("0", "5", NA)))
  expect_identical(
    zu_ifelse(c(TRUE, FALSE), uint64(1), int64(-1)),
    int128(c(1, -1))
  )
  expect_identical(
    zu_vapply(1:3, function(i) uint64(2)^i, uint64(0)),
    uint64(c(2, 4, 8))
  )
  expect_identical(zu_vapply(list(), function(i) i, int128(0)), int128())
  expect_identical(
    zu_vapply(c(a = 1, b = 2), function(i) i, int64(0)),
    int64(c(a = 1, b = 2))
  )
  expect_error(
    zu_vapply(1:2, function(i) int64(1:2), int64(0)),
    class = "zuint_type_error"
  )
  expect_error(zu_vapply(1:2, identity, 0), class = "zuint_type_error")
})

test_that("slots vctrs creates are the type's NA, never R's NA bits", {
  skip_if_not_installed("vctrs")
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    expect_identical(vctrs::vec_init(ctor(), 2), ctor(c(NA, NA)), label = type)
    expect_identical(
      vctrs::vec_slice(ctor(c(5, 6)), c(1, NA)),
      ctor(c(5, NA)),
      label = type
    )
    expect_identical(vctrs::vec_c(ctor(1), NA), ctor(c(1, NA)), label = type)
  }
  # the genuine value whose bits are R's NA_real_ stays a value
  nan_bits <- int64("9218868437227407266")
  expect_false(is.na(vctrs::vec_slice(nan_bits, 1)))
  expect_identical(
    vctrs::vec_c(nan_bits, NA),
    int64(c("9218868437227407266", NA))
  )
})

test_that("vctrs padding, unmatched rows, lag and if_else give NA (#25)", {
  skip_if_not_installed("vctrs")
  skip_if_not(exists("vec_case_when", asNamespace("vctrs")))
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    padded <- vctrs::vec_rbind(data.frame(x = ctor(1)), data.frame(y = 1))$x
    expect_identical(padded, ctor(c(1, NA)), label = type)
    # an unmatched join row is an NA index
    v <- ctor(c(7, 8, 9))
    joined <- vctrs::vec_slice(v, vctrs::vec_match(c(1L, 4L), 1:3))
    expect_identical(joined, ctor(c(7, NA)), label = type)
    # dplyr::lag()
    x <- ctor(1:3)
    lagged <- vctrs::vec_c(vctrs::vec_init(x, 1L), vctrs::vec_slice(x, 1:2))
    expect_identical(lagged, ctor(c(NA, 1, 2)), label = type)
    expect_identical(
      vctrs::vec_if_else(c(TRUE, NA, FALSE), ctor(1), ctor(2)),
      ctor(c(1, NA, 2)),
      label = type
    )
    expect_identical(
      vctrs::vec_case_when(list(c(TRUE, FALSE)), list(ctor(3))),
      ctor(c(3, NA)),
      label = type
    )
  }
})

test_that("zu_ifelse keeps the names of test (#35)", {
  expect_identical(
    zu_ifelse(c(a = TRUE, b = FALSE), int64(1), int64(2)),
    int64(c(a = 1, b = 2))
  )
})

test_that("zu_ifelse applies the double rule of c() and the operators", {
  expect_error(zu_ifelse(TRUE, 1.5, int64(2)), class = "zuint_double_error")
  expect_identical(zu_ifelse(c(TRUE, FALSE), 2, int64(3)), int64(c(2, 3)))
})

test_that("vctrs casts zuint vectors to double and integer exactly or not at all", {
  skip_if_not_installed("vctrs")
  expect_identical(vctrs::vec_cast(int64(c(5, NA)), double()), c(5, NA))
  expect_identical(vctrs::vec_cast(uint128(7), integer()), 7L)
  expect_error(
    vctrs::vec_cast(int64("9007199254740993"), double()),
    class = "vctrs_error_cast_lossy"
  )
  expect_error(
    vctrs::vec_cast(int64(2^40), integer()),
    class = "vctrs_error_cast_lossy"
  )
})

test_that("vctrs methods register whichever of vctrs and zuint loads first (#82)", {
  skip_on_cran()
  skip_if_not_installed("vctrs")
  probe <- c(
    "ok <- tryCatch(",
    "  inherits(vctrs::vec_c(zuint::int64(1), 2L), 'zu_int64'),",
    "  error = function(e) FALSE",
    ")",
    "cat(ok)"
  )
  loader <- zuint_loader()
  # zuint first: the hook on vctrs' load registers the methods
  expect_identical(
    fresh_r(c(loader, probe)),
    "TRUE"
  )
  # vctrs first: zuint's .onLoad finds it loaded and registers at once
  expect_identical(
    fresh_r(c("invisible(loadNamespace('vctrs'))", loader, probe)),
    "TRUE"
  )
})

