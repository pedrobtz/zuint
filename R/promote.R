# The promotion order (design 5). Kind 0 is R's logical and integer.
#
#   logical -> integer -> int64 ---> int128
#                     `-> uint64 -'
#                           `--------> uint128
#
# int128 and uint128 have no common type, nor do int64 and uint128.

# The common kind of two integer kinds (0 to 4), or NA when there is none.
zu_common2 <- function(a, b) {
  if (is.na(a) || is.na(b)) {
    return(NA_integer_)
  }
  if (a == b || b == 0L) {
    return(a)
  }
  if (a == 0L) {
    return(b)
  }
  lo <- min(a, b)
  hi <- max(a, b)
  if (lo == 1L && hi == 2L) {
    3L
  } else if (hi == 3L) {
    3L
  } else if (lo == 2L && hi == 4L) {
    4L
  } else {
    NA_integer_
  }
}

# The common type code of the integer kinds among `kinds` (doubles and
# strings adopt it), with an error naming both sides when there is none.
zu_common_code <- function(kinds, call = NULL) {
  ints <- kinds[kinds >= 0L]
  code <- 0L
  for (k in ints) {
    nxt <- zu_common2(code, k)
    if (is.na(nxt)) {
      zu_abort(
        sprintf(
          "%s and %s have no common type; convert one explicitly.",
          zu_types[[code]],
          zu_types[[k]]
        ),
        "incompatible",
        call = call
      )
    }
    code <- nxt
  }
  code
}

#' The common type of zuint vectors
#'
#' The type that mixing these vectors in arithmetic, comparison or `c()`
#' gives. Every step is lossless:
#'
#' | x ⊕ y | result |
#' | --- | --- |
#' | integer ⊕ int64 | int64 |
#' | integer ⊕ uint64 | uint64 |
#' | int64 ⊕ uint64 | int128 |
#' | integer, int64 or uint64 ⊕ int128 | int128 |
#' | integer or uint64 ⊕ uint128 | uint128 |
#' | int64 or int128 ⊕ uint128 | no common type: an error |
#'
#' A negative integer meeting an unsigned type is out of range, and the
#' operation's overflow policy decides what happens to it. A double takes the
#' type of the zuint operand if every value is integral and in range;
#' otherwise it is an error of class `zuint_double_error`. Setting
#' `options(zuint.double = "allow")` makes that a double result with a
#' warning of class `zuint_double_warning` instead.
#'
#' @param ... zuint vectors, and optionally logical or integer vectors.
#' @return The name of the common type: `"int64"`, `"uint64"`, `"int128"` or
#'   `"uint128"`. With no common type, an error of class
#'   `zuint_incompatible_error`.
#' @examples
#' zu_common_type(int64(1), uint64(1))
#' zu_common_type(uint64(1), 1L)
#' try(zu_common_type(int128(1), uint128(1)))
#' @export
zu_common_type <- function(...) {
  args <- list(...)
  kinds <- vapply(args, zu_kind, integer(1))
  if (anyNA(kinds) || any(kinds < 0L) || !any(kinds > 0L)) {
    zu_abort(
      "Arguments must be zuint vectors, with at most logical and integer vectors besides.",
      "type",
      call = sys.call()
    )
  }
  zu_types[[zu_common_code(kinds, call = sys.call())]]
}

zu_double_policy <- function() {
  opt <- getOption("zuint.double", "error")
  if (!identical(opt, "allow") && !identical(opt, "error")) {
    zu_abort('`options(zuint.double)` must be "error" or "allow".', "type")
  }
  opt
}
