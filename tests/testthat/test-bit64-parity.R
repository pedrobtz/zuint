# Every int64 behaviour of this stage, run with bit64 attached and with bit64
# never loaded. A difference means bit64 has a method zuint lacks.
test_that("int64 behaves the same with bit64 attached and absent", {
  parity_code <- '
x <- int64(c(a = "-9223372036854775807", b = "-1", c = "0", d = "9007199254740993", e = NA))
y <- x
y[7] <- 5L
y[["b"]] <- "12"
z <- x
length(z) <- 6
is.na(z) <- 1
list(
  chr = as.character(x),
  storage = zu_storage(x),
  subset = zu_storage(x[c(2, 9, NA)]),
  sub2 = zu_storage(x[[4]]),
  assign = zu_storage(y),
  len = zu_storage(z),
  c = zu_storage(c(x, 1L, "2", NA)),
  rep = zu_storage(rep(x, 2)),
  rev = zu_storage(rev(x)),
  is_na = is.na(x),
  any_na = anyNA(x),
  dbl = suppressWarnings(as.double(x)),
  int = suppressWarnings(as.integer(x)),
  lgl = as.logical(x),
  list = lapply(as.list(x), zu_storage),
  format = format(x),
  print = capture.output(print(x)),
  str = capture.output(str(x)),
  summary = summary(x),
  df = capture.output(print(data.frame(v = x))),
  cast = zu_storage(int64(c(1.5, 2, NA))),
  uint = zu_storage(uint64(x)),
  wide = zu_storage(int128(x))
)
'
  res <- bit64_states(parity_code)
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
  parity_code <- '
x <- int64(c("-9223372036854775807", "-3", "0", "7", "9007199254740993", NA))
y <- int64(c("2", "-2", "5", "0", "3", "1"))
list(
  add = zu_storage(suppressWarnings(x + y)),
  sub = zu_storage(suppressWarnings(x - y)),
  mul = zu_storage(suppressWarnings(x * y)),
  idiv = zu_storage(x %/% y),
  mod = zu_storage(x %% y),
  pow = zu_storage(suppressWarnings(int64(3)^40L)),
  neg = zu_storage(-x),
  abs = zu_storage(abs(x)),
  sign = zu_storage(sign(x)),
  div = x / y,
  cmp = list(x == y, x < y, x >= 1.5, x == 9007199254740992),
  int = zu_storage(x + 1L),
  dbl = zu_storage(x + 2),
  mixed = zu_storage(x + uint64(1)),
  checked = tryCatch(checked_add(x, x), error = function(e) class(e)),
  wrapping = zu_storage(wrapping_mul(x, y)),
  not = !x
)
'
  res <- bit64_states(parity_code)
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
  parity_code <- '
x <- int64(c("9007199254740993", "-3", NA, "9007199254740992", "-3", "0"))
list(
  sum = zu_storage(sum(x, na.rm = TRUE)),
  prod = zu_storage(prod(int64(c(2, -3)))),
  minmax = lapply(list(min(x, na.rm = TRUE), max(x, na.rm = TRUE), range(x, na.rm = TRUE)), zu_storage),
  mean = mean(x, na.rm = TRUE),
  median = median(x, na.rm = TRUE),
  sort = zu_storage(sort(x)),
  sort_desc = zu_storage(sort(x, decreasing = TRUE, na.last = TRUE)),
  xtfrm = xtfrm(x),
  unique = zu_storage(unique(x)),
  duplicated = duplicated(x),
  any_dup = anyDuplicated(x),
  cumsum = zu_storage(cumsum(int64(1:4))),
  cummax = zu_storage(cummax(int64(c(3, 1, 5)))),
  diff = zu_storage(diff(int64(c(1, 4, 9)))),
  summary = summary(x)
)
'
  res <- bit64_states(parity_code)
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
  parity_code <- '
x <- int64(c("-1", NA, "5", "9007199254740993"))
list(
  is_nan = is.nan(x), is_finite = is.finite(x), is_infinite = is.infinite(x),
  is_numeric = is.numeric(x), complex = suppressWarnings(as.complex(x[1:3])),
  raw = suppressWarnings(as.raw(x[c(1, 3)])), seq = zu_storage(seq(int64(1), int64(5))),
  all_equal = all.equal(x, x), date = as.Date(int64(1))
)
'
  res <- bit64_states(parity_code)
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
