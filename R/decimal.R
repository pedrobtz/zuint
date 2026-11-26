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
#'   zero. With neither `precision` nor `scale` given it is returned as it
#'   is.
#'
#' A value that does not fit `precision` digits becomes `NA` with a warning
#' of class `zuint_cast_warning`. Names are kept.
#'
#' Arithmetic follows DuckDB's types: `+` and `-` keep the larger scale
#' and grow the precision by one, `*` adds precisions and scales, and
#' `precision` stops at 38. As in DuckDB, a product of two operands of at
#' most 18 digits stops at 18 unless its scale is 18 or more. A result that does not fit is `NA` with a
#' `zuint_overflow_warning`. An integer operand counts as
#' `DECIMAL(10, 0)`, `int64` as `DECIMAL(19, 0)`, `uint64` as
#' `DECIMAL(20, 0)` and the 128-bit types as `DECIMAL(38, 0)`; a whole
#' double is an integer operand, and any other double follows
#' `options(zuint.double)`. Comparison is exact across scales. `/`, `%%`,
#' `%/%`, `^` and the `Math` functions other than `abs()` compute in double,
#' as does `mean()`; `sum()` is a `DECIMAL(38, scale)`.
#'
#' `c()` and vctrs combine vectors in DuckDB's common type: the largest
#' scale and the most integer digits, and the scale cut when both do not
#' fit 38 digits. A value the common type cannot hold exactly is `NA` with
#' a `zuint_cast_warning`.
#'
#' @param x A vector to convert.
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
  if (is_decimal128(x) && missing(precision) && missing(scale)) {
    return(x)
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

# x as DECIMAL(p, s), names kept; lost values are NA with a warning
# reported against `call`.
dec_cast <- function(x, p, s, call) {
  nm <- names(x)
  extra <- 0
  if (is_decimal128(x)) {
    res <- .Call(zu_dec_rescale_c, x, dec_s(x), p, s)
  } else if (is.character(x) && !is.object(x)) {
    blank <- is.na(x) | x == "NA" | !nzchar(trimws(x))
    x[blank] <- NA_character_
    res <- .Call(zu_dec_parse_c, enc2utf8(x), p, s)
  } else if (is.double(x) && !is.object(x)) {
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
    out <- withCallingHandlers(
      dec_cast(x, p, s, call),
      zuint_cast_warning = function(w) invokeRestart("muffleWarning")
    )
    return(list(out, sum(dec_is_na(out) & !is.na(x))))
  }
  res <- .Call(zu_dec_rescale_c, x, dec_s(x), p, s)
  out <- res[[1L]]
  lost <- !is.na(res[[2L]]) & res[[2L]] != dec_ok
  if (s < dec_s(x)) {
    same <- .Call(zu_dec_compare_c, out, s, zu_bare(x), dec_s(x)) == 0L
    frac <- !is.na(same) & !same
    out <- zu_fill_na(out, 3L, frac)
    lost <- lost | frac
  }
  names(out) <- names(x)
  list(dec_new(out, p, s), sum(lost))
}

# The values as an int128 payload when they are whole, and how many were
# not: rounded to scale 0 and scaled back, a value that changed had a
# fraction.
dec_to_int128 <- function(x) {
  s <- dec_s(x)
  r <- .Call(zu_dec_rescale_c, x, s, 38L, 0L)[[1L]]
  back <- .Call(zu_dec_rescale_c, r, 0L, 38L, s)[[1L]]
  same <- .Call(zu_dec_compare_c, back, s, zu_bare(x), s) == 0L
  frac <- !is.na(same) & !same
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
  scale = "zu_matrix_unsupported"
)

dec_s3_registrations <- function() {
  sprintf('S3method("%s", zu_decimal128, %s)', names(dec_methods), dec_methods)
}

#' @evalNamespace dec_s3_registrations()
NULL

dec_subset <- function(x, i, ...) dec_back(zu_subset(dec_view(x), i, ...), x)

dec_subset2 <- function(x, i, ...) dec_back(zu_subset2(dec_view(x), i, ...), x)

dec_subassign <- function(x, i, ..., value) {
  value <- dec_view(dec_cast(value, dec_p(x), dec_s(x), sys.call()))
  dec_back(zu_subassign(dec_view(x), i, ..., value = value), x)
}

dec_subassign2 <- function(x, i, ..., value) {
  value <- dec_view(dec_cast(value, dec_p(x), dec_s(x), sys.call()))
  dec_back(zu_subassign2(dec_view(x), i, ..., value = value), x)
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

dec_mtfrm <- function(x) dec_as_character(x)

dec_format <- function(x, ..., width = 0L, big.mark = "", justify = "right") {
  s <- dec_as_character(x)
  na <- is.na(s)
  if (nzchar(big.mark)) {
    s[!na] <- prettyNum(s[!na], big.mark = big.mark, preserve.width = "none")
  }
  s[na] <- "NA"
  out <- formatC(s, width = max(width, nchar(s, "width"), 0L))
  names(out) <- names(x)
  out
}

dec_print <- function(x, ..., max = NULL) {
  n <- length(x)
  cat("<", dec_type_label(dec_p(x), dec_s(x)), "[", n, "]>\n", sep = "")
  if (n == 0L) {
    return(invisible(x))
  }
  max <- if (is.null(max)) getOption("max.print", 99999L) else max
  shown <- if (n > max) x[seq_len(max)] else x
  print(dec_format(shown), quote = FALSE, ...)
  if (n > max) {
    cat(
      " [ reached 'max' / getOption(\"max.print\") -- omitted",
      n - max,
      "entries ]\n"
    )
  }
  invisible(x)
}

dec_str <- function(object, ..., vec.len = 4) {
  n <- length(object)
  shown <- object[seq_len(min(n, max(1L, round(2.5 * vec.len))))]
  vals <- dec_as_character(shown)
  vals[is.na(vals)] <- "NA"
  cat(
    " ",
    dec_type_label(dec_p(object), dec_s(object)),
    " ",
    if (n == 1L) "" else paste0("[1:", n, "] "),
    paste(vals, collapse = " "),
    if (length(shown) < n) " ...",
    "\n",
    sep = ""
  )
  invisible()
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
    "Mean" = format(dec_mean(object, na.rm = TRUE), digits = 15L),
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
# integer operand: INTEGER when every value fits one, as DuckDB types an
# integer literal, else BIGINT.
dec_operand <- function(x, call, what = "decimal arithmetic") {
  if (is_decimal128(x)) {
    return(list(x = x, p = dec_p(x), s = dec_s(x)))
  }
  if (is.double(x) && !is.object(x)) {
    v <- x[!is.na(x)]
    if (!all(is.finite(v) & v == trunc(v) & abs(v) < 2^63)) {
      return(NULL)
    }
    w <- if (all(abs(v) <= .Machine$integer.max)) 10L else 19L
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
    return(c(max(vapply(ops, function(o) o$p, 1L)), 0L))
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
  args <- args[!vapply(args, is.null, logical(1))]
  chr <- vapply(args, function(a) is.character(a) && !is.object(a), logical(1))
  ops <- vector("list", length(args))
  for (i in which(!chr)) {
    op <- dec_operand(args[[i]], call, "c() with a decimal128")
    if (is.null(op)) {
      zu_double_problem("decimal128", call)
      return(unlist(lapply(unname(args), dec_dbl_quiet)))
    }
    ops[[i]] <- op
  }
  int <- vapply(
    seq_along(args),
    function(i) !chr[[i]] && !is_decimal128(args[[i]]),
    logical(1)
  )
  type <- dec_common(ops[!chr], int[!chr])
  lost <- 0
  parts <- lapply(seq_along(args), function(i) {
    v <- if (chr[[i]]) args[[i]] else ops[[i]]$x
    r <- dec_cast_exact(v, type[[1L]], type[[2L]], call)
    lost <<- lost + r[[2L]]
    out <- zu_bare(r[[1L]])
    names(out) <- names(args[[i]])
    out
  })
  zu_warn_lost(lost, dec_type_label(type[[1L]], type[[2L]]), call = call)
  names(parts) <- names(args)
  dec_new(do.call(c, parts), type[[1L]], type[[2L]])
}

dec_dbl_quiet <- function(x) {
  if (is_decimal128(x)) dec_as_double(x) else zu_dbl_quiet(x)
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
    "|" = get(op, baseenv())(dec_logical(e1), dec_logical(e2)),
    dec_compare(op, e1, e2, call)
  )
}

dec_logical <- function(x) {
  if (is_decimal128(x)) dec_as_logical(x) else as.logical(x)
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
    pa <- a$x
    pb <- b$x
  } else {
    s <- max(a$s, b$s)
    p <- min(38L, max(a$p - a$s, b$p - b$s) + s + 1L)
    ra <- .Call(zu_dec_rescale_c, a$x, a$s, 38L, s)
    rb <- .Call(zu_dec_rescale_c, b$x, b$s, 38L, s)
    lost <- dec_lost(ra[[2L]]) + dec_lost(rb[[2L]])
    pa <- ra[[1L]]
    pb <- rb[[1L]]
  }
  pp <- dec_recycle(pa, pb)
  r <- .Call(zu_dec_arith_c, match(op, c("+", "-", "*")), pp[[1L]], pp[[2L]])
  fit <- .Call(zu_dec_rescale_c, r[[1L]], s, p, s)
  # an operand lost in the rescale is NA in r, so it is counted once
  lost <- lost + dec_lost(r[[2L]]) + dec_lost(fit[[2L]])
  zu_report_overflow(lost, zu_policy_default, call)
  out <- fit[[1L]]
  names(out) <- zu_result_names(e1, e2, length(out))
  dec_new(out, p, s)
}

dec_compare <- function(op, e1, e2, call) {
  a <- dec_operand(e1, call, "a decimal comparison")
  b <- dec_operand(e2, call, "a decimal comparison")
  if (is.null(a) || is.null(b)) {
    return(dec_in_double(op, e1, e2, call))
  }
  zu_check_recycling(e1, e2)
  pp <- dec_recycle(a$x, b$x)
  cmp <- .Call(zu_dec_compare_c, pp[[1L]], a$s, pp[[2L]], b$s)
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

# abs() keeps the type, as DuckDB's does; the rest is computed on the
# doubles.
dec_math <- function(x, ...) {
  if (.Generic == "abs") {
    out <- .Call(zu_abs_sign_c, zu_unclass(x), 3L, FALSE)
    names(out) <- names(x)
    return(dec_new(out, dec_p(x), dec_s(x)))
  }
  out <- do.call(.Generic, list(dec_as_double(x), ...))
  names(out) <- names(x)
  out
}

# ---- ordering, hashing, summaries -----------------------------------------------

# The coefficients share one scale, so int128's code orders and hashes them.

dec_sort <- function(x, decreasing = FALSE, na.last = NA, ...) {
  dec_back(zu_sort(dec_view(x), decreasing = decreasing, na.last = na.last), x)
}

dec_xtfrm <- function(x) .Call(zu_rank_c, x, 3L)

dec_duplicated <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  .Call(zu_duplicated_c, x, 3L, isTRUE(fromLast))
}

dec_unique <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
  dec_back(zu_unique(dec_view(x), fromLast = fromLast), x)
}

dec_any_duplicated <- function(
  x,
  incomparables = FALSE,
  fromLast = FALSE,
  ...
) {
  d <- dec_duplicated(x, fromLast = fromLast)
  if (any(d)) which(d)[[if (fromLast) sum(d) else 1L]] else 0L
}

# The mean of the coefficients, then the scale: DuckDB's avg() is a double.
dec_mean <- function(x, trim = 0, na.rm = FALSE, ...) {
  zu_mean(dec_view(x), trim = trim, na.rm = na.rm) / 10^dec_s(x)
}

dec_median <- function(x, na.rm = FALSE, ...) {
  zu_median(dec_view(x), na.rm = na.rm) / 10^dec_s(x)
}

# min() or max() of values that are not all NA.
dec_extreme <- function(x, which) {
  r <- .Call(zu_range_c, x, 3L, TRUE)
  dec_new(r[which], dec_p(x), dec_s(x))
}

dec_summary_group <- function(..., na.rm = FALSE) {
  call <- sys.call()
  args <- list(...)
  finite <- FALSE
  if (.Generic == "range" && "finite" %in% names(args)) {
    finite <- isTRUE(args[["finite"]])
    args[names(args) == "finite"] <- NULL
    na.rm <- na.rm || finite
  }
  x <- if (length(args) == 1L) args[[1L]] else do.call(dec_c, args)
  if (!is_decimal128(x)) {
    # c() fell back to double under options(zuint.double = "allow")
    if (.Generic == "range") {
      return(range(x, na.rm = na.rm, finite = finite))
    }
    return(get(.Generic, baseenv())(x, na.rm = na.rm))
  }
  switch(
    .Generic,
    sum = dec_sum(x, na.rm, call),
    prod = prod(dec_as_double(x), na.rm = na.rm),
    min = dec_min_max(x, na.rm, 1L),
    max = dec_min_max(x, na.rm, 2L),
    range = {
      lo <- dec_min_max(x, na.rm, 1L)
      hi <- dec_min_max(x, na.rm, 2L)
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

dec_min_max <- function(x, na.rm, which) {
  out <- zu_extreme(dec_view(x), 3L, na.rm, which, sys.call(-1L))
  if (is.double(out)) out else dec_back(out, x)
}
