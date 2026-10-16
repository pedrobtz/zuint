#' Hexadecimal and binary text
#'
#' `format_hex()` and `format_bin()` write each value with a `0x` or `0b`
#' prefix. A negative value is written as a sign and a magnitude, `-0x1`,
#' not as two's complement, so the constructors read every string back as
#' the same value. (The two's complement pattern of a negative value would
#' not do: the one for -1, `0xffffffffffffffff`, is `uint64`'s `NA`.) `NA`
#' gives `NA_character_`.
#'
#' The constructors read the same forms: decimal, `0x` hex or `0b` binary
#' digits, an optional sign, `_` between digits, and surrounding whitespace.
#' Exponents and fractions are not accepted.
#'
#' @param x A zuint vector.
#' @param pad If `TRUE`, write every digit of the type's width (16 or 32 hex
#'   digits, 64 or 128 binary digits), as for hashes.
#' @return A character vector the length of `x`, with its names.
#' @examples
#' format_hex(uint64("18446744073709551614"))
#' format_hex(int64(c(255, -255, NA)))
#' format_hex(uint64(255), pad = TRUE)
#' format_bin(int128(5))
#' uint64("0xffff_ffff")
#' @export
format_hex <- function(x, pad = FALSE) zu_format_base(x, 16L, pad, sys.call())

#' @rdname format_hex
#' @export
format_bin <- function(x, pad = FALSE) zu_format_base(x, 2L, pad, sys.call())

zu_format_base <- function(x, base, pad, call) {
  code <- zu_code(x)
  if (is.na(code)) {
    zu_abort("`x` must be a zuint vector.", "type", call = call)
  }
  if (!isTRUE(pad) && !isFALSE(pad)) {
    zu_abort("`pad` must be TRUE or FALSE.", "type", call = call)
  }
  out <- .Call(zu_format_base_c, x, code, base, pad)
  names(out) <- names(x)
  out
}
