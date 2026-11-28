# One condition per call, whatever the number of values it concerns, and the
# wording of each kind in a snapshot (#66). The tests elsewhere assert
# classes only; the count from C and the reported call reach only the
# message, so the snapshot is what pins them.

test_that("a call that loses many values warns once", {
  collect_warnings <- function(expr) {
    seen <- list()
    withCallingHandlers(
      expr,
      warning = function(w) {
        seen[[length(seen) + 1L]] <<- w
        invokeRestart("muffleWarning")
      }
    )
    vapply(seen, function(w) class(w)[[1L]], character(1))
  }
  big <- "9223372036854775807"
  cases <- list(
    zuint_cast_warning = quote(int64(c(1.5, 2.5, 3.5, 4))),
    zuint_cast_warning = quote(uint64(c(-1L, -2L, 3L))),
    zuint_cast_warning = quote(int64(c("x", "y", "1"))),
    zuint_overflow_warning = quote(int64(c(big, big, big)) + 1L),
    zuint_overflow_warning = quote(int64(big) * int64(2:4)),
    zuint_overflow_warning = quote(sum(int64(c(big, big)))),
    zuint_overflow_warning = quote(cumsum(int64(c(big, big, big)))),
    zuint_overflow_warning = quote(bit_not(int64(c(big, big)))),
    zuint_precision_warning = quote(as.double(uint64(c(
      "18446744073709551614",
      "18446744073709551613"
    )))),
    zuint_recycling_warning = quote(int64(1:3) + int64(1:2))
  )
  for (i in seq_along(cases)) {
    got <- collect_warnings(eval(cases[[i]]))
    expect_identical(got, names(cases)[[i]], label = deparse1(cases[[i]]))
  }
})

test_that("condition messages and the calls they report", {
  big <- "9223372036854775807"
  expect_snapshot({
    x <- int64(1.5)
    x <- int64(c(1.5, 2.5, 3.5))
    x <- int64(c(big, big, big)) + 1L
    x <- as.double(uint64("18446744073709551614"))
    x <- int64(1:3) + int64(1:2)
    x <- min(int64())
  })
  expect_snapshot(error = TRUE, int128(1) + uint128(1))
  expect_snapshot(error = TRUE, checked_add(int64(big), 1L))
  expect_snapshot(error = TRUE, checked_idiv(int64(1), 0L))
  expect_snapshot(error = TRUE, int64(1) + 1.5)
  expect_snapshot(error = TRUE, seq_zu(int64(1), int64(5), by = 0L))
  expect_snapshot(error = TRUE, quantile(int64(1:3)))
  withr::local_options(zuint.double = "allow")
  expect_snapshot(x <- int64(1) + 1.5)
})

test_that("every condition reports the user's call (#80)", {
  call_of <- function(expr) {
    tryCatch(expr, condition = function(c) conditionCall(c))
  }
  x <- int64(1:3)
  y <- int64(1:2)
  d <- decimal128(c("1.5", "2.5", "3.5"), 5L, 1L)
  e <- decimal128(c("1.5", "2.5"), 5L, 1L)
  # the recycling warning, from each kind of operation that checks it
  expect_identical(call_of(x + y), quote(Ops.zu_int64(x, y)))
  expect_identical(call_of(x == y), quote(Ops.zu_int64(x, y)))
  expect_identical(call_of(x^y), quote(Ops.zu_int64(x, y)))
  expect_identical(call_of(bit_and(x, y)), quote(bit_and(x, y)))
  expect_identical(call_of(shift_left(x, 1:2)), quote(shift_left(x, 1:2)))
  expect_identical(call_of(d + e), quote(Ops.zu_decimal128(d, e)))
  expect_identical(call_of(d < e), quote(Ops.zu_decimal128(d, e)))
  withr::with_options(
    list(zuint.double = "allow"),
    expect_identical(
      call_of(d / c(1, 2)),
      quote(Ops.zu_decimal128(d, c(1, 2)))
    )
  )
  # an invalid zuint.double option
  withr::with_options(
    list(zuint.double = "sometimes"),
    expect_identical(call_of(x + 1.5), quote(Ops.zu_int64(x, 1.5)))
  )
  # min(), max() and range() of nothing, and sum() and prod() overflowing,
  # name the generic, not the payload the method was called with
  big <- int64("9223372036854775807")
  expect_identical(call_of(min(int64())), quote(min(...)))
  expect_identical(call_of(max(int64(NA), na.rm = TRUE)), quote(max(...)))
  expect_identical(call_of(range(uint128())), quote(range(...)))
  expect_identical(call_of(sum(big, big)), quote(sum(...)))
  expect_identical(call_of(prod(big, 2L)), quote(prod(...)))
  dbig <- decimal128(strrep("9", 38), 38L, 0L)
  expect_identical(call_of(sum(dbig, dbig)), quote(sum(...)))
  expect_identical(call_of(min(d[0])), quote(min(...)))
})

test_that("a Summary condition prints without deparsing the payload (#80)", {
  skip_if_gctorture()
  x <- rep(int64("9223372036854775807"), 1e5)
  w <- tryCatch(sum(x), warning = identity)
  expect_s3_class(w, "zuint_overflow_warning")
  elapsed <- system.time(utils::capture.output(print(w)))[["elapsed"]]
  expect_lt(elapsed, 1)
})
