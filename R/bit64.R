# Methods that keep a zuint vector's answer the same whether or not bit64 is
# loaded (design 4.1): every base generic bit64 defines for integer64 needs
# one here, or zu_int64 falls through to bit64's method when it is loaded
# and to base R on the raw bits when it is not. test-bit64-parity.R diffs
# bit64's list against these.

zu_is_numeric <- function(x) TRUE

zu_is_nan <- function(x) {
  out <- logical(length(x))
  names(out) <- names(x)
  out
}

zu_is_finite <- function(x) !zu_is_na(x)

zu_is_infinite <- zu_is_nan

# Through the doubles, so an NA is base's as.complex(NA_real_) on every R:
# assigning a logical NA gave an NA imaginary part before R 4.4.
zu_as_complex <- function(x, ...) as.complex(zu_as_double(x))

zu_as_raw <- function(x) as.raw(zu_as_integer(x))

zu_as_date <- function(x, ...) as.Date(zu_as_double(x), ...)

zu_as_posixct <- function(x, tz = "", ...) {
  as.POSIXct(zu_as_double(x), tz = tz, ...)
}

zu_as_posixlt <- function(x, tz = "", ...) {
  as.POSIXlt(zu_as_double(x), tz = tz, ...)
}

# seq() on a zuint `from`: seq_zu(), with along.with as base seq() has it.
zu_seq <- function(
  from,
  to = NULL,
  by = NULL,
  length.out = NULL,
  along.with = NULL,
  ...
) {
  if (!is.null(along.with)) {
    length.out <- length(along.with)
  }
  if (is.null(by)) {
    if (!is.null(to) && !is.null(length.out)) {
      zu_abort(
        "seq() with `to` and `length.out` needs a step that may not be whole; give `by`.",
        "unsupported",
        call = sys.call()
      )
    }
    by <- 1L
  }
  seq_zu(from, to, by = by, length.out = length.out)
}

# Exact: the same type and the same values (and names), or a description of
# how they differ. Tolerances mean nothing for integers.
zu_all_equal <- function(target, current, ...) {
  if (is.na(zu_code(current))) {
    return(sprintf(
      "target is %s, current is %s",
      zu_type_name(target),
      zu_kind_label(current)
    ))
  }
  if (zu_code(current) != zu_code(target)) {
    return(sprintf(
      "Types differ: %s vs %s",
      zu_type_name(target),
      zu_type_name(current)
    ))
  }
  if (length(target) != length(current)) {
    return(sprintf("Lengths (%d, %d) differ", length(target), length(current)))
  }
  msg <- character()
  if (!identical(names(target), names(current))) {
    msg <- "names differ"
  }
  differ <- sum(
    xor(zu_is_na(target), zu_is_na(current)) |
      (!is.na(target == current) & !(target == current))
  )
  if (differ > 0) {
    msg <- c(msg, sprintf("%d of %d values differ", differ, length(target)))
  }
  if (length(msg)) msg else TRUE
}

# What 0.1.0 does not do: quantiles (after 0.1.0) and matrices (a
# non-goal). An error rather than an answer computed on the raw bits.
zu_unsupported <- function(x, ...) {
  zu_abort(
    sprintf("%s() is not supported for zuint vectors.", .Generic),
    "unsupported",
    call = sys.call()
  )
}

zu_quantile <- function(x, ...) {
  zu_abort(
    "quantile() for zuint vectors comes after zuint 0.1.0.",
    "unsupported",
    call = sys.call()
  )
}

zu_matrix_unsupported <- function(...) {
  zu_abort(
    "zuint vectors do not form matrices.",
    "unsupported",
    call = sys.call()
  )
}

# bit64's as.integer64() for the wider types, registered when bit64 loads.
# bit64 calls it when an integer64 is on the left of one of them, then
# computes in int64: exact, or NA with a warning, never truncated.
# A decimal refuses: bit64 would compute `integer64 * decimal` on the
# integers, making every fraction NA, and keep the decimal's attributes.
#
# bit64's `*`, `/`, `^`, `[<-` and `[[<-` ask its is.double() generic
# first, and use the operand's bits as a double when it says TRUE, which
# base's does for a uint64 (#151). int64 inherits is.double.integer64(),
# and the other types are complex, so uint64 is the one that needs it.
zu_register_bit64 <- function(...) {
  ns <- asNamespace("bit64")
  for (cl in c("zu_uint64", "zu_int128", "zu_uint128")) {
    registerS3method("as.integer64", cl, zu_as_integer64_method, envir = ns)
  }
  registerS3method(
    "as.integer64",
    "zu_decimal128",
    dec_as_integer64_method,
    envir = ns
  )
  # only when bit64 masks base's is.double() with a generic of its own
  if (exists("is.double", envir = ns, inherits = FALSE)) {
    registerS3method("is.double", "zu_uint64", zu_is_double_method, envir = ns)
  }
}

zu_is_double_method <- function(x) FALSE

# bit64 masks setdiff(), union(), intersect(), is.element() and setequal(),
# and they call methods::as(x, "integer64"), which needs zu_int64 declared
# as a subclass of integer64 (#161). bit64's own integer64 class is
# unchanged by it.
setOldClass(c("zu_int64", "integer64"))

zu_as_integer64_method <- function(x, ...) as_integer64(x)

dec_as_integer64_method <- function(x, ...) {
  zu_abort(
    paste(
      "bit64 can't compute with a decimal128.",
      "Put the decimal128 first in the operation, or convert it with as_integer64() or int64()."
    ),
    "incompatible",
    call = sys.call(-1L)
  )
}

#' Convert to bit64's integer64
#'
#' `as_integer64()` returns the values as a plain bit64 `integer64`, for
#' code that checks the class exactly. `int64` already has bit64's storage,
#' so for it only the class changes; the other types convert first, exactly
#' or to `NA` with a warning of class `zuint_cast_warning`. bit64 itself is
#' not needed.
#'
#' The other direction is [int64()], which on an `integer64` likewise only
#' swaps the class.
#'
#' @param x A zuint vector or a bit64 `integer64`.
#' @return An `integer64` vector the length of `x`, with its names.
#' @examples
#' y <- as_integer64(int64("9007199254740993"))
#' class(y)
#' int64(y)
#' @export
as_integer64 <- function(x) {
  x <- zu_cast(x, 1L, call = sys.call())
  oldClass(x) <- "integer64"
  x
}
