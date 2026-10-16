#' Conditions zuint signals
#'
#' Every error and warning zuint raises has a class, which is part of its
#' interface and safe to test for; the message text is not. Each also has the
#' class `zuint_error` or `zuint_warning`.
#'
#' Errors:
#'
#' * `zuint_type_error`: an argument of the wrong kind.
#' * `zuint_incompatible_error`: two types with no common type, such as
#'   `int128` and `uint128` (see [zu_common_type()]).
#' * `zuint_double_error`: a double that is not integral or not in range, in
#'   arithmetic, comparison-free mixing or `c()`; see `options(zuint.double)`.
#' * `zuint_overflow_error`: a result out of range under a `checked_*()`
#'   function (see [checked_add()]).
#' * `zuint_division_error`: a zero divisor in [checked_idiv()] or
#'   [checked_mod()].
#' * `zuint_arrow_error`: an Arrow array zuint cannot read, or a released
#'   struct (see [zu_from_arrow()]).
#' * `zuint_unsupported_error`: an operation zuint does not do, such as
#'   `quantile()` or a matrix.
#'
#' Warnings:
#'
#' * `zuint_cast_warning`: values that could not be represented became `NA`.
#' * `zuint_overflow_warning`: a result out of range became `NA`.
#' * `zuint_precision_warning`: a conversion to double rounded.
#' * `zuint_double_warning`: a double was computed in double, under
#'   `options(zuint.double = "allow")`.
#' * `zuint_recycling_warning`: operand lengths are not multiples.
#' * `zuint_empty_warning`: `min()` or `max()` of nothing.
#'
#' @examples
#' tryCatch(int128(1) + uint128(1), zuint_incompatible_error = function(e) "no common type")
#' withCallingHandlers(int64(1.5), zuint_cast_warning = function(w) invokeRestart("muffleWarning"))
#' @name zuint-conditions
NULL

# The kinds are listed in the topic above; keep it in step.
#
# `call` is the user's call to report, usually the exported function's own
# sys.call().

zu_abort <- function(message, kind, call = NULL) {
  stop(errorCondition(
    message,
    class = c(paste0("zuint_", kind, "_error"), "zuint_error"),
    call = call
  ))
}

zu_warn <- function(message, kind, call = NULL) {
  warning(warningCondition(
    message,
    class = c(paste0("zuint_", kind, "_warning"), "zuint_warning"),
    call = call
  ))
}

zu_warn_lost <- function(n, type, call = NULL) {
  if (n > 0) {
    zu_warn(
      sprintf(
        "%s value%s could not be represented as %s and became NA.",
        format(n, scientific = FALSE),
        if (n == 1) "" else "s",
        type
      ),
      "cast",
      call = call
    )
  }
}
