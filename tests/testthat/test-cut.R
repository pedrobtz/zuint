test_that("cut() agrees with base cut() where the values are exact", {
  x_int <- c(-7L, -3L, 0L, 1L, 3L, 4L, 10L, 11L, NA, 3L)
  breaks_set <- list(c(0, 3, 10), c(-7, 0, 11), c(10, 0, 3), c(-100, 5, 100))
  for (type in zu_vector_types) {
    ctor <- zu_ctor(type)
    # an unsigned type holds no negative value
    keep <- if (type %in% c("uint64", "uint128")) {
      is.na(x_int) | x_int >= 0L
    } else {
      rep(TRUE, length(x_int))
    }
    xi <- x_int[keep]
    x <- ctor(xi)
    for (b in test_thin(breaks_set, 2L)) {
      for (right in c(TRUE, FALSE)) {
        for (lowest in c(TRUE, FALSE)) {
          label <- paste(type, paste(b, collapse = ","), right, lowest)
          expect_identical(
            cut(x, b, right = right, include.lowest = lowest),
            cut(xi, b, right = right, include.lowest = lowest),
            label = label
          )
          expect_identical(
            cut(x, b, labels = FALSE, right = right, include.lowest = lowest),
            cut(xi, b, labels = FALSE, right = right, include.lowest = lowest),
            label = label
          )
        }
      }
    }
    expect_identical(
      cut(x, c(0, 3, 10), labels = c("a", "b"), ordered_result = TRUE),
      cut(xi, c(0, 3, 10), labels = c("a", "b"), ordered_result = TRUE),
      label = type
    )
  }
})

test_that("cut() takes zuint, integer, double and fractional breaks", {
  x <- int64(c(-5, 0, 1, 2, 3, NA))
  ref <- cut(c(-5, 0, 1, 2, 3, NA), c(-10, 0.5, 2, 3))
  expect_identical(cut(x, c(-10, 0.5, 2, 3)), ref)
  expect_identical(cut(x, c(-10, 0, 2, 3)), cut(x, c(-10L, 0L, 2L, 3L)))
  expect_identical(cut(x, c(-10, 0, 2, 3)), cut(x, int64(c(-10, 0, 2, 3))))
  expect_identical(cut(x, c(-10, 0, 2, 3)), cut(x, int128(c(3, 0, -10, 2))))
  expect_identical(
    cut(x, c(-Inf, 0, Inf), labels = FALSE),
    c(1L, 1L, 2L, 2L, 2L, NA)
  )
  expect_identical(
    levels(cut(x, c(-Inf, 0, Inf))),
    c("(-Inf,0]", "(0,Inf]")
  )
})

test_that("cut() is exact beyond 2^53 and at the type edges", {
  skip_if_not_installed("gmp")
  # the reference scans the sorted breaks with gmp comparisons
  ref <- function(v, b, right, lowest) {
    b <- sort(b)
    nb <- length(b)
    vapply(
      seq_along(v),
      function(i) {
        if (is.na(v[i])) {
          return(NA_integer_)
        }
        for (k in seq_len(nb - 1L)) {
          lo <- b[k]
          hi <- b[k + 1L]
          inside <- if (right) {
            v[i] > lo && v[i] <= hi
          } else {
            v[i] >= lo && v[i] < hi
          }
          if (lowest && right && k == 1L && v[i] == lo) {
            inside <- TRUE
          }
          if (lowest && !right && k == nb - 1L && v[i] == hi) {
            inside <- TRUE
          }
          if (inside) return(k)
        }
        NA_integer_
      },
      integer(1)
    )
  }
  for (type in zu_all_types) {
    r <- oracle_range(type)
    two <- gmp::as.bigz(2)
    v <- c(
      oracle_edges(type),
      as.character(two^53 + 2:3),
      as.character(r$min),
      as.character(r$max)
    )
    v <- unique(v)
    # breaks on the values double would tie: 2^53 and its neighbours
    b <- gmp::as.bigz(c(two^53, two^53 + 1, r$max - 1))
    b <- b[b <= r$max]
    x <- zu_ctor(type)(c(v, NA))
    bz <- zu_ctor(type)(as.character(b))
    for (right in c(TRUE, FALSE)) {
      for (lowest in c(TRUE, FALSE)) {
        expect_identical(
          cut(x, bz, labels = FALSE, right = right, include.lowest = lowest),
          ref(c(gmp::as.bigz(v), NA), b, right, lowest),
          label = paste(type, right, lowest)
        )
      }
    }
    # breaks at the edges of the type
    edges <- c(r$min, r$max)
    expect_identical(
      cut(
        x,
        zu_ctor(type)(as.character(edges)),
        labels = FALSE,
        include.lowest = TRUE
      ),
      ref(c(gmp::as.bigz(v), NA), edges, TRUE, TRUE),
      label = type
    )
  }
  # labels are the breaks' exact text, not three digits
  x <- int64("9007199254740993")
  expect_identical(
    levels(cut(x, int64(c("9007199254740992", "9007199254740993")))),
    "(9007199254740992,9007199254740993]"
  )
  expect_identical(
    cut(x, int64(c("9007199254740992", "9007199254740993")), labels = FALSE),
    1L
  )
})

test_that("cut() refuses what it cannot do exactly", {
  x <- int64(1:5)
  expect_error(cut(x, 2), class = "zuint_unsupported_error")
  expect_error(cut(x, c(1, NA, 3)), class = "zuint_type_error")
  expect_error(cut(x, c(1, 1, 3)), class = "zuint_type_error")
  expect_error(
    cut(x, c(1, 3), labels = c("a", "b")),
    class = "zuint_type_error"
  )
  expect_error(cut(x, c(1, 3), right = NA), class = "zuint_type_error")
  expect_error(cut(x, "a"), class = "zuint_type_error")
})
