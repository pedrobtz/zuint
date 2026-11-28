# Ordering, set operations and summaries (design 7).

# The Summary group's arguments: range()'s `finite` is an argument, not
# data (#56), and for integers it drops NA, as base R does.
zu_summary_args <- function(args, generic, na.rm) {
  finite <- FALSE
  if (generic == "range" && "finite" %in% names(args)) {
    finite <- isTRUE(args[["finite"]])
    args[names(args) == "finite"] <- NULL
    na.rm <- na.rm || finite
  }
  list(args = args, na.rm = na.rm, finite = finite)
}

# The combined values were doubles, under options(zuint.double = "allow")
# (#60): the answer is base R's on those doubles.
zu_summary_double <- function(x, generic, na.rm, finite) {
  if (generic == "range") {
    return(range(x, na.rm = na.rm, finite = finite))
  }
  get(generic, baseenv())(x, na.rm = na.rm)
}

zu_summary_group <- function(..., na.rm = FALSE) {
  call <- sys.call()
  a <- zu_summary_args(list(...), .Generic, na.rm)
  args <- a$args
  na.rm <- a$na.rm
  x <- if (length(args) == 1L) args[[1L]] else do.call(zu_c, args)
  if (is_decimal128(x)) {
    # min(int64(1), <decimal128>): the decimal's method on the combination
    return(get(.Generic, baseenv())(x, na.rm = na.rm))
  }
  code <- zu_code(x)
  if (is.na(code) && zu_is_bare_double(x)) {
    # zu_c() fell back to double under options(zuint.double = "allow")
    return(zu_summary_double(x, .Generic, na.rm, a$finite))
  }
  if (is.na(code)) {
    x <- zu_cast(
      x,
      zu_common_code(vapply(args, zu_kind, integer(1)), call),
      call = call
    )
    code <- zu_code(x)
  }
  p <- x
  switch(
    .Generic,
    sum = zu_reduce_result(.Call(zu_sum_c, p, code, na.rm), code, call),
    prod = zu_reduce_result(.Call(zu_prod_c, p, code, na.rm), code, call),
    min = zu_extreme(x, code, na.rm, 1L, call),
    max = zu_extreme(x, code, na.rm, 2L, call),
    range = c(
      zu_extreme(x, code, na.rm, 1L, call),
      zu_extreme(x, code, na.rm, 2L, call)
    ),
    any = any(zu_as_logical(x), na.rm = na.rm),
    all = all(zu_as_logical(x), na.rm = na.rm)
  )
}

zu_reduce_result <- function(res, code, call) {
  zu_report_overflow(res[[2L]], zu_policy_default, call)
  zu_new(res[[1L]], code)
}

# min() or max(): exact; with nothing to take it from, Inf or -Inf with a
# warning, as base R gives for numbers.
zu_extreme <- function(x, code, na.rm, which, call) {
  if (!na.rm && anyNA(x)) {
    return(zu_new(zu_bare(zu_cast(NA, code)), code))
  }
  if (length(x) == 0L || all(zu_is_na(x))) {
    zu_warn(
      sprintf(
        "no non-missing arguments to %s; returning %s",
        c("min", "max")[[which]],
        c("Inf", "-Inf")[[which]]
      ),
      "empty"
    )
    return(c(Inf, -Inf)[[which]])
  }
  r <- .Call(zu_range_c, x, code, TRUE)
  zu_new(r[which], code)
}

zu_mean <- function(x, trim = 0, na.rm = FALSE, ...) {
  if (!identical(trim, 0) && !identical(trim, 0L)) {
    zu_abort(
      "mean() with `trim` is not supported for zuint vectors.",
      "unsupported",
      call = sys.call()
    )
  }
  zu_mean_scaled(x, na.rm, 0L)
}

# The exact mean divided by 10^scale, rounded once to a double: a decimal's
# mean is its coefficients' at its scale.
zu_mean_scaled <- function(x, na.rm, scale) {
  .Call(zu_mean_c, x, zu_code(x), isTRUE(na.rm), as.integer(scale))
}

zu_median <- function(x, na.rm = FALSE, ...) {
  zu_median_scaled(x, na.rm, 0L)
}

zu_median_scaled <- function(x, na.rm, scale) {
  if (anyNA(x)) {
    if (!na.rm) {
      return(NA_real_)
    }
    x <- x[!zu_is_na(x)]
  }
  n <- length(x)
  if (n == 0L) {
    return(NA_real_)
  }
  s <- zu_sort(x)
  mid <- s[c((n + 1L) %/% 2L, (n + 2L) %/% 2L)]
  zu_mean_scaled(mid, FALSE, scale)
}

# Values sorted in C, with the NAs put back as na.last says. Names follow
# their values, which needs the positions.
zu_sort <- function(x, decreasing = FALSE, na.last = NA, ...) {
  code <- zu_code(x)
  if (!is.null(names(x))) {
    return(x[.Call(zu_order_c, x, code, isTRUE(decreasing), na.last)])
  }
  s <- .Call(zu_sort_values_c, x, code, isTRUE(decreasing))
  n_na <- length(x) - length(s)
  if (n_na > 0L && !is.na(na.last)) {
    nas <- zu_bare(zu_cast(rep(NA, n_na), code))
    s <- if (isTRUE(na.last)) c(s, nas) else c(nas, s)
  }
  zu_new(s, code)
}

# Integer ranks, ties sharing the lowest, so base order() and rank() on any
# number of keys stay exact (design 7). Doubles only past 2^31 - 1 values.
zu_xtfrm <- function(x) {
  .Call(zu_rank_c, x, zu_code(x))
}

zu_duplicated <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  .Call(zu_duplicated_c, x, zu_code(x), isTRUE(fromLast))
}

# Names go, as base unique() drops them.
zu_unique <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  if (isTRUE(fromLast) || !is.null(names(x))) {
    out <- x[!zu_duplicated(x, fromLast = fromLast)]
    names(out) <- NULL
    return(out)
  }
  zu_new(.Call(zu_unique_c, x, zu_code(x)), zu_code(x))
}

zu_any_duplicated <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  d <- zu_duplicated(x, fromLast = fromLast)
  if (any(d)) which(d)[[if (fromLast) sum(d) else 1L]] else 0L
}

# What match(), %in% and table() compare: the exact decimal text. match()
# is not generic, and no other atomic vector maps these values one to one.
zu_mtfrm <- function(x) zu_as_character(x)

#' Exact, fast matching
#'
#' `zu_match()` is [match()] for zuint vectors, and `%zin%` is `%in%`. Base
#' `match()` and `%in%` give the same answers on zuint vectors, by comparing
#' exact decimal text; these hash the values themselves and are much faster
#' on long vectors.
#'
#' Both arguments take their common type first (see [zu_common_type()]); `NA`
#' matches `NA`. A [decimal128()] matches by value, whatever the scales:
#' `1.0` matches `1.00` and the integer `1`.
#'
#' @param x Values to look up: a zuint vector, or an integer vector when
#'   `table` is one.
#' @param table Values to look them up in.
#' @param nomatch The position to give values not in `table`.
#' @return `zu_match()` returns an integer vector of positions in `table`;
#'   `%zin%` a logical vector.
#' @examples
#' zu_match(uint64(c("18446744073709551614", "7")), uint64(c(7, 1)))
#' int64(5) %zin% int64(1:10)
#' @export
zu_match <- function(x, table, nomatch = NA_integer_) {
  call <- sys.call()
  x <- zu_from_bit64(x)
  table <- zu_from_bit64(table)
  if (is_decimal128(x) || is_decimal128(table)) {
    return(dec_match(x, table, as.integer(nomatch), call))
  }
  kinds <- c(zu_kind(x), zu_kind(table))
  zu_check_operands(kinds, list(x, table), call)
  code <- zu_common_code(kinds, call)
  nomatch <- as.integer(nomatch)
  # A value the common type can't hold matches nothing, quietly: a lookup
  # that finds nothing loses nothing (#58). Cast to NA, it must not match
  # the table's NA, nor may an NA match a table value lost the same way.
  quiet <- function(v) zu_quiet_cast(zu_cast(v, code, call = call))
  cx <- quiet(x)
  ct <- quiet(table)
  res <- .Call(zu_match_c, cx, ct, code, nomatch)
  na_x <- is.na(cx)
  lost_x <- na_x & !is.na(x)
  res[lost_x] <- nomatch
  if (any(is.na(ct) & !is.na(table)) && any(na_x & !lost_x)) {
    first <- match(TRUE, is.na(table))
    res[na_x & !lost_x] <- if (is.na(first)) nomatch else first
  }
  res
}

#' @rdname zu_match
#' @export
`%zin%` <- function(x, table) zu_match(x, table, nomatch = 0L) > 0L

zu_diff <- function(x, lag = 1L, differences = 1L, ...) {
  lag <- zu_index(lag)
  differences <- zu_index(differences)
  for (i in seq_len(differences)) {
    n <- length(x)
    if (lag >= n) {
      return(x[0L])
    }
    x <- x[-seq_len(lag)] - x[-(n - seq_len(lag) + 1L)]
  }
  x
}

#' Exact sequences
#'
#' `seq_zu()` is [seq()] for zuint vectors: `from`, `from + by`, ... up to
#' `to`, or `length.out` values, computed exactly in the common type of the
#' arguments.
#'
#' @param from,to The ends: zuint vectors or integers, length 1.
#' @param by The step, length 1, not zero. Without it the step is 1, or -1
#'   when `to` is below `from`; with `to` and `length.out` it is the whole
#'   step between them, and an error if there is none.
#' @param length.out The number of values, instead of `to` (or with it, to fix
#'   the step). A fraction rounds up, as in [seq()]. `seq_zu(n)` is `1:n`.
#' @return A zuint vector.
#' @examples
#' seq_zu(uint64("18446744073709551600"), uint64("18446744073709551614"), by = 7L)
#' seq_zu(int128(-2), by = int128("1000000000000000000000"), length.out = 3)
#' @export
seq_zu <- function(from, to = NULL, by = 1L, length.out = NULL) {
  zu_seq_impl(from, to, if (missing(by)) NULL else by, length.out, sys.call())
}

# `by` is NULL when the caller gave none: a step of 1, or -1 when `to` is
# below `from`; or, with `to` and `length.out`, the whole step between them.
zu_seq_impl <- function(from, to, by, length.out, call) {
  by_given <- !is.null(by)
  if (!by_given) {
    by <- 1L
  }
  if (is.null(to) && is.null(length.out) && !by_given) {
    # seq(n) is 1:n, as in base R; a longer vector is seq_along()
    if (length(from) != 1L) {
      return(seq_along(from))
    }
    to <- from
    from <- 1L
  }
  args <- list(from, to, by)
  kinds <- vapply(
    args,
    function(a) if (is.null(a)) 0L else zu_kind(a),
    integer(1)
  )
  zu_check_operands(kinds, args, call)
  # the elements' type comes from `from` and `to`; `by` only steps, and may be
  # negative for an unsigned type
  code <- zu_common_code(kinds[1:2], call)
  if (code == 0L) {
    code <- zu_common_code(kinds, call)
  }
  from <- zu_cast(from, code, call = call)
  by <- zu_from_bit64(by)
  if (!is.null(length.out)) {
    if (!is.na(zu_code(length.out))) {
      # a count, compared with the integer range below (#153)
      length.out <- zu_dbl_quiet(length.out)
    }
    if (
      length(length.out) != 1L ||
        !is.numeric(length.out) ||
        is.na(length.out) ||
        length.out < 0
    ) {
      zu_abort(
        "`length.out` must be a single non-negative number.",
        "type",
        call = call
      )
    }
    # a fractional count is rounded up, as base seq() does
    length.out <- ceiling(length.out)
  }
  if (length(from) != 1L || is.na(from) || length(by) != 1L || is.na(by)) {
    zu_abort(
      "`from` and `by` must be single non-missing values.",
      "type",
      call = call
    )
  }
  if (by == 0L) {
    zu_abort("`by` must not be zero.", "type", call = call)
  }
  if (!is.null(to) && !is.null(length.out)) {
    if (by_given) {
      zu_abort(
        "`to`, `by` and `length.out` together over-determine the sequence.",
        "type",
        call = call
      )
    }
    return(zu_seq_between(from, to, length.out, code, call))
  }
  down <- by < 0L
  # the step's magnitude, in the elements' type
  step <- withCallingHandlers(
    zu_cast(abs(by), code, call = call),
    zuint_cast_warning = function(w) {
      zu_abort(
        "`by` is out of range of the sequence's type.",
        "type",
        call = call
      )
    }
  )
  if (is.null(length.out)) {
    to <- zu_cast(to, code, call = call)
    if (length(to) != 1L || is.na(to)) {
      zu_abort("`to` must be a single non-missing value.", "type", call = call)
    }
    if (!by_given && to < from) {
      down <- TRUE
    }
    if ((to > from && down) || (to < from && !down)) {
      zu_abort(
        "`by` goes the wrong way from `from` to `to`.",
        "type",
        call = call
      )
    }
    length.out <- zu_seq_count(from, to, step, down, call)
  }
  if (length.out > .Machine$integer.max) {
    zu_abort("The sequence is too long.", "type", call = call)
  }
  n <- as.integer(length.out)
  if (n == 0L) {
    return(from[0L])
  }
  steps <- rep(step, n - 1L)
  # Each partial sum is an element, so no intermediate value leaves the
  # range. Downwards in an unsigned type, the offsets k * step are at most
  # from - to and so fit too.
  if (!down) {
    cumsum(c(from, steps))
  } else if (code == 1L || code == 3L) {
    cumsum(c(from, -steps))
  } else {
    from - cumsum(c(step * 0L, steps))
  }
}

# from, to and length.out: n values from `from` to `to`, whose step must be
# whole (a zuint vector has no fractions); anything else is an error.
zu_seq_between <- function(from, to, n, code, call) {
  to <- zu_cast(to, code, call = call)
  if (length(to) != 1L || is.na(to)) {
    zu_abort("`to` must be a single non-missing value.", "type", call = call)
  }
  if (n > .Machine$integer.max) {
    zu_abort("The sequence is too long.", "type", call = call)
  }
  if (n == 0) {
    return(from[0L])
  }
  if (n == 1) {
    return(from)
  }
  down <- to < from
  # |to - from| in a type that holds it: int128 for the 64-bit types
  wide <- if (code %in% c(1L, 2L)) 3L else code
  hi <- zu_cast(if (down) from else to, wide, call = call)
  lo <- zu_cast(if (down) to else from, wide, call = call)
  d <- withCallingHandlers(
    hi - lo,
    zuint_overflow_warning = function(w) {
      zu_abort(
        "The distance from `from` to `to` is too wide for `length.out`.",
        "type",
        call = call
      )
    }
  )
  m <- as.integer(n) - 1L
  if (!(d %% m == 0L)) {
    zu_abort(
      "The step from `from` to `to` in `length.out` values is not whole.",
      "type",
      call = call
    )
  }
  step <- zu_cast(d %/% m, code, call = call)
  if (step == 0L) {
    return(rep(from, length.out = n))
  }
  if (down) {
    # up from `to`, then reversed: a step of -step may not exist in the type
    return(rev(zu_seq_impl(to, NULL, step, n, call)))
  }
  zu_seq_impl(from, NULL, step, n, call)
}

# floor(|to - from| / step) + 1 without forming to - from, which may not fit:
# with a = q_a * step + r_a (floor division, 0 <= r < step) for the larger
# end and likewise for the smaller, the count is (q_a - q_b) - (r_a < r_b) + 1.
# q_a - q_b only overflows when step is so small that the sequence would be
# too long anyway.
zu_seq_count <- function(from, to, step, down, call) {
  hi <- if (down) from else to
  lo <- if (down) to else from
  # in the elements' own type: q_hi >= q_lo, so an unsigned difference
  # cannot wrap, and a signed one that overflows is too long anyway (#59)
  dq <- withCallingHandlers(
    (hi %/% step) - (lo %/% step),
    zuint_overflow_warning = function(w) invokeRestart("muffleWarning")
  )
  if (is.na(dq) || dq > .Machine$integer.max) {
    return(Inf)
  }
  zu_dbl_quiet(dq) - as.double(hi %% step < lo %% step) + 1
}
