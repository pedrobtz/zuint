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
