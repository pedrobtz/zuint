# Extracted from test-conditions.R:36

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "zuint", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
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

# test -------------------------------------------------------------------------
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
