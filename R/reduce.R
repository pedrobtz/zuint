# Ordering, set operations and summaries (design 7).

zu_summary_group <- function(..., na.rm = FALSE) {
  call <- sys.call()
  args <- list(...)
  x <- if (length(args) == 1L) args[[1L]] else do.call(zu_c, args)
  code <- zu_code(x)
  if (is.na(code)) {
    x <- zu_cast(x, zu_common_code(vapply(args, zu_kind, integer(1)), call), call = call)
    code <- zu_code(x)
  }
  p <- x
  switch(
    .Generic,
    sum = zu_reduce_result(.Call(zu_sum_c, p, code, na.rm), code, call),
    prod = zu_reduce_result(.Call(zu_prod_c, p, code, na.rm), code, call),
    min = zu_extreme(x, code, na.rm, 1L, call),
    max = zu_extreme(x, code, na.rm, 2L, call),
    range = c(zu_extreme(x, code, na.rm, 1L, call), zu_extreme(x, code, na.rm, 2L, call)),
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
    warning(
      sprintf("no non-missing arguments to %s; returning %s", c("min", "max")[[which]], c("Inf", "-Inf")[[which]]),
      call. = FALSE
    )
    return(c(Inf, -Inf)[[which]])
  }
  r <- .Call(zu_range_c, x, code, TRUE)
  zu_new(r[which], code)
}

zu_mean <- function(x, ..., na.rm = FALSE) {
  .Call(zu_mean_c, x, zu_code(x), isTRUE(na.rm))
}

zu_median <- function(x, na.rm = FALSE, ...) {
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
  zu_mean(mid)
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

zu_unique <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  if (isTRUE(fromLast) || !is.null(names(x))) {
    return(x[!zu_duplicated(x, fromLast = fromLast)])
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
#' matches `NA`.
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
  kinds <- c(zu_kind(x), zu_kind(table))
  zu_check_operands(kinds, list(x, table), call)
  code <- zu_common_code(kinds, call)
  .Call(zu_match_c, zu_cast(x, code, call = call), zu_cast(table, code, call = call), code, as.integer(nomatch))
}

#' @rdname zu_match
#' @export
`%zin%` <- function(x, table) zu_match(x, table, nomatch = 0L) > 0L

zu_diff <- function(x, lag = 1L, differences = 1L, ...) {
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
#' @param by The step, length 1, not zero.
#' @param length.out The number of values, instead of `to`.
#' @return A zuint vector.
#' @examples
#' seq_zu(uint64("18446744073709551600"), uint64("18446744073709551614"), by = 7L)
#' seq_zu(int128(-2), by = int128("1000000000000000000000"), length.out = 3)
#' @export
seq_zu <- function(from, to = NULL, by = 1L, length.out = NULL) {
  call <- sys.call()
  args <- list(from, to, by)
  kinds <- vapply(args, function(a) if (is.null(a)) 0L else zu_kind(a), integer(1))
  zu_check_operands(kinds, args, call)
  code <- zu_common_code(kinds, call)
  wide <- if (code %in% c(1L, 3L)) 3L else 4L
  from <- zu_cast(from, code, call = call)
  by <- zu_cast(by, code, call = call)
  if (length(from) != 1L || length(by) != 1L || is.na(from) || is.na(by)) {
    zu_abort("`from` and `by` must be single non-missing values.", "type", call = call)
  }
  if (by == 0L) {
    zu_abort("`by` must not be zero.", "type", call = call)
  }
  if (is.null(length.out)) {
    to <- zu_cast(to, code, call = call)
    if (length(to) != 1L || is.na(to)) {
      zu_abort("`to` must be a single non-missing value.", "type", call = call)
    }
    if ((to - from > 0L && by < 0L) || (to < from && by > 0L)) {
      zu_abort("`by` goes the wrong way from `from` to `to`.", "type", call = call)
    }
    # in a wider type, so to - from cannot overflow
    span <- zu_cast(to, if (code == 4L) 4L else wide) - zu_cast(from, if (code == 4L) 4L else wide)
    if (code == 2L || code == 4L) {
      span <- if (to >= from) zu_cast(to, 4L) - zu_cast(from, 4L) else zu_cast(from, 4L) - zu_cast(to, 4L)
      step <- if (by > 0L) zu_cast(by, 4L) else -zu_cast(by, 4L)
    } else {
      step <- zu_cast(by, 3L)
    }
    length.out <- as.double(span %/% step) + 1
  }
  if (length.out > .Machine$integer.max) {
    zu_abort("The sequence is too long.", "type", call = call)
  }
  n <- as.integer(length.out)
  if (n == 0L) {
    return(from[0L])
  }
  from + by * zu_cast(seq_len(n) - 1L, code)
}
