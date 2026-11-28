# The C entry points' argument guards (#65). The R layer never passes these
# arguments, so each is reached by calling the routine directly. They are
# internal errors, plain simpleErrors, so the class asserted is that one; the
# point is that the guard fires instead of reading the bad argument.
# Unreachable here, with the reason next to the code: out of memory (the
# alloc-failure workflow), and zu_hash.c's table of 2^31 values.

test_that("arithmetic and comparison refuse a bad operator, policy or operand", {
  x <- zu_bare(int64(1))
  arith <- function(op = 1L, kx = 1L, ky = 1L, y = x, policy = 0L) {
    .Call(zu_arith_c, op, x, kx, y, ky, 1L, policy)
  }
  expect_identical(zu_new(arith()[[1L]], 1L), int64(2))
  expect_error(arith(op = 0L), class = "simpleError")
  expect_error(arith(op = 6L), class = "simpleError")
  expect_error(arith(policy = 3L), class = "simpleError")
  expect_error(arith(ky = 0L, y = 1.5), class = "simpleError") # not integer
  expect_error(arith(ky = 2L), class = "simpleError") # kind != type
  expect_error(arith(ky = 1L, y = 1L), class = "simpleError") # payload
  cmp <- function(op = 1L, kx = 1L, y = x, ky = 1L) {
    .Call(zu_compare_c, op, x, kx, y, ky)
  }
  expect_true(cmp())
  expect_error(cmp(op = 0L), class = "simpleError")
  expect_error(cmp(op = 7L), class = "simpleError")
  expect_error(cmp(y = 1L, ky = -1L), class = "simpleError") # not double
  expect_error(cmp(y = 1.5, ky = 0L), class = "simpleError") # not integer
  expect_error(cmp(ky = 9L), class = "simpleError") # bad kind
})

test_that("casts, NA masks, bit operations and formatting refuse bad arguments", {
  expect_error(.Call(zu_cast_c, 1.5, 0L, 1L), class = "simpleError")
  expect_error(.Call(zu_cast_c, 1L, -1L, 1L), class = "simpleError")
  expect_error(.Call(zu_cast_c, 1L, -2L, 1L), class = "simpleError")
  p <- zu_bare(int64(1:2))
  expect_error(.Call(zu_fill_na_c, p, 1L, TRUE), class = "simpleError")
  expect_error(.Call(zu_fill_na_c, p, 1L, c(1L, 0L)), class = "simpleError")
  expect_error(.Call(zu_bitop_c, 5L, p, 1.5, 1L), class = "simpleError")
  expect_error(.Call(zu_bitop_c, 0L, p, p, 1L), class = "simpleError")
  expect_error(.Call(zu_bitop_c, 7L, p, p, 1L), class = "simpleError")
  expect_error(.Call(zu_format_base_c, p, 1L, 8L, FALSE), class = "simpleError")
  expect_identical(.Call(zu_format_base_c, p, 1L, 16L, FALSE), c("0x1", "0x2"))
})

test_that("every routine refuses a bad type code or a payload of the wrong type", {
  p <- zu_bare(int64(1))
  expect_error(.Call(zu_to_double_c, p, 0L), class = "simpleError")
  expect_error(.Call(zu_to_double_c, p, 5L), class = "simpleError")
  # an int128 payload is a complex vector, not a double
  expect_error(.Call(zu_to_double_c, p, 3L), class = "simpleError")
  expect_error(.Call(zu_to_double_c, 1L, 1L), class = "simpleError")
})

test_that("the Arrow import refuses a malformed array as a zuint_arrow_error", {
  to <- zu_arrow_to(NA_integer_)
  # 6 and 7: an offset past what the index or byte arithmetic can hold (#81)
  for (what in c(1:4, 6:7)) {
    a <- zu_arrow_from(int64(c(1, 2)))
    .Call(zu_arrow_corrupt_c, a, what)
    expect_error(to(a, zu_arrow_tag(a), "error"), class = "zuint_arrow_error")
  }
  for (what in 6:7) {
    a <- zu_arrow_from(uint128(c(1, 2)))
    .Call(zu_arrow_corrupt_c, a, what)
    expect_error(to(a, zu_arrow_tag(a), "error"), class = "zuint_arrow_error")
  }
  # an empty array needs no data buffer
  a <- zu_arrow_from(int64())
  .Call(zu_arrow_corrupt_c, a, 4L)
  expect_identical(to(a, zu_arrow_tag(a), "error"), int64())
  expect_error(.Call(zu_metadata_get_c, "x", "k"), class = "simpleError")
  expect_error(.Call(zu_arrow_schema_c, 1L), class = "simpleError")
  expect_error(.Call(zu_from_arrow_c, 1L, 1L), class = "simpleError")
})

test_that("the fixed-point entry points refuse bad arguments (#119)", {
  p <- zu_bare(int128(1:2))
  expect_identical(.Call(zu_dec_format_c, p, 5L, 2L), c("0.01", "0.02"))
  # a payload that is not complex, text that is not character, a non-double
  expect_error(.Call(zu_dec_format_c, 1, 5L, 2L), class = "simpleError")
  expect_error(.Call(zu_dec_rescale_c, 1L, 0L, 5L, 2L), class = "simpleError")
  expect_error(.Call(zu_dec_parse_c, 1, 5L, 2L), class = "simpleError")
  expect_error(.Call(zu_dec_from_double_c, 1L, 5L, 2L), class = "simpleError")
  # a type or scale out of range
  expect_error(.Call(zu_dec_format_c, p, 39L, 2L), class = "simpleError")
  expect_error(.Call(zu_dec_format_c, p, 5L, 6L), class = "simpleError")
  expect_error(
    .Call(zu_dec_format_c, p, NA_integer_, 2L),
    class = "simpleError"
  )
  expect_error(.Call(zu_dec_compare_c, p, -1L, p, 0L), class = "simpleError")
  expect_error(.Call(zu_dec_compare_c, p, 0L, p, 39L), class = "simpleError")
  # lengths that differ, an operator code out of range
  expect_error(.Call(zu_dec_compare_c, p, 0L, p[1], 0L), class = "simpleError")
  expect_error(.Call(zu_dec_arith_c, 1L, p, p[1]), class = "simpleError")
  expect_error(.Call(zu_dec_arith_c, 0L, p, p), class = "simpleError")
  expect_error(.Call(zu_dec_arith_c, 4L, p, p), class = "simpleError")
  expect_identical(.Call(zu_api_version_c, -1L), FALSE)
  expect_identical(.Call(zu_api_version_c, NA_integer_), FALSE)
})
