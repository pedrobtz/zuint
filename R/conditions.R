# Condition classes are part of the API; messages are not.
#   zuint_type_error        an argument of the wrong kind
#   zuint_cast_warning      values that could not be represented became NA
#   zuint_precision_warning a conversion to double rounded
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
