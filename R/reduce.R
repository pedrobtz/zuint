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

# A logical argument as base's `if (arg)` reads it: 1 is TRUE; NA, a vector
# or text that is not a logical is an error.
zu_flag <- function(x, arg, call) {
  v <- if (length(x) == 1L) suppressWarnings(as.logical(x)) else NA
  if (is.na(v)) {
    zu_abort(
      sprintf("`%s` must be TRUE or FALSE.", arg),
      "type",
      call = call
    )
  }
  v
}

# `na.last` of sort(): TRUE, FALSE or NA.
zu_na_last <- function(x, call) {
  if (length(x) != 1L || !is.logical(x)) {
    zu_abort("`na.last` must be TRUE, FALSE or NA.", "type", call = call)
  }
  x
}

# A whole number >= `min` for `lag` and `differences`. Base R's diff() gives
# a fraction a meaningless answer (and a warning), so it is refused here.
zu_whole_arg <- function(x, arg, min, call) {
  x <- zu_index(x)
  v <- if (length(x) == 1L && is.numeric(x) && isTRUE(x == floor(x))) {
    suppressWarnings(as.integer(x))
  } else {
    NA_integer_
  }
  if (is.na(v) || v < min) {
    zu_abort(
      sprintf("`%s` must be a single whole number of at least %d.", arg, min),
      "type",
      call = call
    )
  }
  v
}

# The values `incomparables` names, which are never duplicates of one
# another; NULL for FALSE, which names none.
zu_incomparable <- function(x, incomparables, call) {
  if (isFALSE(incomparables)) {
    return(NULL)
  }
  zu_match(x, incomparables, nomatch = 0L) > 0L
}

# `nomatch` of match(): one value, truncated to an integer.
zu_nomatch_arg <- function(nomatch, call) {
  nomatch <- zu_index(nomatch)
  if (length(nomatch) != 1L || !(is.numeric(nomatch) || is.logical(nomatch))) {
    zu_abort("`nomatch` must be a single number.", "type", call = call)
  }
  as.integer(nomatch)
}

zu_mean <- function(x, trim = 0, na.rm = FALSE, ...) {
  na.rm <- zu_flag(na.rm, "na.rm", sys.call())
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
  na.rm <- zu_flag(na.rm, "na.rm", sys.call())
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
zu_sort <- function(
  x,
  decreasing = FALSE,
  na.last = NA,
  index.return = FALSE,
  partial = NULL,
  ...
) {
  call <- sys.call()
  if (!is.null(partial)) {
    zu_abort(
      "sort() with `partial` is not supported for zuint vectors.",
      "unsupported",
      call = call
    )
  }
  decreasing <- zu_flag(decreasing, "decreasing", call)
  na.last <- zu_na_last(na.last, call)
  index.return <- zu_flag(index.return, "index.return", call)
  code <- zu_code(x)
  if (index.return) {
    # as sort.int(): `ix` indexes x, with the NAs dropped first when
    # na.last is NA
    if (is.na(na.last)) {
      x <- x[!zu_is_na(x)]
      na.last <- TRUE
    }
    ix <- .Call(zu_order_c, x, code, decreasing, na.last)
    return(list(x = x[ix], ix = ix))
  }
  if (!is.null(names(x))) {
    return(x[.Call(zu_order_c, x, code, decreasing, na.last)])
  }
  s <- .Call(zu_sort_values_c, x, code, decreasing)
  n_na <- length(x) - length(s)
  if (n_na > 0L && !is.na(na.last)) {
    nas <- zu_bare(zu_cast(rep(NA, n_na), code))
    s <- if (na.last) c(s, nas) else c(nas, s)
  }
  zu_new(s, code)
}

# Integer ranks, ties sharing the lowest, so base order() and rank() on any
# number of keys stay exact (design 7). Doubles only past 2^31 - 1 values.
zu_xtfrm <- function(x) {
  .Call(zu_rank_c, x, zu_code(x))
}

zu_duplicated <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  fromLast <- zu_flag(fromLast, "fromLast", sys.call())
  d <- .Call(zu_duplicated_c, x, zu_code(x), fromLast)
  inc <- zu_incomparable(x, incomparables, sys.call())
  if (!is.null(inc)) {
    d[inc] <- FALSE
  }
  d
}

# Names go, as base unique() drops them.
zu_unique <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  fromLast <- zu_flag(fromLast, "fromLast", sys.call())
  if (fromLast || !is.null(names(x)) || !isFALSE(incomparables)) {
    out <- x[
      !zu_duplicated(x, incomparables = incomparables, fromLast = fromLast)
    ]
    names(out) <- NULL
    return(out)
  }
  zu_new(.Call(zu_unique_c, x, zu_code(x)), zu_code(x))
}

zu_any_duplicated <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  fromLast <- zu_flag(fromLast, "fromLast", sys.call())
  d <- zu_duplicated(x, incomparables = incomparables, fromLast = fromLast)
  if (any(d)) which(d)[[if (fromLast) sum(d) else 1L]] else 0L
}

# What match(), %in% and table() compare: the exact decimal text. match()
# is not generic, and no other atomic vector maps these values one to one.
# An unclassed double or logical on the other side reaches match() as its
# own text ("1e+05"), which this cannot change (design 7, #149).
zu_mtfrm <- function(x) zu_as_character(x)

#' Exact, fast matching
#'
#' `zu_match()` is [base::match()] for zuint vectors, and `%zin%` is `%in%`. Base
#' `match()` and `%in%` compare exact decimal text when both sides are zuint
#' vectors; these hash the values themselves and are much faster on long
#' vectors. They are also exact when one side is a bare number, which base
#' `match()` is not (see below).
#'
#' Both arguments take their common type first (see [zu_common_type()]); `NA`
#' matches `NA`. A [decimal128()] matches by value, whatever the scales:
#' `1.0` matches `1.00` and the integer `1`.
#'
#' @section Base functions and a bare number:
#' [base::match()] and `%in%` are not generic. They turn the zuint side into text
#' with `mtfrm()`, and the other side, if it is a bare double or logical,
#' into text by R's own rules. The two texts then differ: `1e5` is `"1e+05"`,
#' and `int64(100000) %in% 100000` is `FALSE`. The answer also changes with
#' `options(scipen =)` and `OutDec`, and with bit64 attached, whose masked
#' `%in%` answers differently. A method cannot reach the bare side.
#'
#' [base::table()], [merge()] and the set functions [base::intersect()], [base::setdiff()],
#' [base::union()] and [base::is.element()] go through `match()` and have the same
#' limit. `intersect(int64(1e5), 1e5)` is empty, and `setdiff()` and
#' `union()` return the raw bits of the zuint side.
#'
#' Use `zu_match()` or `%zin%`, or convert the bare side first, for example
#' `int64(1e5)`. Two zuint vectors of the same type are always safe.
#'
#' @param x Values to look up: a zuint vector, or an integer vector when
#'   `table` is one.
#' @param table Values to look them up in.
#' @param nomatch The position to give values not in `table`: one number,
#'   truncated to an integer, as [base::match()] does.
#' @return `zu_match()` returns an integer vector of positions in `table`;
#'   `%zin%` a logical vector.
#' @examples
#' zu_match(uint64(c("18446744073709551614", "7")), uint64(c(7, 1)))
#' int64(5) %zin% int64(1:10)
#' # a bare double is compared as text by base R, and by value here
#' int64(100000) %in% 100000
#' int64(100000) %zin% 100000
#' @export
zu_match <- function(x, table, nomatch = NA_integer_) {
  call <- sys.call()
  x <- zu_from_bit64(x)
  table <- zu_from_bit64(table)
  if (is_decimal128(x) || is_decimal128(table)) {
    return(dec_match(x, table, zu_nomatch_arg(nomatch, call), call))
  }
  kinds <- c(zu_kind(x), zu_kind(table))
  zu_check_operands(kinds, list(x, table), call)
  code <- zu_common_code(kinds, call)
  nomatch <- zu_nomatch_arg(nomatch, call)
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
  call <- sys.call()
  lag <- zu_whole_arg(lag, "lag", 1L, call)
  differences <- zu_whole_arg(differences, "differences", 1L, call)
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

#' Cut a zuint vector into intervals
#'
#' `cut()` of a zuint or [decimal128()] vector compares each value with the
#' breaks exactly, so values beyond 2^53 fall in the interval they belong to.
#' Base `cut()` reads such a vector's raw bits.
#'
#' The arguments are those of [base::cut.default()]. `breaks` is a zuint
#' vector or a number vector, in any order; the values are compared with it
#' as `x > b` and `x <= b` are, never through a double. The default labels
#' write each break in full, so `dig.lab` is accepted and not used.
#'
#' A single number of intervals as `breaks` is refused with a
#' `zuint_unsupported_error`: base derives the breaks from the range with a
#' fractional step, which a vector of integers cannot hold. Give the breaks.
#' Breaks that are `NA`, repeated or not numbers, a `labels` vector of the
#' wrong length and a flag that is not `TRUE` or `FALSE` are a
#' `zuint_type_error`.
#'
#' @param x A zuint or `decimal128` vector.
#' @param breaks At least two breaks, in any order.
#' @param labels `NULL` for the default labels, `FALSE` for integer codes,
#'   or one label for each interval.
#' @param include.lowest Whether the lowest break (the highest, when
#'   `right = FALSE`) belongs to its interval.
#' @param right Whether the intervals are closed on the right.
#' @param dig.lab Accepted for compatibility; the labels are not rounded.
#' @param ordered_result Whether the factor is ordered.
#' @param ... Not used.
#' @return A factor, or an integer vector for `labels = FALSE`; `NA` for a
#'   value outside every interval and for `NA`.
#' @examples
#' x <- int64(c("9007199254740993", "9007199254740994", "-5"))
#' cut(x, int64(c("-10", "9007199254740993", "9007199254740995")))
#' cut(x, c(-10, 0, 1e16), labels = FALSE)
#' @name zu_cut
NULL

zu_cut <- function(
  x,
  breaks,
  labels = NULL,
  include.lowest = FALSE,
  right = TRUE,
  dig.lab = 3L,
  ordered_result = FALSE,
  ...
) {
  call <- sys.call()
  include.lowest <- zu_flag(include.lowest, "include.lowest", call)
  right <- zu_flag(right, "right", call)
  ordered_result <- zu_flag(ordered_result, "ordered_result", call)
  breaks <- zu_from_bit64(breaks)
  plain <- !is.object(breaks) &&
    typeof(breaks) %in% c("logical", "integer", "double")
  if (!(plain || !is.na(zu_code(breaks)) || is_decimal128(breaks))) {
    zu_abort("`breaks` must be numbers.", "type", call = call)
  }
  if (length(breaks) == 1L) {
    zu_abort(
      "`breaks` as a number of intervals is not supported for zuint vectors; give the breaks.",
      "unsupported",
      call = call
    )
  }
  if (length(breaks) < 2L || anyNA(breaks)) {
    zu_abort(
      "`breaks` must be at least two values, none NA.",
      "type",
      call = call
    )
  }
  breaks <- sort(breaks)
  if (anyDuplicated(breaks)) {
    zu_abort("`breaks` are not unique.", "type", call = call)
  }
  nb <- length(breaks)
  codes_only <- is.logical(labels) &&
    length(labels) == 1L &&
    !is.na(labels) &&
    !labels
  if (is.null(labels)) {
    text <- zu_break_text(breaks)
    labels <- if (anyDuplicated(text)) {
      paste0("Range_", seq_len(nb - 1L))
    } else {
      paste0(
        if (right) "(" else "[",
        text[-nb],
        ",",
        text[-1L],
        if (right) "]" else ")"
      )
    }
    if (include.lowest && !anyDuplicated(text)) {
      if (right) {
        substr(labels[1L], 1L, 1L) <- "["
      } else {
        substring(labels[nb - 1L], nchar(labels[nb - 1L], "c")) <- "]"
      }
    }
  } else if (!codes_only && length(labels) != nb - 1L) {
    zu_abort(
      "The number of intervals and the length of `labels` differ.",
      "type",
      call = call
    )
  }
  # the number of breaks below x (right) or at most x (left) is its interval
  below <- integer(length(x))
  for (j in seq_len(nb)) {
    b <- breaks[j]
    below <- below + if (right) as.integer(x > b) else as.integer(x >= b)
  }
  code <- below
  if (include.lowest) {
    if (right) {
      code[zu_true(x == breaks[1L])] <- 1L
    } else {
      code[zu_true(x == breaks[nb])] <- nb - 1L
    }
  }
  code[is.na(x) | code < 1L | code > nb - 1L] <- NA_integer_
  if (codes_only) {
    return(code)
  }
  factor(code, seq_len(nb - 1L), labels, ordered = ordered_result)
}

zu_true <- function(x) !is.na(x) & x

# The breaks written in full: the exact text of a zuint, the shortest text
# that reads back as the same double for a double.
zu_break_text <- function(breaks) {
  if (is.object(breaks)) {
    return(as.character(breaks))
  }
  vapply(
    as.double(breaks),
    function(b) {
      if (!is.finite(b)) {
        return(as.character(b))
      }
      if (b == round(b)) {
        return(sprintf("%.0f", 0 + b))
      }
      for (digits in 15:17) {
        s <- sprintf(paste0("%.", digits, "g"), b)
        if (as.double(s) == b) break
      }
      s
    },
    ""
  )
}
