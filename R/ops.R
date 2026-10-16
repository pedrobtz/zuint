# Arithmetic and comparison (design 5, 6). Operands are converted to their
# common type in R, then the C code computes under one of three overflow
# policies. Codes match zu_policy, zu_op and zu_cmp_op in src/.

zu_policy_default <- 0L
zu_policy_checked <- 1L
zu_policy_wrap <- 2L

zu_arith_ops <- c("+" = 1L, "-" = 2L, "*" = 3L, "%/%" = 4L, "%%" = 5L)
zu_compare_ops <- c("==" = 1L, "!=" = 2L, "<" = 3L, "<=" = 4L, ">" = 5L, ">=" = 6L)

zu_ops <- function(e1, e2) {
  op <- .Generic
  call <- sys.call()
  if (missing(e2)) {
    return(switch(
      op,
      "-" = zu_negate(e1, zu_policy_default, call),
      "+" = e1,
      "!" = !zu_as_logical(e1)
    ))
  }
  switch(
    op,
    "+" = ,
    "-" = ,
    "*" = ,
    "%/%" = ,
    "%%" = zu_arith(op, e1, e2, zu_policy_default, call),
    "/" = zu_divide(e1, e2, call),
    "^" = zu_pow(e1, e2, zu_policy_default, call),
    "&" = as.logical(e1) & as.logical(e2),
    "|" = as.logical(e1) | as.logical(e2),
    zu_compare(op, e1, e2, call)
  )
}

zu_math <- function(x, ...) {
  code <- zu_code(x)
  switch(
    .Generic,
    abs = zu_new(.Call(zu_abs_sign_c, zu_unclass(x), code, FALSE), code),
    sign = zu_new(.Call(zu_abs_sign_c, zu_unclass(x), code, TRUE), code),
    floor = ,
    ceiling = ,
    trunc = x,
    round = zu_round(x, ..., call = sys.call()),
    signif = zu_signif(x, ..., call = sys.call()),
    cumsum = ,
    cumprod = ,
    cummax = ,
    cummin = {
      what <- match(.Generic, c("cumsum", "cumprod", "cummax", "cummin"))
      res <- .Call(zu_cum_c, x, code, what)
      zu_report_overflow(res[[2L]], zu_policy_default, sys.call())
      out <- res[[1L]]
      names(out) <- names(x)
      zu_new(out, code)
    },
    # everything else is a real function: compute it on the doubles
    do.call(.Generic, list(zu_as_double(x), ...))
  )
}

# ---- operands ---------------------------------------------------------------

zu_check_operands <- function(kinds, args, call) {
  bad <- is.na(kinds) | kinds == zu_kind_chr
  if (any(bad)) {
    zu_abort(
      sprintf("Can't use %s in zuint arithmetic.", zu_kind_label(args[[which(bad)[[1L]]]])),
      "type",
      call = call
    )
  }
  if (!any(kinds > 0L)) {
    zu_abort("At least one operand must be a zuint vector.", "type", call = call)
  }
}

# A double that is not integral or not in range of `type`: an error, or a
# warning when options(zuint.double = "allow"), in which case the caller
# computes in double.
zu_double_problem <- function(type, call) {
  if (zu_double_policy() == "allow") {
    zu_warn(
      sprintf("A double is not an integral value in range of %s; computing in double.", type),
      "double",
      call = call
    )
  } else {
    zu_abort(
      sprintf(
        "A double must be integral and in range of %s to mix with it. Convert it explicitly, or set options(zuint.double = \"allow\").",
        type
      ),
      "double",
      call = call
    )
  }
}

# One operand for the C arithmetic, in common type `code`: R's integers go
# as they are (kind 0), since the C code applies the policy to a negative
# one meeting an unsigned type; the rest become payloads of `code`. NULL
# when a double did not convert.
zu_operand <- function(x, kind, code) {
  if (kind == zu_kind_int) {
    if (is.null(x)) {
      x <- integer()
    }
    # into a signed type, or without negatives, an integer converts exactly
    # and the C code takes its fast path
    if ((code == 1L || code == 3L || !any(x < 0L, na.rm = TRUE)) && length(x) <= 1L) {
      return(list(value = zu_convert(x, kind, code)[[1L]], kind = code))
    }
    return(list(value = x, kind = 0L))
  }
  r <- zu_convert(x, kind, code)
  if (r[[2L]] > 0) NULL else list(value = r[[1L]], kind = code)
}

# The doubles an operand stands for, without a precision warning: callers
# that compute in double have said so.
zu_dbl_quiet <- function(x) {
  code <- zu_code(x)
  if (is.na(code)) as.double(x) else .Call(zu_to_double_c, x, code)[[1L]]
}

# Names as base arithmetic gives them: the first operand's when it is as
# long as the result, else the second's.
zu_result_names <- function(x, y, n) {
  if (length(x) == n && !is.null(names(x))) names(x) else if (length(y) == n) names(y)
}

zu_check_recycling <- function(x, y) {
  nx <- length(x)
  ny <- length(y)
  if (nx > 0L && ny > 0L && max(nx, ny) %% min(nx, ny) != 0L) {
    zu_warn("longer object length is not a multiple of shorter object length", "recycling")
  }
}

# Overflows under the default policy warn; under checked_* they are errors.
zu_report_overflow <- function(n, policy, call) {
  if (n == 0) {
    return(invisible())
  }
  msg <- sprintf(
    "%s result%s out of range.",
    format(n, scientific = FALSE),
    if (n == 1) " is" else "s are"
  )
  if (policy == zu_policy_checked) {
    zu_abort(msg, "overflow", call = call)
  } else if (policy == zu_policy_default) {
    zu_warn(paste(msg, "NA produced."), "overflow", call = call)
  }
}

# ---- operations -------------------------------------------------------------

zu_arith <- function(op, x, y, policy, call) {
  kinds <- c(zu_kind(x), zu_kind(y))
  zu_check_operands(kinds, list(x, y), call)
  zu_check_recycling(x, y)
  if (policy == zu_policy_checked && op %in% c("%/%", "%%") && length(x) > 0L &&
    isTRUE(any(y == 0L, na.rm = TRUE))) {
    zu_abort("Division by zero.", "division", call = call)
  }
  code <- zu_common_code(kinds, call)
  ox <- zu_operand(x, kinds[[1L]], code)
  oy <- zu_operand(y, kinds[[2L]], code)
  if (is.null(ox) || is.null(oy)) {
    zu_double_problem(zu_types[[code]], call)
    return(get(op, baseenv())(zu_dbl_quiet(x), zu_dbl_quiet(y)))
  }
  res <- .Call(zu_arith_c, zu_arith_ops[[op]], ox$value, ox$kind, oy$value, oy$kind, code, policy)
  zu_report_overflow(res[[2L]], policy, call)
  out <- res[[1L]]
  names(out) <- zu_result_names(x, y, length(out))
  zu_new(out, code)
}

zu_negate <- function(x, policy, call) {
  zu_check_operands(zu_kind(x), list(x), call)
  code <- zu_code(x)
  res <- .Call(zu_neg_c, x, code, policy)
  zu_report_overflow(res[[2L]], policy, call)
  out <- res[[1L]]
  names(out) <- names(x)
  zu_new(out, code)
}

# `/` is division in double, as it is for R's integers.
zu_divide <- function(x, y, call) {
  zu_check_operands(c(zu_kind(x), zu_kind(y)), list(x, y), call)
  out <- zu_dbl_quiet(x) / zu_dbl_quiet(y)
  names(out) <- zu_result_names(x, y, length(out))
  out
}

# Exact when every exponent is a non-negative integer; anything else is
# computed in double. The result type is the base's, or the common type
# when the base is not a zuint vector.
zu_pow <- function(x, y, policy, call) {
  kinds <- c(zu_kind(x), zu_kind(y))
  zu_check_operands(kinds, list(x, y), call)
  zu_check_recycling(x, y)
  code <- if (kinds[[1L]] > 0L) kinds[[1L]] else zu_common_code(kinds, call)
  ky <- kinds[[2L]]
  exact <- if (ky == zu_kind_dbl) {
    all(is.na(y) | (y >= 0 & y == floor(y) & y < 2^128))
  } else if (ky == zu_kind_int) {
    all(is.na(y) | y >= 0L)
  } else {
    !isTRUE(any(zu_compare("<", y, 0L, call)))
  }
  if (!exact) {
    out <- zu_dbl_quiet(x)^zu_dbl_quiet(y)
    names(out) <- zu_result_names(x, y, length(out))
    return(out)
  }
  e <- zu_convert(y, ky, 4L)[[1L]]
  ox <- zu_operand(x, kinds[[1L]], code)
  if (is.null(ox)) {
    zu_double_problem(zu_types[[code]], call)
    return(zu_dbl_quiet(x)^zu_dbl_quiet(y))
  }
  res <- .Call(zu_pow_c, ox$value, ox$kind, e, code, policy)
  zu_report_overflow(res[[2L]], policy, call)
  out <- res[[1L]]
  names(out) <- zu_result_names(x, y, length(out))
  zu_new(out, code)
}

# Exact for any two kinds, doubles included, and never an error for being
# out of range: 1.5 is compared as 1.5.
zu_compare <- function(op, x, y, call) {
  kinds <- c(zu_kind(x), zu_kind(y))
  zu_check_operands(kinds, list(x, y), call)
  zu_check_recycling(x, y)
  out <- .Call(zu_compare_c, zu_compare_ops[[op]], x, kinds[[1L]], y, kinds[[2L]])
  names(out) <- zu_result_names(x, y, length(out))
  out
}

# ---- overflow policies --------------------------------------------------------

#' Arithmetic with an explicit overflow policy
#'
#' The operators `+`, `-`, `*`, `%/%`, `%%`, `^` and unary minus give `NA`
#' with one warning of class `zuint_overflow_warning` per call when a result
#' is out of range. These functions choose differently:
#'
#' * `checked_*()` raise an error of class `zuint_overflow_error` instead.
#' * `wrapping_*()` compute modulo \eqn{2^{64}} or \eqn{2^{128}}, for hashing
#'   and checksums. A result that wraps onto the type's `NA` bit pattern is
#'   `NA`: `NA`-ness never depends on the policy. A negative integer operand
#'   of an unsigned type wraps too.
#'
#' Operands take their common type first (see [zu_common_type()]). `%/%`
#' rounds towards negative infinity and `%%` takes the sign of the divisor,
#' as in R; division by zero is `NA`, except in `checked_idiv()` and
#' `checked_mod()`, where it is an error of class `zuint_division_error`. `/` divides in double. `^` is exact
#' for a non-negative integer exponent and computed in double otherwise.
#' Comparison is exact across all the types and doubles.
#'
#' @param x,y zuint vectors, or a zuint vector and a logical, integer or
#'   double vector. They are recycled.
#' @return A zuint vector of the common type.
#' @examples
#' x <- int64("9223372036854775807")
#' x + 1L
#' try(checked_add(x, 1L))
#' wrapping_add(x, 2L)
#' wrapping_mul(uint64("18446744073709551614"), 31L)
#' checked_pow(int128(2), 126L)
#' @name zuint-arith
NULL

#' @rdname zuint-arith
#' @export
checked_add <- function(x, y) zu_arith("+", x, y, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
checked_sub <- function(x, y) zu_arith("-", x, y, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
checked_mul <- function(x, y) zu_arith("*", x, y, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
checked_idiv <- function(x, y) zu_arith("%/%", x, y, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
checked_mod <- function(x, y) zu_arith("%%", x, y, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
checked_pow <- function(x, y) zu_pow(x, y, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
checked_neg <- function(x) zu_negate(x, zu_policy_checked, sys.call())

#' @rdname zuint-arith
#' @export
wrapping_add <- function(x, y) zu_arith("+", x, y, zu_policy_wrap, sys.call())

#' @rdname zuint-arith
#' @export
wrapping_sub <- function(x, y) zu_arith("-", x, y, zu_policy_wrap, sys.call())

#' @rdname zuint-arith
#' @export
wrapping_mul <- function(x, y) zu_arith("*", x, y, zu_policy_wrap, sys.call())

#' @rdname zuint-arith
#' @export
wrapping_pow <- function(x, y) zu_pow(x, y, zu_policy_wrap, sys.call())

#' @rdname zuint-arith
#' @export
wrapping_neg <- function(x) zu_negate(x, zu_policy_wrap, sys.call())

# ---- rounding to tens, hundreds, ... -----------------------------------------

# round(x, digits): the identity for digits >= 0; for digits < 0, the nearest
# multiple of 10^-digits, ties to the even multiple, on the exact value (as
# base R rounds integers). A multiple beyond the type is NA with an overflow
# warning, as in arithmetic.
zu_round <- function(x, digits = 0, ..., call = NULL) {
  digits <- zu_digits_arg(digits, call)
  if (digits >= 0L) {
    return(x)
  }
  zu_round_to(x, -digits, call)
}

# signif(x, digits): keep `digits` significant decimal digits (at least 1),
# rounding as zu_round() does.
zu_signif <- function(x, digits = 6L, ..., call = NULL) {
  digits <- max(1L, zu_digits_arg(digits, call))
  s <- zu_as_character(abs(x))
  shift <- ifelse(is.na(s), 0L, pmax(0L, nchar(s) - digits))
  out <- x
  for (k in setdiff(unique(shift), 0L)) {
    at <- shift == k
    out[at] <- zu_round_to(x[at], k, call)
  }
  out
}

zu_digits_arg <- function(digits, call) {
  if (length(digits) != 1L || is.na(digits) || !is.numeric(digits)) {
    zu_abort("`digits` must be a single number.", "type", call = call)
  }
  as.integer(digits)
}

zu_round_to <- function(x, k, call) {
  code <- zu_code(x)
  # 10^k in the widest type of the same signedness. When it does not fit,
  # it exceeds twice every value of the type, so every value rounds to 0
  wide <- if (code %in% c(1L, 3L)) 3L else 4L
  p <- withCallingHandlers(
    zu_new(zu_bare(zu_cast(10L, wide)), wide)^k,
    zuint_overflow_warning = function(w) invokeRestart("muffleWarning")
  )
  xw <- zu_cast(x, wide)
  if (all(is.na(p))) {
    out <- xw * 0L
  } else {
    q <- xw %/% p
    r <- xw %% p
    up <- r > p - r | (r == p - r & q %% 2L == 1L)
    up[is.na(up)] <- FALSE
    out <- (q + zu_ifelse_raw(up, 1L, 0L)) * p
  }
  zu_narrow(out, code, call)
}

zu_ifelse_raw <- function(test, yes, no) {
  out <- rep(no, length(test))
  out[test] <- yes
  out
}

# A value computed in a wider type, back in `code`: exact, or NA with an
# overflow warning.
zu_narrow <- function(x, code, call) {
  out <- withCallingHandlers(
    zu_cast(x, code),
    zuint_cast_warning = function(w) {
      zu_warn("A rounded value is out of range. NA produced.", "overflow", call = call)
      invokeRestart("muffleWarning")
    }
  )
  names(out) <- names(x)
  out
}
