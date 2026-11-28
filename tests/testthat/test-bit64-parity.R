# Every int64 behaviour of this stage, run with bit64 attached and with bit64
# never loaded. A difference means bit64 has a method zuint lacks.
test_that("int64 behaves the same with bit64 attached and absent", {
  res <- expect_bit64_parity("vector")
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
  res <- expect_bit64_parity("arithmetic")
  expect_identical(
    res$attached$value$checked,
    c("zuint_overflow_error", "zuint_error", "error", "condition")
  )
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
  expect_bit64_parity("summaries")
})

test_that("decimal128 behaves the same with bit64 attached and absent", {
  res <- expect_bit64_parity("decimal")
  # and the attached run is not vacuous: int64 operands took DECIMAL(19, 0)
  expect_identical(res$attached$value$add[[1L]], "9223372036854775794.66")
  expect_true(length(res$attached$value) > 20)
})

test_that("every base generic bit64 has an integer64 method for has a zu_int64 method", {
  skip_if_not_installed("bit64")
  ns <- asNamespace("bit64")
  generics <- unique(sub(
    "[.]integer64$",
    "",
    ls(ns, pattern = "[.]integer64$", all.names = TRUE)
  ))
  generics <- generics[vapply(
    generics,
    function(g) {
      !is.null(utils::getS3method(g, "integer64", optional = TRUE, envir = ns))
    },
    logical(1)
  )]
  covered_by_group <- c(
    # Ops
    "+",
    "-",
    "*",
    "/",
    "^",
    "%%",
    "%/%",
    "==",
    "!=",
    "<",
    "<=",
    ">",
    ">=",
    "&",
    "|",
    "!",
    # Math
    "abs",
    "sign",
    "sqrt",
    "floor",
    "ceiling",
    "trunc",
    "round",
    "signif",
    "log",
    "log2",
    "log10",
    "cumsum",
    "cumprod",
    "cummax",
    "cummin",
    # Summary
    "sum",
    "prod",
    "min",
    "max",
    "range",
    "any",
    "all",
    # as.double's methods serve as.numeric
    "as.numeric"
  )
  masked_functions <- c(
    # bit64 replaces these functions on the search path rather than adding
    # methods to a base generic; they are bit64's to define
    ":",
    "%in%",
    "match",
    "order",
    "rank",
    "table",
    "array",
    "matrix",
    "colSums",
    "rowSums",
    "identical",
    "is.double",
    "is.vector",
    "%*%"
  )
  # only the generics R itself defines: bit and bit64's own generics exist
  # only with those packages loaded, and work on int64's bits as they are
  in_r <- vapply(
    generics,
    function(g) {
      any(vapply(
        c("base", "stats", "utils"),
        function(p) exists(g, envir = asNamespace(p), inherits = FALSE),
        logical(1)
      ))
    },
    logical(1)
  )
  generics <- generics[in_r]
  needed <- setdiff(generics, c(covered_by_group, masked_functions))
  missing <- needed[vapply(
    needed,
    function(g) {
      is.null(utils::getS3method(g, "zu_int64", optional = TRUE))
    },
    logical(1)
  )]
  expect_identical(missing, character())
})

test_that("the bit64-shadowed predicates and conversions agree with bit64 absent", {
  expect_bit64_parity("predicates")
})

test_that("a plain integer64 on the left of a wider type is exact or NA, never truncated", {
  skip_if_not_installed("bit64")
  withr::local_package("bit64")
  big <- bit64::as.integer64("9007199254740993")
  for (type in c("uint64", "int128", "uint128")) {
    ctor <- zu_ctor(type)
    expect_identical(
      as.character(big + ctor(0)),
      "9007199254740993",
      label = type
    )
    expect_true(big == ctor("9007199254740993"), label = type)
    expect_identical(
      as.character(c(bit64::as.integer64(1), ctor(2))),
      c("1", "2"),
      label = type
    )
    expect_warning(
      r <- bit64::as.integer64(1) + ctor("18446744073709551614"),
      class = "zuint_cast_warning"
    )
    expect_identical(r, bit64::NA_integer64_, label = type)
  }
})

test_that("a plain integer64 operand reads as its values with bit64 absent (#150)", {
  res <- expect_bit64_parity("operands")
  v <- res$absent$value
  expect_identical(v$and, c(TRUE, FALSE, NA))
  expect_identical(v$or, c(TRUE, FALSE, NA))
  expect_identical(v$xor, c(FALSE, TRUE, NA))
  expect_identical(v$match, c(2L, 1L, NA))
  expect_identical(v$match_table, c(3L, 2L, 1L))
  expect_identical(v$zin, c(TRUE, FALSE, FALSE))
  expect_identical(v$ifelse, zu_storage(int64(c(1, 2, NA, 1))))
  expect_identical(v$idiv, zu_storage(int64(c(NA, -5))))
  expect_identical(v$seq_by, zu_storage(int64(c(1, 0, -1))))
  expect_identical(v$seq_len, zu_storage(int64(1:3)))
  expect_identical(v$round, zu_storage(int64(1200)))
  expect_identical(v$dec_cmp, c(NA, TRUE, FALSE))
  expect_identical(v$dec_lt, c(NA, TRUE, TRUE))
  expect_identical(v$dec_match, c(2L, 1L))
  expect_identical(v$dec_and, c(FALSE, FALSE, NA))
  expect_identical(v$dec_ifelse, c("0.00", "-1.00", NA))
  expect_identical(res$absent$warnings, character())
})

test_that("vctrs casts a plain integer64 by its values with bit64 absent (#150)", {
  skip_if_not_installed("vctrs")
  res <- expect_bit64_parity("operands_vctrs")
  v <- res$absent$value
  expect_identical(v$int64, zu_storage(int64(c(1, NA, -1))))
  expect_identical(v$uint64, "lossy")
  expect_identical(v$uint64_ok, zu_storage(uint64(c(1, NA))))
  expect_identical(v$int128, zu_storage(int128(c(-1, NA))))
  expect_identical(v$decimal, c("1.00", NA, "-1.00"))
  expect_identical(v$decimal_lossy, "lossy")
  expect_identical(v$combine, zu_storage(int64(c(5, NA, -1))))
})

test_that("bit64's masked set functions work on int64 (#161)", {
  res <- expect_bit64_parity("sets")
  v <- res$attached$value
  expect_identical(
    v$setdiff,
    zu_storage(int64(c("-2", "0", "9007199254740993")))
  )
  expect_identical(
    v$union,
    zu_storage(int64(c(
      "-2",
      "-1",
      "0",
      "9007199254740993",
      NA,
      "9007199254740992"
    )))
  )
  expect_identical(v$intersect, zu_storage(int64(c("-1", NA))))
  expect_identical(v$is_element, c(FALSE, TRUE, FALSE, FALSE, TRUE))
  expect_identical(v$setequal, c(TRUE, FALSE))
})

test_that("integer64 with any zuint type on the right is exact with bit64 attached (#151)", {
  skip_if_not_installed("bit64")
  skip_if_not_installed("gmp")
  withr::local_package("bit64")
  a <- c("-9007199254740993", "-2", "3", "7", NA)
  b <- c("1", "5", "2", "3", "4")
  ga <- gmp::as.bigz(a)
  gb <- gmp::as.bigz(b)
  x <- bit64::as.integer64(a)
  for (type in zu_all_types) {
    y <- zu_ctor(type)(b)
    for (op in c("+", "-", "*", "%/%", "%%")) {
      expect_identical(
        as.character(get(op)(x, y)),
        oracle_chr(oracle_op(op, ga, gb)),
        label = paste(type, op)
      )
    }
    expect_identical(
      as.character(x^y),
      oracle_chr(ga^as.integer(b)),
      label = paste(type, "^")
    )
    expect_equal(
      x / y,
      as.numeric(gmp::as.bigq(ga) / gmp::as.bigq(gb)),
      label = paste(type, "/")
    )
    expect_identical(x < y, c(TRUE, TRUE, FALSE, FALSE, NA), label = type)
  }
  # bit64's [<- asks is.double() too: a uint64 is assigned by its value
  z <- x
  z[2] <- uint64(5)
  z[[3]] <- uint64("9007199254740993")
  expect_identical(
    as.character(z),
    c("-9007199254740993", "5", "9007199254740993", "7", NA)
  )
})
