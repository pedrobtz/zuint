# Bit operations (design 6). Codes match zu_bitop and zu_bitcount in
# src/zu_bits.c.

#' Bit operations
#'
#' Bitwise operations on the two's complement bits of each type's full
#' width: 64 bits for `int64` and `uint64`, 128 for `int128` and `uint128`.
#'
#' `bit_and()`, `bit_or()` and `bit_xor()` take their operands to the common
#' type first (see [zu_common_type()]). `shift_left()` discards the bits it
#' shifts out; `shift_right()` fills with zeros for the unsigned types and
#' with the sign bit for the signed ones, so it rounds towards negative
#' infinity. A shift by a negative amount, or by the width or more, is `NA`.
#'
#' A result whose bits are the type's `NA` pattern (for example
#' `bit_not(int64("9223372036854775807"))`) is out of range: `NA` with a
#' warning of class `zuint_overflow_warning`, as in arithmetic.
#'
#' `popcount()` counts the set bits, `clz()` the leading zeros and `ctz()`
#' the trailing zeros, all of the full width; `clz()` and `ctz()` of zero are
#' the width.
#'
#' @param x,y zuint vectors, or a zuint vector and an integer vector.
#' @param n Shift amounts: an integer vector, or anything that converts to
#'   one exactly. Recycled against `x`.
#' @return `bit_*()` and `shift_*()` return a zuint vector; `popcount()`,
#'   `clz()` and `ctz()` an integer vector.
#' @examples
#' x <- uint64("0xff00")
#' format_hex(bit_and(x, uint64("0x0ff0")))
#' format_hex(shift_left(x, 8L))
#' shift_right(int64(-16), 2L)
#' popcount(uint128("0xffffffffffffffffffff"))
#' clz(uint64(1))
#' ctz(int128(0))
#' @name zuint-bits
NULL

zu_bit_binary <- function(op, x, y, call) {
  kinds <- c(zu_kind(x), zu_kind(y))
  zu_check_operands(kinds, list(x, y), call)
  if (any(kinds == zu_kind_dbl)) {
    zu_abort("Bit operations take integer operands, not doubles.", "type", call = call)
  }
  zu_check_recycling(x, y)
  code <- zu_common_code(kinds, call)
  cx <- zu_convert(x, kinds[[1L]], code)
  cy <- zu_convert(y, kinds[[2L]], code)
  zu_warn_lost(cx[[2L]] + cy[[2L]], zu_types[[code]], call = call)
  res <- .Call(zu_bitop_c, op, cx[[1L]], cy[[1L]], code)
  zu_bit_result(res, code, zu_result_names(x, y, length(res[[1L]])), call)
}

zu_bit_result <- function(res, code, nm, call) {
  zu_report_overflow(res[[2L]], zu_policy_default, call)
  out <- res[[1L]]
  names(out) <- nm
  zu_new(out, code)
}

zu_bit_shift <- function(op, x, n, call) {
  zu_check_operands(zu_kind(x), list(x), call)
  zu_check_recycling(x, n)
  code <- zu_code(x)
  if (!is.integer(n)) {
    n <- zu_as_integer(int64(n))
  }
  res <- .Call(zu_bitop_c, op, zu_bare(x), zu_bare(n), code)
  zu_bit_result(res, code, zu_result_names(x, n, length(res[[1L]])), call)
}

zu_bit_count <- function(what, x, call) {
  zu_check_operands(zu_kind(x), list(x), call)
  out <- .Call(zu_bitcount_c, zu_bare(x), zu_code(x), what)
  names(out) <- names(x)
  out
}

#' @rdname zuint-bits
#' @export
bit_and <- function(x, y) zu_bit_binary(1L, x, y, sys.call())

#' @rdname zuint-bits
#' @export
bit_or <- function(x, y) zu_bit_binary(2L, x, y, sys.call())

#' @rdname zuint-bits
#' @export
bit_xor <- function(x, y) zu_bit_binary(3L, x, y, sys.call())

#' @rdname zuint-bits
#' @export
bit_not <- function(x) {
  call <- sys.call()
  zu_check_operands(zu_kind(x), list(x), call)
  code <- zu_code(x)
  zu_bit_result(.Call(zu_bitop_c, 4L, zu_bare(x), NULL, code), code, names(x), call)
}

#' @rdname zuint-bits
#' @export
shift_left <- function(x, n) zu_bit_shift(5L, x, n, sys.call())

#' @rdname zuint-bits
#' @export
shift_right <- function(x, n) zu_bit_shift(6L, x, n, sys.call())

#' @rdname zuint-bits
#' @export
popcount <- function(x) zu_bit_count(1L, x, sys.call())

#' @rdname zuint-bits
#' @export
clz <- function(x) zu_bit_count(2L, x, sys.call())

#' @rdname zuint-bits
#' @export
ctz <- function(x) zu_bit_count(3L, x, sys.call())
