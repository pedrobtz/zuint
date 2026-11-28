# The decimal128 class (design 2.2): DuckDB's DECIMAL(p, s) as an R vector.
# The payload is int128's, a CPLXSXP whose bits are the coefficient c, and
# the value is c / 10^s. Each vector has one precision and one scale, as a
# column does, in the integer attributes `precision` and `scale`. The C code
# ignores attributes, so the payload goes to it as it is; the structural
# methods go through an int128 view of the same payload.

dec_class <- c("zu_decimal128", "zu_decimal")

# Statuses of src/zu_fixed.h.
dec_ok <- 0L

#' Fixed-point decimal vectors
#'
#' `decimal128()` creates a vector of DuckDB's `DECIMAL(precision, scale)`:
#' numbers with at most `precision` digits, `scale` of them after the
#' point, held exactly as a 128-bit integer coefficient. A DuckDB `DECIMAL`
#' column, or one written to it, keeps every digit and its type.
#'
#' `x` can be text, a logical, integer or double vector, a zuint vector, a
#' bit64 `integer64` or another `decimal128`.
#'
#' * Text is read as DuckDB reads a `DECIMAL`: an optional sign, digits with
#'   an optional point, `_` between digits, an exponent, and surrounding
#'   whitespace; digits past the scale round half away from zero. `"NA"`
#'   and blank strings are `NA`.
#' * Integers and zuint vectors convert exactly.
#' * A double is rounded to the scale, half away from zero, as DuckDB's
#'   cast does: `decimal128(2.675, 5, 2)` is `2.68`.
#' * A `decimal128` of another type is rescaled, rounding half away from
#'   zero. Without `precision` or `scale` it keeps its own: `decimal128(x,
#'   20)` changes only the precision. With neither it is returned as it is.
#'
#' A value that does not fit `precision` digits becomes `NA` with a warning
#' of class `zuint_cast_warning`. Names are kept.
#'
#' Arithmetic follows DuckDB's types: `+` and `-` keep the larger scale
#' and grow the precision by one, `*` adds precisions and scales, and
#' `precision` stops at 38. As in DuckDB, a product of two operands of at
#' most 18 digits stops at 18 unless its scale is 18 or more. A result that
#' does not fit is `NA` with a `zuint_overflow_warning`. An integer operand
#' counts as `DECIMAL(10, 0)`, `int64` as `DECIMAL(19, 0)`, `uint64` as
#' `DECIMAL(20, 0)` and the 128-bit types as `DECIMAL(38, 0)`. A whole
#' double is an integer operand, typed as DuckDB types an integer literal;
#' any other double follows `options(zuint.double)`.
#'
#' Comparison is exact across scales, and with every integer and whole
#' double, even one too large for 38 digits. `/`, `%%`, `%/%` and `^`
#' compute in double, as do `mean()`, `median()`, `prod()` and the `Math`
#' functions other than those below; `!`, `&` and `|` give logicals.
#'
#' These keep a decimal type, DuckDB's:
#' * `abs()`, `cummax()` and `cummin()` keep the type, and `sum()` and
#'   `cumsum()` are `DECIMAL(38, scale)`.
#' * `round(x, digits)` rounds half away from zero to `DECIMAL(precision,
#'   digits)`, and is `x` when `digits` is the scale or more. A negative
#'   `digits` gives scale 0, with one more digit at scale 0.
#' * `floor()`, `ceiling()` and `trunc()` are `DECIMAL(precision, 0)`.
#'
#' `c()`, vctrs and `x[i] <- value` combine values in DuckDB's common type
#' (for `[<-`, `x`'s type): the largest scale and the most integer digits,
#' and the scale cut when both do not fit 38 digits. A value the type
#' cannot hold exactly is `NA` with a `zuint_cast_warning`; only
#' `decimal128()` rounds. `sum()`, `min()` and the other `Summary`
#' functions dispatch on their first argument, as R's group generics do, so
#' write `sum(x, 1L)`, not `sum(1L, x)`.
#'
#' @param x For `decimal128()`, a vector to convert; for `is_decimal128()`,
#'   any object; for `decimal_precision()` and `decimal_scale()`, a
#'   `decimal128` vector.
#' @param precision The number of digits, 1 to 38.
#' @param scale The number of digits after the point, 0 to `precision`.
#' @return `decimal128()` returns a `decimal128` vector the length of `x`.
#'   `is_decimal128()` returns `TRUE` or `FALSE`, and `decimal_precision()`
#'   and `decimal_scale()` a single integer.
#' @examples
#' price <- decimal128(c("19.99", "5.00", NA), 10, 2)
#' price
#' price * 3L
#' sum(price, na.rm = TRUE)
#' decimal_scale(price * price)
#'
#' # Too many digits, so NA with a warning:
#' decimal128("123.45", 4, 2)
#' @export
decimal128 <- function(x = character(), precision = 38L, scale = 0L) {
  call <- sys.call()
  if (is_decimal128(x)) {
    if (missing(precision) && missing(scale)) {
      return(x)
    }
    # what is not given stays x's: decimal128(x, 20) keeps the scale
    if (missing(precision)) {
      precision <- dec_p(x)
    }
    if (missing(scale)) {
      scale <- min(dec_s(x), precision)
    }
  }
  type <- dec_check_type(precision, scale, call)
  dec_cast(x, type[[1L]], type[[2L]], call)
}

#' @rdname decimal128
#' @export
is_decimal128 <- function(x) inherits(x, "zu_decimal128")

#' @rdname decimal128
#' @export
decimal_precision <- function(x) {
  dec_require(x, sys.call())
  dec_p(x)
}

#' @rdname decimal128
#' @export
decimal_scale <- function(x) {
  dec_require(x, sys.call())
  dec_s(x)
}

dec_require <- function(x, call) {
  if (!is_decimal128(x)) {
    zu_abort(
      sprintf("`x` must be a decimal128 vector, not %s.", zu_kind_label(x)),
      "type",
      call = call
    )
  }
}

dec_check_type <- function(precision, scale, call) {
  whole <- function(v) {
    is.numeric(v) &&
      !is.object(v) &&
      length(v) == 1L &&
      !is.na(v) &&
      v == trunc(v)
  }
  ok <- whole(precision) &&
    whole(scale) &&
    precision >= 1 &&
    precision <= 38 &&
    scale >= 0 &&
    scale <= precision
  if (!ok) {
    zu_abort(
      "`precision` must be a whole number from 1 to 38, and `scale` one from 0 to `precision`.",
      "type",
      call = call
    )
  }
  c(as.integer(precision), as.integer(scale))
}

dec_p <- function(x) attr(x, "precision", exact = TRUE)
dec_s <- function(x) attr(x, "scale", exact = TRUE)

dec_type_label <- function(p, s) sprintf("decimal128(%d, %d)", p, s)

# A payload (names allowed, nothing else) as DECIMAL(p, s).
dec_new <- function(payload, p, s) {
  attr(payload, "precision") <- p
  attr(payload, "scale") <- s
  oldClass(payload) <- dec_class
  payload
}

# The payload as an int128 vector, names kept, and back to x's type.
dec_view <- function(x) {
  v <- zu_unclass(x)
  oldClass(v) <- "zu_int128"
  v
}

dec_back <- function(v, like) dec_new(zu_unclass(v), dec_p(like), dec_s(like))

# The count of statuses that lost a value, NA statuses aside.
dec_lost <- function(status) sum(status != dec_ok, na.rm = TRUE)

dec_is_chr <- function(x) is.character(x) && !is.object(x)

# Text that is NA on purpose: NA, "NA", and blank in the core's whitespace,
# which is C's isspace() in the C locale.
dec_blank <- function(x) {
  t <- trimws(x, whitespace = "[ \t\n\v\f\r]")
  is.na(x) | t == "" | t == "NA"
}

# What a cast may lose: the values that are not NA on purpose.
dec_present <- function(x) {
  if (dec_is_chr(x)) !dec_blank(x) else !is.na(x)
}

# x as DECIMAL(p, s), names kept; lost values are NA with a warning
# reported against `call`.
dec_cast <- function(x, p, s, call) {
  nm <- names(x)
  extra <- 0
  if (is_decimal128(x)) {
    res <- .Call(zu_dec_rescale_c, x, dec_s(x), p, s)
  } else if (dec_is_chr(x)) {
    x[dec_blank(x)] <- NA_character_
    res <- .Call(zu_dec_parse_c, enc2utf8(x), p, s)
  } else if (zu_is_bare_double(x)) {
    res <- .Call(zu_dec_from_double_c, x, p, s)
  } else {
    kind <- zu_kind(x)
    if (is.na(kind) || kind < 0L) {
      zu_abort(
        sprintf(
          "Can't convert %s to %s.",
          zu_kind_label(x),
          dec_type_label(p, s)
        ),
        "type",
        call = call
      )
    }
    wide <- zu_convert(x, kind, 3L)
    extra <- wide[[2L]]
    res <- .Call(zu_dec_rescale_c, wide[[1L]], 0L, p, s)
  }
  zu_warn_lost(dec_lost(res[[2L]]) + extra, dec_type_label(p, s), call = call)
  out <- res[[1L]]
  names(out) <- nm
  dec_new(out, p, s)
}

# x as DECIMAL(p, s) without rounding, for c(): list(decimal, how many
# values were lost). A value the scale cannot hold exactly is NA. Text and
# doubles keep their own rules: they are what the user typed.
dec_cast_exact <- function(x, p, s, call) {
  if (!is_decimal128(x)) {
    out <- zu_quiet_cast(dec_cast(x, p, s, call))
    return(list(out, sum(dec_is_na(out) & dec_present(x))))
  }
  res <- .Call(zu_dec_rescale_c, x, dec_s(x), p, s)
  out <- res[[1L]]
  lost <- !is.na(res[[2L]]) & res[[2L]] != dec_ok
  if (s < dec_s(x)) {
    frac <- dec_changed(out, s, x, dec_s(x))
    out <- zu_fill_na(out, 3L, frac)
    lost <- lost | frac
  }
  names(out) <- names(x)
  list(dec_new(out, p, s), sum(lost))
}

# Where payload `r` at scale `s` is not the value of `x` at scale `sx`:
# the values a rescale rounded. NA on either side is not a change.
dec_changed <- function(r, s, x, sx) {
  same <- .Call(zu_dec_compare_c, r, s, zu_bare(x), sx) == 0L
  !is.na(same) & !same
}

# The values as an int128 payload when they are whole, and how many were
# not: rounded to scale 0 and scaled back, a value that changed had a
# fraction.
dec_to_int128 <- function(x) {
  s <- dec_s(x)
  r <- .Call(zu_dec_rescale_c, x, s, 38L, 0L)[[1L]]
  frac <- dec_changed(r, 0L, x, s)
  if (any(frac)) {
    r <- zu_fill_na(r, 3L, frac)
  }
  list(r, sum(frac))
}

# x to zuint type `code`: exact, or NA with a warning.
dec_to_zuint <- function(x, code, call) {
  r <- dec_to_int128(x)
  res <- zu_convert(r[[1L]], 3L, code)
  zu_warn_lost(r[[2L]] + res[[2L]], zu_types[[code]], call = call)
  out <- res[[1L]]
  names(out) <- names(x)
  zu_new(out, code)
}

# ---- the vector protocol -----------------------------------------------------

# generic = method. Registered for zu_decimal128 by dec_s3_registrations().
dec_methods <- c(
  "[" = "dec_subset",
  "[[" = "dec_subset2",
  "[<-" = "dec_subassign",
  "[[<-" = "dec_subassign2",
  "length<-" = "dec_set_length",
  c = "dec_c",
  rep = "dec_rep",
  rev = "zu_rev",
  is.na = "dec_is_na",
  "is.na<-" = "zu_set_na",
  anyNA = "dec_any_na",
  as.character = "dec_as_character",
  as.double = "dec_as_double",
  as.integer = "dec_as_integer",
  as.logical = "dec_as_logical",
  as.list = "zu_as_list",
  as.data.frame = "zu_as_data_frame",
  format = "dec_format",
  print = "dec_print",
  str = "dec_str",
  summary = "dec_summary",
  Ops = "dec_ops",
  Math = "dec_math",
  Summary = "dec_summary_group",
  mean = "dec_mean",
  median = "dec_median",
  sort = "dec_sort",
  xtfrm = "dec_xtfrm",
  unique = "dec_unique",
  duplicated = "dec_duplicated",
  anyDuplicated = "dec_any_duplicated",
  mtfrm = "dec_mtfrm",
  diff = "zu_diff",
  "utils::head" = "zu_head",
  "utils::tail" = "zu_tail",
  chooseOpsMethod = "zu_choose_ops_method",
  is.numeric = "zu_is_numeric",
  is.nan = "zu_is_nan",
  is.finite = "dec_is_finite",
  is.infinite = "zu_is_nan",
  as.complex = "dec_as_complex",
  all.equal = "dec_all_equal",
  seq = "zu_unsupported",
  as.raw = "zu_unsupported",
  as.Date = "zu_unsupported",
  as.POSIXct = "zu_unsupported",
  as.POSIXlt = "zu_unsupported",
  quantile = "zu_quantile",
  cbind = "zu_matrix_unsupported",
  rbind = "zu_matrix_unsupported",
  as.matrix = "zu_matrix_unsupported",
  aperm = "zu_matrix_unsupported",
  scale = "zu_matrix_unsupported",
  "%*%" = "zu_matrix_unsupported",
  crossprod = "zu_matrix_unsupported",
  tcrossprod = "zu_matrix_unsupported",
  Complex = "zu_complex_unsupported"
)

dec_s3_registrations <- function() {
  zu_s3_lines(names(dec_methods), "zu_decimal128", dec_methods)
}

#' @evalNamespace dec_s3_registrations()
NULL

dec_subset <- function(x, i, ...) dec_back(zu_subset(dec_view(x), i, ...), x)

dec_subset2 <- function(x, i, ...) dec_back(zu_subset2(dec_view(x), i, ...), x)

dec_subassign <- function(x, i, ..., value) {
  value <- dec_view(dec_assign_value(value, x, sys.call()))
  dec_back(zu_subassign(dec_view(x), i, ..., value = value), x)
}

dec_subassign2 <- function(x, i, ..., value) {
  value <- dec_view(dec_assign_value(value, x, sys.call()))
  dec_back(zu_subassign2(dec_view(x), i, ..., value = value), x)
}

# A value assigned into x takes x's type by the rules of c(): exact or NA
# with a warning, never rounded, and a double that is not whole follows
# zuint.double. Under "allow" it is rounded, since x can't become a double.
dec_assign_value <- function(value, x, call) {
  p <- dec_p(x)
  s <- dec_s(x)
  if (!dec_is_chr(value)) {
    op <- dec_operand(value, call, "assignment to a decimal128")
    if (is.null(op)) {
      zu_double_problem("decimal128", call)
      return(dec_cast(value, p, s, call))
    }
    value <- op$x
  }
  r <- dec_cast_exact(value, p, s, call)
  zu_warn_lost(r[[2L]], dec_type_label(p, s), call = call)
  r[[1L]]
}

dec_set_length <- function(x, value) {
  dec_back(zu_set_length(dec_view(x), value), x)
}

dec_rep <- function(x, ...) dec_back(zu_rep(dec_view(x), ...), x)

dec_is_na <- function(x) {
  out <- .Call(zu_is_na_c, x, 3L)
  names(out) <- names(x)
  out
}

dec_any_na <- function(x, recursive = FALSE) any(dec_is_na(x))

dec_is_finite <- function(x) !dec_is_na(x)

dec_as_character <- function(x, ...) {
  .Call(zu_dec_format_c, x, dec_p(x), dec_s(x))
}

# DuckDB's cast, correctly rounded. No warning: almost every fraction
# rounds, and a double was asked for.
dec_as_double <- function(x, ...) {
  .Call(zu_dec_to_double_c, x, dec_p(x), dec_s(x))
}

dec_as_integer <- function(x, ...) {
  r <- dec_to_int128(x)
  res <- .Call(zu_to_integer_c, r[[1L]], 3L)
  zu_warn_lost(r[[2L]] + res[[2L]], "integer", call = sys.call())
  res[[1L]]
}

dec_as_logical <- function(x, ...) zu_as_logical(dec_view(x))

dec_as_complex <- function(x, ...) as.complex(dec_as_double(x))

# match(), %in% and table() compare this text, so it must not depend on the
# scale: 1.0 and 1.00 are one value. Trailing zeros of the fraction go, and
# a whole value is the integer's text, as int128's mtfrm() writes it.
dec_mtfrm <- function(x) {
  out <- dec_as_character(x)
  if (dec_s(x) > 0L) {
    out <- sub("\\.?0*$", "", out)
    out <- sub("^(-?)\\.", "\\10.", out)
    out[out %in% c("", "-")] <- "0"
  }
  out
}

# As zu_format(): `justify` is accepted and numbers stay right-justified.
dec_format <- function(
  x,
  ...,
  width = 0L,
  big.mark = "",
  justify = "right",
  big.interval = 3L,
  zero.print = NULL,
  trim = FALSE
) {
  zu_format_text(
    dec_as_character(x),
    names(x),
    width,
    big.mark,
    big.interval,
    zero.print,
    trim
  )
}

# The header names the type even when x is empty: a zero-length decimal
# still has one.
dec_print <- function(x, ..., max = NULL) {
  cat("<", dec_type_label(dec_p(x), dec_s(x)), "[", length(x), "]>\n", sep = "")
  zu_print_values(x, dec_format, max, ...)
}

dec_str <- function(object, ..., vec.len = 4) {
  zu_str_line(
    object,
    dec_type_label(dec_p(object), dec_s(object)),
    dec_as_character,
    vec.len
  )
}

dec_summary <- function(object, ...) {
  keep <- object[!dec_is_na(object)]
  ends <- if (length(keep)) {
    dec_as_character(c(dec_extreme(keep, 1L), dec_extreme(keep, 2L)))
  } else {
    c(NA, NA)
  }
  out <- c(
    "Min." = ends[[1L]],
    "Median" = zu_format_double(dec_median(object, na.rm = TRUE)),
    "Mean" = zu_format_double(dec_mean(object, na.rm = TRUE)),
    "Max." = ends[[2L]]
  )
  n_na <- length(object) - length(keep)
  if (n_na > 0L) {
    out <- c(out, "NA's" = as.character(n_na))
  }
  out[is.na(out)] <- "NA"
  noquote(out)
}

dec_all_equal <- function(target, current, ...) {
  if (!is_decimal128(current)) {
    return(sprintf(
      "target is %s, current is %s",
      dec_type_label(dec_p(target), dec_s(target)),
      zu_kind_label(current)
    ))
  }
  if (dec_p(target) != dec_p(current) || dec_s(target) != dec_s(current)) {
    return(sprintf(
      "Types differ: %s vs %s",
      dec_type_label(dec_p(target), dec_s(target)),
      dec_type_label(dec_p(current), dec_s(current))
    ))
  }
  if (length(target) != length(current)) {
    return(sprintf("Lengths (%d, %d) differ", length(target), length(current)))
  }
  msg <- character()
  if (!identical(names(target), names(current))) {
    msg <- "names differ"
  }
  eq <- target == current
  differ <- sum(
    xor(dec_is_na(target), dec_is_na(current)) | (!is.na(eq) & !eq)
  )
  if (differ > 0) {
    msg <- c(msg, sprintf("%d of %d values differ", differ, length(target)))
  }
  if (length(msg)) msg else TRUE
}

# ---- types --------------------------------------------------------------------

# The DECIMAL(w, 0) DuckDB casts each integer kind to: R's integers and
# logicals as INTEGER, int64 as BIGINT, uint64 as UBIGINT, the 128-bit types
# as HUGEINT and UHUGEINT.
dec_int_width <- c(10L, 19L, 20L, 38L, 38L)

# An operand as list(x = a decimal128, p, s), or NULL for a double that is
# not whole (the caller applies zuint.double). A whole double is an
# integer operand, typed as DuckDB types an integer literal: INTEGER when
# every value fits one, BIGINT when every value fits that, else HUGEINT.
dec_operand <- function(x, call, what = "decimal arithmetic") {
  if (is_decimal128(x)) {
    return(list(x = x, p = dec_p(x), s = dec_s(x)))
  }
  if (zu_is_bare_double(x)) {
    v <- x[!is.na(x)]
    if (!all(is.finite(v) & v == trunc(v))) {
      return(NULL)
    }
    w <- if (all(abs(v) <= .Machine$integer.max)) {
      10L
    } else if (all(v >= -2^63 & v < 2^63)) {
      19L
    } else {
      38L
    }
    return(list(x = dec_cast(x, w, 0L, call), p = w, s = 0L))
  }
  kind <- zu_kind(x)
  if (is.na(kind) || kind < 0L) {
    zu_abort(
      sprintf("Can't use %s in %s.", zu_kind_label(x), what),
      "type",
      call = call
    )
  }
  w <- dec_int_width[[kind + 1L]]
  list(x = dec_cast(x, w, 0L, call), p = w, s = 0L)
}

# DuckDB's common type of two decimals: the largest scale and the most
# integer digits; past 38 digits the scale gives way.
dec_common2 <- function(a, b) {
  e <- max(a$p - a$s, b$p - b$s)
  s <- max(a$s, b$s)
  if (e + s > 38L) {
    s <- 38L - e
  }
  c(e + s, s)
}

# With an integer type the decimal's scale stays, and the precision stops
# at 38.
dec_common_int <- function(d, w) {
  c(min(38L, max(d$p - d$s, w) + d$s), d$s)
}

# The common type of operands from dec_operand(); `int` marks those that
# came from integers.
dec_common <- function(ops, int) {
  dec <- ops[!int]
  if (!length(dec)) {
    return(c(max(vapply(ops, function(o) o$p, integer(1))), 0L))
  }
  type <- c(dec[[1L]]$p, dec[[1L]]$s)
  for (o in dec[-1L]) {
    type <- dec_common2(list(p = type[[1L]], s = type[[2L]]), o)
  }
  for (o in ops[int]) {
    type <- dec_common_int(list(p = type[[1L]], s = type[[2L]]), o$p)
  }
  type
}

# ---- c() ----------------------------------------------------------------------

# Every argument takes DuckDB's common type. Text takes it as it is; a
# double that is not whole follows zuint.double, as in c() of the integers.
dec_c <- function(...) {
  args <- list(...)
  call <- sys.call()
  # c()'s own arguments are not data
  use_names <- !isFALSE(args[["use.names"]])
  if (!is.null(names(args))) {
    args <- args[!names(args) %in% c("use.names", "recursive")]
  }
  args <- args[!vapply(args, is.null, logical(1))]
  chr <- vapply(args, dec_is_chr, logical(1))
  ops <- vector("list", length(args))
  for (i in which(!chr)) {
    op <- dec_operand(args[[i]], call, "c() with a decimal128")
    if (is.null(op)) {
      zu_double_problem("decimal128", call)
      return(do.call(c, lapply(args, dec_dbl_quiet)))
    }
    ops[[i]] <- op
  }
  int <- !chr & !vapply(args, is_decimal128, logical(1))
  type <- dec_common(ops[!chr], int[!chr])
  lost <- 0
  parts <- vector("list", length(args))
  for (i in seq_along(args)) {
    v <- if (chr[[i]]) args[[i]] else ops[[i]]$x
    r <- dec_cast_exact(v, type[[1L]], type[[2L]], call)
    lost <- lost + r[[2L]]
    part <- zu_bare(r[[1L]])
    names(part) <- names(args[[i]])
    parts[[i]] <- part
  }
  zu_warn_lost(lost, dec_type_label(type[[1L]], type[[2L]]), call = call)
  names(parts) <- names(args)
  out <- do.call(c, parts)
  if (!use_names) {
    names(out) <- NULL
  }
  dec_new(out, type[[1L]], type[[2L]])
}

# The doubles a value stands for, names kept.
dec_dbl_quiet <- function(x) {
  out <- if (is_decimal128(x)) dec_as_double(x) else zu_dbl_quiet(x)
  names(out) <- names(x)
  out
}

# ---- Ops ------------------------------------------------------------------------

dec_ops <- function(e1, e2) {
  call <- sys.call()
  if (missing(e2)) {
    return(dec_unary(.Generic, e1, call))
  }
  dec_binary(.Generic, e1, e2, call)
}

dec_unary <- function(op, x, call) {
  if (!is_decimal128(x)) {
    zu_abort(
      sprintf("Can't use %s in decimal arithmetic.", zu_kind_label(x)),
      "type",
      call = call
    )
  }
  switch(
    op,
    "-" = {
      out <- .Call(zu_neg_c, zu_unclass(x), 3L, zu_policy_default)[[1L]]
      names(out) <- names(x)
      dec_new(out, dec_p(x), dec_s(x))
    },
    "+" = x,
    "!" = {
      out <- !dec_as_logical(x)
      names(out) <- names(x)
      out
    }
  )
}

dec_binary <- function(op, e1, e2, call) {
  switch(
    op,
    "+" = ,
    "-" = ,
    "*" = dec_arith(op, e1, e2, call),
    "/" = ,
    "%%" = ,
    "%/%" = ,
    "^" = dec_in_double(op, e1, e2, call, check = FALSE),
    "&" = ,
    "|" = {
      out <- get(op, baseenv())(dec_logical(e1), dec_logical(e2))
      names(out) <- zu_result_names(e1, e2, length(out))
      out
    },
    dec_compare(op, e1, e2, call)
  )
}

dec_logical <- function(x) {
  if (is_decimal128(x)) dec_as_logical(x) else as.logical(zu_from_bit64(x))
}

# The operation on the doubles each side stands for. With `check`, a double
# operand reached here because it was not whole: zuint.double decides.
dec_in_double <- function(op, e1, e2, call, check = TRUE) {
  for (v in list(e1, e2)) {
    if (!is_decimal128(v)) {
      kind <- zu_kind(v)
      if (is.na(kind) || kind == zu_kind_chr) {
        zu_abort(
          sprintf("Can't use %s in decimal arithmetic.", zu_kind_label(v)),
          "type",
          call = call
        )
      }
    }
  }
  if (check) {
    zu_double_problem("decimal128", call)
  }
  zu_check_recycling(e1, e2)
  out <- get(op, baseenv())(dec_dbl_quiet(e1), dec_dbl_quiet(e2))
  names(out) <- zu_result_names(e1, e2, length(out))
  out
}

# Both payloads recycled to the longer, as base arithmetic does.
dec_recycle <- function(a, b) {
  n <- if (length(a) == 0L || length(b) == 0L) 0L else max(length(a), length(b))
  list(rep_len(zu_bare(a), n), rep_len(zu_bare(b), n))
}

dec_arith <- function(op, e1, e2, call) {
  a <- dec_operand(e1, call)
  b <- dec_operand(e2, call)
  if (is.null(a) || is.null(b)) {
    return(dec_in_double(op, e1, e2, call))
  }
  zu_check_recycling(e1, e2)
  # recycled first, so that a value lost in the rescale is counted once
  # for each result it makes NA
  pp <- dec_recycle(a$x, b$x)
  lost <- 0
  if (op == "*") {
    p <- a$p + b$p
    s <- a$s + b$s
    # DuckDB multiplies two operands of 18 digits or fewer in 64 bits, and
    # caps the precision at 18 unless the scale is 18 or more
    p <- if (p > 18L && max(a$p, b$p) <= 18L && s < 18L) 18L else min(38L, p)
    if (s > 38L) {
      zu_abort(
        sprintf(
          "The product of %s and %s needs scale %d, and DECIMAL holds at most 38. Rescale an operand with decimal128() first.",
          dec_type_label(a$p, a$s),
          dec_type_label(b$p, b$s),
          s
        ),
        "incompatible",
        call = call
      )
    }
  } else {
    s <- max(a$s, b$s)
    p <- min(38L, max(a$p - a$s, b$p - b$s) + s + 1L)
    ra <- .Call(zu_dec_rescale_c, pp[[1L]], a$s, 38L, s)
    rb <- .Call(zu_dec_rescale_c, pp[[2L]], b$s, 38L, s)
    lost <- dec_lost(ra[[2L]]) + dec_lost(rb[[2L]])
    pp <- list(ra[[1L]], rb[[1L]])
  }
  r <- .Call(zu_dec_arith_c, match(op, c("+", "-", "*")), pp[[1L]], pp[[2L]])
  fit <- .Call(zu_dec_rescale_c, r[[1L]], s, p, s)
  # an operand lost in the rescale is NA in r, so it is counted once
  lost <- lost + dec_lost(r[[2L]]) + dec_lost(fit[[2L]])
  zu_report_overflow(lost, zu_policy_default, call)
  out <- fit[[1L]]
  names(out) <- zu_result_names(e1, e2, length(out))
  dec_new(out, p, s)
}

# An integer comparison operand as list(x = a decimal128, s, beyond):
# `beyond` is the sign of each value too large for 38 digits (0 for the
# others), which is then larger or smaller than every decimal.
dec_compare_operand <- function(x, call) {
  x <- zu_from_bit64(x)
  if (is_decimal128(x)) {
    return(list(x = x, s = dec_s(x), beyond = 0L))
  }
  kind <- zu_kind(x)
  if (is.na(kind) || kind < 0L) {
    zu_abort(
      sprintf("Can't use %s in a decimal comparison.", zu_kind_label(x)),
      "type",
      call = call
    )
  }
  d <- zu_quiet_cast(dec_cast(x, 38L, 0L, call))
  big <- dec_is_na(d) & !is.na(x)
  beyond <- integer(length(x))
  if (any(big)) {
    beyond[big] <- ifelse((x[big] > 0L) %in% TRUE, 1L, -1L)
  }
  list(x = d, s = 0L, beyond = beyond)
}

# Comparison is exact with every operand, doubles included, as for the
# integer types (design 5).
dec_compare <- function(op, e1, e2, call) {
  zu_check_recycling(e1, e2)
  if (zu_is_bare_double(e1) || zu_is_bare_double(e2)) {
    flip <- zu_is_bare_double(e1)
    d <- if (flip) e2 else e1
    pp <- dec_recycle(d, if (flip) e1 else e2)
    cmp <- dec_compare_double(pp[[1L]], dec_s(d), pp[[2L]])
    if (flip) {
      cmp <- -cmp
    }
  } else {
    a <- dec_compare_operand(e1, call)
    b <- dec_compare_operand(e2, call)
    pp <- dec_recycle(a$x, b$x)
    cmp <- .Call(zu_dec_compare_c, pp[[1L]], a$s, pp[[2L]], b$s)
    n <- length(cmp)
    # a value beyond 38 digits against a decimal: its sign is the answer,
    # unless the decimal is NA
    sides <- list(list(a$beyond, pp[[2L]], 1L), list(b$beyond, pp[[1L]], -1L))
    for (side in sides) {
      beyond <- rep_len(side[[1L]], n)
      at <- beyond != 0L & !.Call(zu_is_na_c, side[[2L]], 3L)
      cmp[at] <- side[[3L]] * as.integer(beyond[at])
    }
  }
  out <- switch(
    op,
    "==" = cmp == 0L,
    "!=" = cmp != 0L,
    "<" = cmp < 0L,
    "<=" = cmp <= 0L,
    ">" = cmp > 0L,
    ">=" = cmp >= 0L
  )
  names(out) <- zu_result_names(e1, e2, length(out))
  out
}

# The sign of d - v, exactly, for payload `c` at scale `s` and doubles `v`
# of the same length; NA where either is. Beyond 10^38 the sign of v
# decides. Below it the whole parts compare first, then the fractions:
# trunc() is monotone, and a fraction has its value's sign. A double's
# fraction is exact in its full decimal expansion, at most 1074 digits,
# which sprintf() writes.
dec_compare_double <- function(c, s, v) {
  out <- rep(NA_integer_, length(v))
  ok <- !.Call(zu_is_na_c, c, 3L) & !is.na(v)
  big <- ok & abs(v) >= 1e38
  out[big] <- -as.integer(sign(v[big]))
  rest <- ok & !big
  if (!any(rest)) {
    return(out)
  }
  v <- v[rest]
  d <- dec_new(c[rest], 38L, s)
  vi <- trunc(v)
  vf <- v - vi
  di <- dec_whole(d, "trunc")
  ci <- .Call(
    zu_dec_compare_c,
    zu_bare(di),
    0L,
    zu_bare(dec_cast(vi, 38L, 0L, NULL)),
    0L
  )
  # d's fraction at scale s, and v's cut to s digits with a flag for more
  dis <- .Call(zu_dec_rescale_c, di, 0L, 38L, s)[[1L]]
  df <- .Call(zu_dec_arith_c, 2L, zu_bare(d), dis)[[1L]]
  txt <- sprintf("%.1080f", abs(vf))
  more <- grepl("[1-9]", substring(txt, 3L + s))
  vfs <- if (s == 0L) {
    complex(length(v))
  } else {
    sgn <- ifelse(vf < 0, "-", "")
    frac <- paste0(sgn, "0.", substr(txt, 3L, 2L + s))
    zu_bare(dec_cast(frac, 38L, s, NULL))
  }
  cf <- .Call(zu_dec_compare_c, df, s, vfs, s)
  tie <- cf == 0L & more
  cf[tie] <- ifelse(vf[tie] > 0, -1L, 1L)
  out[rest] <- ifelse(ci != 0L, ci, cf)
  out
}

# ---- Math -----------------------------------------------------------------------

# abs(), the rounding functions and the cumulative sums, minima and maxima
# keep a decimal type, as DuckDB's do; the rest is computed on the doubles.
dec_math <- function(x, ...) {
  call <- sys.call()
  switch(
    .Generic,
    abs = {
      out <- .Call(zu_abs_sign_c, zu_unclass(x), 3L, FALSE)
      names(out) <- names(x)
      dec_new(out, dec_p(x), dec_s(x))
    },
    round = dec_round(x, ..., call = call),
    floor = ,
    ceiling = ,
    trunc = dec_whole(x, .Generic),
    cumsum = dec_cumsum(x, call),
    cummax = ,
    cummin = {
      what <- match(.Generic, c("cumsum", "cumprod", "cummax", "cummin"))
      out <- .Call(zu_cum_c, x, 3L, what)[[1L]]
      names(out) <- names(x)
      dec_new(out, dec_p(x), dec_s(x))
    },
    {
      out <- do.call(.Generic, list(dec_as_double(x), ...))
      names(out) <- names(x)
      out
    }
  )
}

# round(x, digits), half away from zero, in DuckDB's type: DECIMAL(p,
# digits) below the scale, x as it is at or above it. A negative `digits`
# gives scale 0, and at scale 0 one more digit (to 38) while -digits <= p:
# round(99, -2) is 100.
dec_round <- function(x, digits = 0, ..., call = NULL) {
  d <- zu_digits_arg(digits, call)
  p <- dec_p(x)
  s <- dec_s(x)
  if (d >= s) {
    return(x)
  }
  if (d >= 0L) {
    out <- .Call(zu_dec_rescale_c, x, s, p, d)[[1L]]
    names(out) <- names(x)
    return(dec_new(out, p, d))
  }
  k <- -d
  p_out <- if (s == 0L && k <= p) min(38L, p + 1L) else p
  if (s + k > 38L) {
    # |x| < 10^(38 - s) <= 10^(k - 1): every value rounds to zero
    out <- zu_fill_na(complex(length(x)), 3L, dec_is_na(x))
  } else {
    # the coefficient read at scale s + k, rounded to a whole number, then
    # scaled back up by 10^k
    r <- .Call(zu_dec_rescale_c, x, s + k, 38L, 0L)[[1L]]
    up <- .Call(zu_dec_rescale_c, r, 0L, 38L, k)
    fit <- .Call(zu_dec_rescale_c, up[[1L]], 0L, p_out, 0L)
    zu_report_overflow(
      dec_lost(up[[2L]]) + dec_lost(fit[[2L]]),
      zu_policy_default,
      call
    )
    out <- fit[[1L]]
  }
  names(out) <- names(x)
  dec_new(out, p_out, 0L)
}

# floor(), ceiling() and trunc() as DECIMAL(p, 0): the value rounded half
# away from zero, then moved one toward the direction asked where that went
# the wrong way.
dec_whole <- function(x, how) {
  s <- dec_s(x)
  if (s == 0L) {
    return(x)
  }
  r <- zu_new(.Call(zu_dec_rescale_c, x, s, 38L, 0L)[[1L]], 3L)
  cmp <- .Call(zu_dec_compare_c, zu_bare(r), 0L, zu_bare(x), s)
  pos <- (r > 0L) %in% TRUE
  neg <- (r < 0L) %in% TRUE
  down <- switch(
    how,
    floor = cmp > 0L,
    ceiling = rep(FALSE, length(cmp)),
    trunc = cmp > 0L & pos
  ) %in%
    TRUE
  up <- switch(
    how,
    floor = rep(FALSE, length(cmp)),
    ceiling = cmp < 0L,
    trunc = cmp < 0L & neg
  ) %in%
    TRUE
  r[down] <- r[down] - 1L
  r[up] <- r[up] + 1L
  out <- zu_unclass(r)
  names(out) <- names(x)
  dec_new(out, dec_p(x), 0L)
}

# cumsum() as DuckDB's running sum(): DECIMAL(38, s). From the first sum
# past 38 digits on, the sums are NA, as base cumsum() does after an
# overflow.
dec_cumsum <- function(x, call) {
  s <- dec_s(x)
  res <- .Call(zu_cum_c, x, 3L, 1L)
  fit <- .Call(zu_dec_rescale_c, res[[1L]], s, 38L, s)
  out <- fit[[1L]]
  bad <- which(!is.na(fit[[2L]]) & fit[[2L]] != dec_ok)
  lost <- res[[2L]]
  if (length(bad)) {
    after <- seq_along(out) >= bad[[1L]]
    lost <- lost + sum(after & !.Call(zu_is_na_c, res[[1L]], 3L))
    out <- zu_fill_na(out, 3L, after)
  }
  zu_report_overflow(lost, zu_policy_default, call)
  names(out) <- names(x)
  dec_new(out, 38L, s)
}

# ---- ordering, hashing, summaries -----------------------------------------------

# zu_match() with a decimal on either side: by value, through the text
# mtfrm() gives, which does not depend on the scale; a double's is its exact
# value's. A value that can't be a decimal matches nothing, as in zu_match()
# of the integers (#58).
# The exact value of each double as mtfrm() writes a decimal's: every digit
# of its full expansion, then no trailing zeros. 0.1 is not "0.1".
dec_double_key <- function(v) {
  out <- sprintf("%.1080f", v)
  out <- sub("\\.?0*$", "", out)
  out[out == "-0"] <- "0"
  out[is.na(v)] <- NA_character_
  out[is.infinite(v)] <- "Inf"
  out
}

dec_match <- function(x, table, nomatch, call) {
  key <- function(v) {
    if (is_decimal128(v)) {
      return(dec_mtfrm(v))
    }
    if (dec_is_chr(v)) {
      zu_abort(
        sprintf("Can't use %s in zu_match().", zu_kind_label(v)),
        "type",
        call = call
      )
    }
    if (zu_is_bare_double(v)) {
      return(dec_double_key(v))
    }
    dec_mtfrm(zu_quiet_cast(dec_operand(v, call, "zu_match()"))$x)
  }
  kx <- key(x)
  kt <- key(table)
  # a table value lost in the cast must not match x's NA
  kt[is.na(kt) & !is.na(table)] <- "lost"
  res <- match(kx, kt, nomatch)
  res[is.na(kx) & !is.na(x)] <- nomatch
  res
}

# The coefficients share one scale, so int128's code orders and hashes them.

dec_sort <- function(
  x,
  decreasing = FALSE,
  na.last = NA,
  index.return = FALSE,
  partial = NULL,
  ...
) {
  res <- zu_sort(
    dec_view(x),
    decreasing = decreasing,
    na.last = na.last,
    index.return = index.return,
    partial = partial
  )
  if (is.list(res)) {
    res$x <- dec_back(res$x, x)
    return(res)
  }
  dec_back(res, x)
}

dec_xtfrm <- function(x) .Call(zu_rank_c, x, 3L)

dec_duplicated <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  fromLast <- zu_flag(fromLast, "fromLast", sys.call())
  d <- .Call(zu_duplicated_c, x, 3L, fromLast)
  inc <- zu_incomparable(x, incomparables, sys.call())
  if (!is.null(inc)) {
    d[inc] <- FALSE
  }
  d
}

dec_unique <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  if (!isFALSE(incomparables)) {
    out <- x[
      !dec_duplicated(x, incomparables = incomparables, fromLast = fromLast)
    ]
    names(out) <- NULL
    return(out)
  }
  dec_back(zu_unique(dec_view(x), fromLast = fromLast), x)
}

dec_any_duplicated <- function(
  x,
  incomparables = FALSE,
  fromLast = FALSE,
  ...
) {
  fromLast <- zu_flag(fromLast, "fromLast", sys.call())
  d <- dec_duplicated(x, incomparables = incomparables, fromLast = fromLast)
  if (any(d)) which(d)[[if (fromLast) sum(d) else 1L]] else 0L
}

# The exact mean of the values, rounded once: DuckDB's avg() is a double,
# within an ulp or two of it (design 2.2).
dec_mean <- function(x, trim = 0, na.rm = FALSE, ...) {
  na.rm <- zu_flag(na.rm, "na.rm", sys.call())
  if (!identical(trim, 0) && !identical(trim, 0L)) {
    zu_abort(
      "mean() with `trim` is not supported for zuint vectors.",
      "unsupported",
      call = sys.call()
    )
  }
  zu_mean_scaled(dec_view(x), na.rm, dec_s(x))
}

dec_median <- function(x, na.rm = FALSE, ...) {
  na.rm <- zu_flag(na.rm, "na.rm", sys.call())
  zu_median_scaled(dec_view(x), na.rm, dec_s(x))
}

# min() or max() of values that are not all NA.
dec_extreme <- function(x, which) {
  r <- .Call(zu_range_c, x, 3L, TRUE)
  dec_new(r[which], dec_p(x), dec_s(x))
}

dec_summary_group <- function(..., na.rm = FALSE) {
  call <- sys.call()
  a <- zu_summary_args(list(...), .Generic, na.rm)
  na.rm <- a$na.rm
  x <- if (length(a$args) == 1L) a$args[[1L]] else do.call(dec_c, a$args)
  if (!is_decimal128(x)) {
    # c() fell back to double under options(zuint.double = "allow")
    return(zu_summary_double(x, .Generic, na.rm, a$finite))
  }
  switch(
    .Generic,
    sum = dec_sum(x, na.rm, call),
    prod = prod(dec_as_double(x), na.rm = na.rm),
    min = dec_min_max(x, na.rm, 1L, call),
    max = dec_min_max(x, na.rm, 2L, call),
    range = {
      lo <- dec_min_max(x, na.rm, 1L, call)
      hi <- dec_min_max(x, na.rm, 2L, call)
      if (is_decimal128(lo)) dec_c(lo, hi) else c(lo, hi)
    },
    any = any(dec_as_logical(x), na.rm = na.rm),
    all = all(dec_as_logical(x), na.rm = na.rm)
  )
}

# DECIMAL(38, s), as DuckDB's sum(); past 38 digits NA with a warning.
dec_sum <- function(x, na.rm, call) {
  s <- dec_s(x)
  res <- .Call(zu_sum_c, x, 3L, na.rm)
  fit <- .Call(zu_dec_rescale_c, res[[1L]], s, 38L, s)
  zu_report_overflow(res[[2L]] + dec_lost(fit[[2L]]), zu_policy_default, call)
  dec_new(fit[[1L]], 38L, s)
}

dec_min_max <- function(x, na.rm, which, call) {
  out <- zu_extreme(dec_view(x), 3L, na.rm, which, call)
  if (is.double(out)) out else dec_back(out, x)
}
