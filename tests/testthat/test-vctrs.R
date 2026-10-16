test_that("vctrs combines by the promotion order and casts exactly", {
  skip_if_not_installed("vctrs")
  expect_identical(vctrs::vec_c(int64(1), uint64(2)), int128(c(1, 2)))
  expect_identical(vctrs::vec_c(uint64(1), 2L), uint64(c(1, 2)))
  expect_identical(vctrs::vec_c(1L, uint128(2)), uint128(c(1, 2)))
  expect_identical(vctrs::vec_c(int64(1), 2), int64(c(1, 2)))
  expect_error(vctrs::vec_c(int128(1), uint128(1)), class = "vctrs_error_ptype2")
  expect_error(vctrs::vec_cast(int64(-1), uint64()), class = "vctrs_error_cast_lossy")
  expect_error(vctrs::vec_cast(1.5, int64()), class = "vctrs_error_cast_lossy")
  expect_identical(vctrs::vec_cast(uint64(5), int128()), int128(5))
  skip_if_not_installed("bit64")
  expect_identical(vctrs::vec_c(int64(1), bit64::as.integer64(2)), int64(c(1, 2)))
})

test_that("vctrs slices, compares and orders exactly, beyond 2^53 and NaN patterns", {
  skip_if_not_installed("vctrs")
  for (type in zu_all_types) {
    v <- c(oracle_edges(type), NA, oracle_edges(type)[1:3])
    x <- zu_ctor(type)(v)
    expect_identical(vctrs::vec_slice(x, 2:3), x[2:3])
    expect_identical(vctrs::vec_unique(x), unique(x), label = type)
    expect_identical(vctrs::vec_order(x), order(oracle_keys(v), method = "radix"), label = type)
    expect_identical(vctrs::vec_equal(x, rev(x)), x == rev(x))
  }
  # -1 and -2 are both NaN bit patterns as doubles
  expect_identical(vctrs::vec_unique_count(int64(c(-1, -2, -1))), 2L)
})

test_that("dplyr arranges, groups, summarises and binds every type", {
  skip_if_not_installed("dplyr")
  skip_if_not_installed("tibble")
  for (type in zu_all_types) {
    big <- oracle_range(type)$max
    k <- zu_ctor(type)(c(as.character(big), "1", "0", "1"))
    df <- tibble::tibble(k = k, g = c("a", "b", "a", "b"))
    arranged <- dplyr::arrange(df, k)
    expect_identical(arranged$k, k[c(3, 2, 4, 1)], label = type)
    s <- dplyr::summarise(dplyr::group_by(df, g), s = sum(k, na.rm = TRUE), .groups = "drop")
    expect_identical(s$s[[2]], zu_ctor(type)(2))
    expect_identical(dplyr::bind_rows(df, df)$k, c(k, k))
    expect_identical(nrow(dplyr::distinct(df, k)), 3L)
  }
  expect_error(dplyr::bind_rows(tibble::tibble(x = int128(1)), tibble::tibble(x = uint128(1))), class = "vctrs_error_ptype2")
})

test_that("tibbles print exact values with short type names", {
  skip_if_not_installed("tibble")
  skip_if_not_installed("pillar")
  expect_snapshot(print(tibble::tibble(
    i64 = int64(c("-9223372036854775807", NA)),
    u64 = uint64(c("18446744073709551614", "0")),
    i128 = int128(c("-1", "170141183460469231731687303715884105727")),
    u128 = uint128(c(NA, "340282366920938463463374607431768211454"))
  )))
})

test_that("data.table keys on int64 natively", {
  skip_if_not_installed("data.table")
  skip_if_not_installed("bit64")
  dt <- data.table::data.table(k = int64(c("9007199254740993", "9007199254740992", "-1")), v = 1:3)
  data.table::setkey(dt, k)
  expect_identical(dt$v, c(3L, 2L, 1L))
  hit <- merge(dt, data.table::data.table(k = int64("9007199254740993")), by = "k")
  expect_identical(hit$v, 1L)
  # the other types key through text, as documented
  dt2 <- data.table::data.table(k = as.character(uint64(c("18446744073709551614", "1"))), v = 1:2)
  data.table::setkey(dt2, k)
  hit2 <- merge(dt2, data.table::data.table(k = "18446744073709551614"), by = "k")
  expect_identical(hit2$v, 1L)
})

test_that("zu_ifelse and zu_vapply keep the type", {
  x <- int64(c("-9223372036854775807", "5", NA))
  expect_identical(zu_ifelse(x > 0L, x, int64(0)), int64(c("0", "5", NA)))
  expect_identical(zu_ifelse(c(TRUE, FALSE), uint64(1), int64(-1)), int128(c(1, -1)))
  expect_identical(zu_vapply(1:3, function(i) uint64(2)^i, uint64(0)), uint64(c(2, 4, 8)))
  expect_identical(zu_vapply(list(), function(i) i, int128(0)), int128())
  expect_identical(zu_vapply(c(a = 1, b = 2), function(i) i, int64(0)), int64(c(a = 1, b = 2)))
  expect_error(zu_vapply(1:2, function(i) int64(1:2), int64(0)), class = "zuint_type_error")
  expect_error(zu_vapply(1:2, identity, 0), class = "zuint_type_error")
})

test_that("slots vctrs creates are the type's NA, never R's NA bits", {
  skip_if_not_installed("vctrs")
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    expect_identical(vctrs::vec_init(ctor(), 2), ctor(c(NA, NA)), label = type)
    expect_identical(vctrs::vec_slice(ctor(c(5, 6)), c(1, NA)), ctor(c(5, NA)))
    expect_identical(vctrs::vec_c(ctor(1), NA), ctor(c(1, NA)))
  }
  # the genuine value whose bits are R's NA_real_ stays a value
  nan_bits <- int64("9218868437227407266")
  expect_false(is.na(vctrs::vec_slice(nan_bits, 1)))
  expect_identical(vctrs::vec_c(nan_bits, NA), int64(c("9218868437227407266", NA)))
})

test_that("dplyr padding, unmatched joins, lag and if_else give NA", {
  skip_if_not_installed("dplyr")
  skip_if_not_installed("tibble")
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    padded <- dplyr::bind_rows(tibble::tibble(x = ctor(1)), tibble::tibble(y = 1))$x
    expect_identical(padded, ctor(c(1, NA)), label = type)
    a <- tibble::tibble(k = 1:3, v = ctor(c(7, 8, 9)))
    joined <- dplyr::left_join(tibble::tibble(k = c(1L, 4L)), a, by = "k")
    expect_identical(joined$v, ctor(c(7, NA)))
    expect_identical(dplyr::lag(ctor(1:3)), ctor(c(NA, 1, 2)))
    expect_identical(dplyr::if_else(c(TRUE, NA, FALSE), ctor(1), ctor(2)), ctor(c(1, NA, 2)))
    expect_identical(dplyr::case_when(c(TRUE, FALSE) ~ ctor(3)), ctor(c(3, NA)))
  }
})
