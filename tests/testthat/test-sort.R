test_that("sort and order match an exact reference, stably, with every na.last", {
  for (type in zu_all_types) {
    v <- c(
      oracle_edges(type),
      oracle_random(type, 60, seed = 21),
      NA,
      oracle_edges(type)[1:4],
      NA
    )
    x <- zu_ctor(type)(v)
    keys <- oracle_keys(v)
    for (na_last in list(TRUE, FALSE, NA)) {
      for (decreasing in c(FALSE, TRUE)) {
        ref <- order(
          keys,
          na.last = na_last,
          decreasing = decreasing,
          method = "radix"
        )
        expect_identical(
          order(x, na.last = na_last, decreasing = decreasing),
          ref,
          label = paste(type, na_last, decreasing)
        )
        expect_identical(
          sort(x, decreasing = decreasing, na.last = na_last),
          x[ref],
          label = type
        )
      }
    }
  }
})

test_that("order() on a data frame with a wide key and a second key is exact beyond 2^53", {
  for (type in zu_all_types) {
    k <- zu_ctor(type)(c(
      "9007199254740993",
      "9007199254740992",
      "9007199254740993",
      "9007199254740994"
    ))
    df <- data.frame(k = k, j = c(2, 1, 1, 0))
    expect_identical(order(df$k, df$j), c(2L, 3L, 1L, 4L), label = type)
    expect_identical(
      rownames(df[order(df$k, -df$j), ]),
      c("2", "1", "3", "4"),
      label = type
    )
  }
})

test_that("xtfrm gives integer ranks with ties sharing the lowest", {
  x <- uint128(c("340282366920938463463374607431768211454", "5", NA, "5", "0"))
  expect_identical(xtfrm(x), c(4L, 2L, NA, 2L, 1L))
  expect_identical(
    rank(x, na.last = "keep", ties.method = "min"),
    c(4L, 2L, NA, 2L, 1L)
  )
})

test_that("sorting agrees with base R on values below 2^53", {
  withr::local_seed(4)
  v <- c(round(runif(300, -2^52, 2^52)), NA, 0, 0)
  for (type in c("int64", "int128")) {
    x <- zu_ctor(type)(v)
    expect_identical(as.double(sort(x)), sort(v), label = type)
    expect_identical(
      order(x, decreasing = TRUE),
      order(v, decreasing = TRUE, method = "radix"),
      label = type
    )
  }
})

test_that("unique, duplicated and match agree with exact references, with word collisions", {
  for (type in zu_all_types) {
    v <- c(oracle_collisions(type), oracle_random(type, 30, seed = 2), NA, NA)
    v <- c(v, sample(v, 20, replace = TRUE))
    x <- zu_ctor(type)(v)
    expect_identical(duplicated(x), duplicated(v), label = type)
    expect_identical(
      duplicated(x, fromLast = TRUE),
      duplicated(v, fromLast = TRUE),
      label = type
    )
    expect_identical(as.character(unique(x)), unique(v), label = type)
    expect_identical(anyDuplicated(x), anyDuplicated(v), label = type)
    tab <- rev(unique(v))
    expect_identical(match(x, zu_ctor(type)(tab)), match(v, tab), label = type)
    expect_identical(
      x %in% zu_ctor(type)(tab[1:5]),
      v %in% tab[1:5],
      label = type
    )
    expect_identical(
      zu_match(x, zu_ctor(type)(tab)),
      match(v, tab),
      label = type
    )
    expect_identical(
      x %zin% zu_ctor(type)(tab[1:5]),
      v %in% tab[1:5],
      label = type
    )
  }
  expect_identical(anyDuplicated(int64(1:3)), 0L)
  expect_identical(zu_match(int64(3), uint64(c(1, 3))), 2L)
  expect_identical(zu_match(1L, int128(c(2, 1)), nomatch = 0L), 2L)
  expect_identical(zu_match(int64(9), int64(1:3), nomatch = 0L), 0L)
  expect_error(
    zu_match(int128(1), uint128(1)),
    class = "zuint_incompatible_error"
  )
})

test_that("mtfrm() is the exact decimal text, so match() cannot tie wide values", {
  x <- int64(c("9007199254740993", "9007199254740992", NA))
  expect_identical(mtfrm(x), c("9007199254740993", "9007199254740992", NA))
  expect_identical(match(int64("9007199254740993"), x), 1L)
})

test_that("table counts exact values", {
  x <- uint64(c(
    "18446744073709551614",
    "18446744073709551613",
    "18446744073709551614"
  ))
  tab <- table(x)
  expect_identical(
    names(tab),
    c("18446744073709551613", "18446744073709551614")
  )
  expect_identical(as.vector(tab), c(1L, 2L))
})
