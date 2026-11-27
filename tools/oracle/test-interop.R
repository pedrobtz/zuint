# zuint inside dplyr, tibble and data.table, which the package's tests do
# not load (the suite checks the vctrs calls dplyr makes, test-vctrs.R).
# CI's oracle job runs this with the package and its test helpers loaded
# (tools/oracle/README.md):
#
#   Rscript -e 'devtools::load_all(); testthat::test_file("tools/oracle/test-interop.R")'

test_that("dplyr arranges, groups, summarises and binds every type", {
  for (type in zu_all_types) {
    big <- oracle_range(type)$max
    k <- zu_ctor(type)(c(as.character(big), "1", "0", "1"))
    df <- tibble::tibble(k = k, g = c("a", "b", "a", "b"))
    arranged <- dplyr::arrange(df, k)
    expect_identical(arranged$k, k[c(3, 2, 4, 1)], label = type)
    s <- dplyr::summarise(
      dplyr::group_by(df, g),
      s = sum(k, na.rm = TRUE),
      .groups = "drop"
    )
    expect_identical(s$s[[2]], zu_ctor(type)(2), label = type)
    expect_identical(dplyr::bind_rows(df, df)$k, c(k, k), label = type)
    expect_identical(nrow(dplyr::distinct(df, k)), 3L, label = type)
  }
  expect_error(
    dplyr::bind_rows(
      tibble::tibble(x = int128(1)),
      tibble::tibble(x = uint128(1))
    ),
    class = "vctrs_error_ptype2"
  )
})


test_that("data.table keys on int64 natively", {
  skip_if_not_installed("bit64")
  dt <- data.table::data.table(
    k = int64(c("9007199254740993", "9007199254740992", "-1")),
    v = 1:3
  )
  data.table::setkey(dt, k)
  expect_identical(dt$v, c(3L, 2L, 1L))
  hit <- merge(
    dt,
    data.table::data.table(k = int64("9007199254740993")),
    by = "k"
  )
  expect_identical(hit$v, 1L)
  # the other types key through text, as documented
  dt2 <- data.table::data.table(
    k = as.character(uint64(c("18446744073709551614", "1"))),
    v = 1:2
  )
  data.table::setkey(dt2, k)
  hit2 <- merge(
    dt2,
    data.table::data.table(k = "18446744073709551614"),
    by = "k"
  )
  expect_identical(hit2$v, 1L)
})

test_that("dplyr padding, unmatched joins, lag and if_else give NA", {
  for (type in zu_all_types) {
    ctor <- zu_ctor(type)
    padded <- dplyr::bind_rows(
      tibble::tibble(x = ctor(1)),
      tibble::tibble(y = 1)
    )$x
    expect_identical(padded, ctor(c(1, NA)), label = type)
    a <- tibble::tibble(k = 1:3, v = ctor(c(7, 8, 9)))
    joined <- dplyr::left_join(tibble::tibble(k = c(1L, 4L)), a, by = "k")
    expect_identical(joined$v, ctor(c(7, NA)), label = type)
    expect_identical(dplyr::lag(ctor(1:3)), ctor(c(NA, 1, 2)), label = type)
    expect_identical(
      dplyr::if_else(c(TRUE, NA, FALSE), ctor(1), ctor(2)),
      ctor(c(1, NA, 2)),
      label = type
    )
    expect_identical(
      dplyr::case_when(c(TRUE, FALSE) ~ ctor(3)),
      ctor(c(3, NA)),
      label = type
    )
  }
})
