# The four types. Codes match zu_type in src/zu_wide.h.
zu_types <- c("int64", "uint64", "int128", "uint128")

zu_classes <- list(
  int64 = c("zu_int64", "integer64"),
  uint64 = "zu_uint64",
  int128 = "zu_int128",
  uint128 = "zu_uint128"
)

# The type code of a zuint vector, or NA. A bare bit64 integer64 reads as
# int64: same layout, only the class differs.
zu_code <- function(x) {
  cl <- oldClass(x)
  if (is.null(cl)) {
    return(NA_integer_)
  }
  code <- match(cl[[1L]], c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128"))
  if (is.na(code) && inherits(x, "integer64")) 1L else code
}

zu_type_code <- function(type) {
  code <- match(type, zu_types)
  if (length(type) != 1L || is.na(code)) {
    zu_abort(
      sprintf(
        "`type` must be one of %s.",
        paste0('"', zu_types, '"', collapse = ", ")
      ),
      "type",
      call = sys.call(-1L)
    )
  }
  code
}

# A payload with the class of type `code`; other attributes are kept.
zu_new <- function(payload, code) {
  oldClass(payload) <- zu_classes[[code]]
  payload
}

#' Wide integer vectors
#'
#' Create signed and unsigned 64-bit and 128-bit integer vectors, or convert
#' to them. Conversion is exact or gives `NA` with a warning of class
#' `zuint_cast_warning`; it never rounds or clamps.
#'
#' `x` can be a logical, integer, double or character vector, another zuint
#' vector, or a bit64 `integer64`. A double must be integral and in range.
#' A string is decimal, `0x` hex or `0b` binary digits, with an optional
#' sign, `_` between digits and surrounding whitespace (see [format_hex()]);
#' `"NA"` and blank strings are `NA`. `NA` stays `NA` without a warning.
#' Names are kept.
#'
#' Each type reserves one bit pattern for `NA`, so its range is one value
#' short of the full width: the most negative value for the signed types and
#' the largest for the unsigned ones.
#'
#' | Type | Range |
#' | --- | --- |
#' | `int64` | \eqn{\pm(2^{63} - 1)} |
#' | `uint64` | \eqn{[0, 2^{64} - 2]} |
#' | `int128` | \eqn{\pm(2^{127} - 1)} |
#' | `uint128` | \eqn{[0, 2^{128} - 2]} |
#'
#' `int64` has class `c("zu_int64", "integer64")` and the storage of bit64's
#' `integer64`, so code that reads `integer64` reads it too.
#'
#' @param x A vector to convert.
#' @return A vector of the requested type, the same length as `x`.
#' @examples
#' int64("9007199254740993")
#' uint64(c(0, 2^53))
#' int128("-170141183460469231731687303715884105727")
#' uint128(NA)
#'
#' # Not exact, so NA with a warning:
#' int64(1.5)
#' @name zuint-types
NULL

#' @rdname zuint-types
#' @export
int64 <- function(x = integer()) zu_cast(x, 1L)

#' @rdname zuint-types
#' @export
uint64 <- function(x = integer()) zu_cast(x, 2L)

#' @rdname zuint-types
#' @export
int128 <- function(x = integer()) zu_cast(x, 3L)

#' @rdname zuint-types
#' @export
uint128 <- function(x = integer()) zu_cast(x, 4L)

#' Missing values of each type
#'
#' The `NA` of each zuint type, a vector of length one.
#'
#' @format A zuint vector of length 1.
#' @examples
#' is.na(NA_int64_)
#' c(int64(1), NA_int64_)
#' @name zuint-na
#' @aliases NA_int64_ NA_uint64_ NA_int128_ NA_uint128_
NULL

# Built from bit patterns at install time, since the C code is not loaded
# yet: INT64_MIN is the bits of -0.0, the unsigned NAs are all ones, and
# INT128_MIN has a zero low word and a high word of 0x8000000000000000.
zu_all_ones <- readBin(as.raw(rep(0xff, 8L)), "double")

#' @rdname zuint-na
#' @export
NA_int64_ <- zu_new(-0, 1L)

#' @rdname zuint-na
#' @export
NA_uint64_ <- zu_new(zu_all_ones, 2L)

#' @rdname zuint-na
#' @export
NA_int128_ <- zu_new(complex(real = 0, imaginary = -0), 3L)

#' @rdname zuint-na
#' @export
NA_uint128_ <- zu_new(complex(real = zu_all_ones, imaginary = zu_all_ones), 4L)

#' Raw storage of a zuint vector
#'
#' `zu_storage()` returns the payload a zuint vector is stored in, for code
#' that reads the bits directly: a double vector whose bits are 64-bit
#' integers for `int64` and `uint64`, and a complex vector whose real and
#' imaginary parts hold the low and high 64-bit words for `int128` and
#' `uint128`. `zu_from_storage()` reverses it. Names are kept both ways.
#'
#' The payload is not a number: printing it or computing with it is
#' meaningless. Keeping the representation behind these two functions is
#' what lets it change without breaking callers.
#'
#' @param x A zuint vector.
#' @param payload A double or complex vector, as returned by `zu_storage()`.
#' @param type One of `"int64"`, `"uint64"`, `"int128"` or `"uint128"`.
#' @return `zu_storage()` returns a double or complex vector;
#'   `zu_from_storage()` a zuint vector of `type`.
#' @examples
#' p <- zu_storage(int128(-1))
#' p
#' zu_from_storage(p, "int128")
#' @export
zu_storage <- function(x) {
  code <- zu_code(x)
  if (is.na(code)) {
    zu_abort("`x` must be a zuint vector.", "type", call = sys.call())
  }
  attributes(x) <- if (is.null(names(x))) NULL else list(names = names(x))
  x
}

#' @rdname zu_storage
#' @export
zu_from_storage <- function(payload, type) {
  code <- zu_type_code(type)
  want <- if (code <= 2L) "double" else "complex"
  if (typeof(payload) != want || is.object(payload)) {
    zu_abort(
      sprintf("`payload` for %s must be a bare %s vector.", type, want),
      "type",
      call = sys.call()
    )
  }
  attributes(payload) <- if (is.null(names(payload))) {
    NULL
  } else {
    list(names = names(payload))
  }
  zu_new(payload, code)
}
