# Every int64 behaviour of this stage, run with bit64 attached and with bit64
# never loaded. A difference means bit64 has a method zuint lacks.
test_that("int64 behaves the same with bit64 attached and absent", {
  res <- bit64_parity("vector")
  expect_identical(res$attached, res$absent)
  # and the attached run is not vacuous
  expect_true(length(res$attached$value) > 10)
  expect_true("zuint_cast_warning" %in% res$attached$warnings)
})

test_that("int64 and bit64 integer64 mix in c() and [<-", {
  skip_if_not_installed("bit64")
  x <- c(int64(1), bit64::as.integer64("9007199254740993"))
  expect_identical(class(x), class(int64()))
  expect_identical(as.character(x), c("1", "9007199254740993"))
  x[1] <- bit64::as.integer64(-7)
  expect_identical(as.character(x), c("-7", "9007199254740993"))
})

test_that("int64 arithmetic behaves the same with bit64 attached and absent", {
  res <- bit64_parity("arithmetic")
  expect_identical(res$attached, res$absent)
  expect_identical(res$attached$value$checked, c("zuint_overflow_error", "zuint_error", "error", "condition"))
})

test_that("zu_int64 and integer64 mix exactly and without warnings", {
  skip_if_not_installed("bit64")
  big <- bit64::as.integer64("9007199254740993")
  expect_no_warning(r <- int64(1) + big)
  expect_s3_class(r, "zu_int64")
  expect_identical(as.character(r), "9007199254740994")
  expect_no_warning(r <- int64("9007199254740993") == big)
  expect_true(r)
  # bit64 >= 4.8 claims Ops through its own chooseOpsMethod(), and R asks the
  # left operand first, so integer64 on the left runs bit64's method. The
  # value is still exact.
  expect_no_warning(r <- big + int64(1))
  expect_identical(as.character(r), "9007199254740994")
})

test_that("int64 summaries and set operations behave the same with bit64 attached and absent", {
  res <- bit64_parity("summaries")
  expect_identical(res$attached, res$absent)
})

test_that("every base generic bit64 has an integer64 method for has a zu_int64 method", {
  skip_if_not_installed("bit64")
  ns <- asNamespace("bit64")
  generics <- unique(sub("[.]integer64$", "", ls(ns, pattern = "[.]integer64$", all.names = TRUE)))
  generics <- generics[vapply(generics, function(g) {
    !is.null(utils::getS3method(g, "integer64", optional = TRUE, envir = ns))
  }, logical(1))]
  covered_by_group <- c(
    # Ops
    "+", "-", "*", "/", "^", "%%", "%/%", "==", "!=", "<", "<=", ">", ">=", "&", "|", "!",
    # Math
    "abs", "sign", "sqrt", "floor", "ceiling", "trunc", "round", "signif", "log", "log2", "log10",
    "cumsum", "cumprod", "cummax", "cummin",
    # Summary
    "sum", "prod", "min", "max", "range", "any", "all",
    # as.double's methods serve as.numeric
    "as.numeric"
  )
  masked_functions <- c(
    # bit64 replaces these functions on the search path rather than adding
    # methods to a base generic; they are bit64's to define
    ":", "%in%", "match", "order", "rank", "table", "array", "matrix", "colSums", "rowSums",
    "identical", "is.double", "is.vector", "%*%"
  )
  # only the generics R itself defines: bit and bit64's own generics exist
  # only with those packages loaded, and work on int64's bits as they are
  in_r <- vapply(generics, function(g) {
    any(vapply(c("base", "stats", "utils"), function(p) exists(g, envir = asNamespace(p), inherits = FALSE), logical(1)))
  }, logical(1))
  generics <- generics[in_r]
  needed <- setdiff(generics, c(covered_by_group, masked_functions))
  missing <- needed[vapply(needed, function(g) {
    is.null(utils::getS3method(g, "zu_int64", optional = TRUE))
  }, logical(1))]
  expect_identical(missing, character())
})

test_that("the bit64-shadowed predicates and conversions agree with bit64 absent", {
  res <- bit64_parity("predicates")
  expect_identical(res$attached, res$absent)
})

test_that("a plain integer64 on the left of a wider type is exact or NA, never truncated", {
  skip_if_not_installed("bit64")
  withr::local_package("bit64")
  big <- bit64::as.integer64("9007199254740993")
  for (type in c("uint64", "int128", "uint128")) {
    ctor <- zu_ctor(type)
    expect_identical(as.character(big + ctor(0)), "9007199254740993", label = type)
    expect_true(big == ctor("9007199254740993"))
    expect_identical(as.character(c(bit64::as.integer64(1), ctor(2))), c("1", "2"))
    expect_warning(r <- bit64::as.integer64(1) + ctor("18446744073709551614"), class = "zuint_cast_warning")
    expect_true(is.na(r))
  }
})
