# vctrs and pillar methods (design 9.2), registered when those packages
# load. The equality and ordering proxy is a data frame of exact 32-bit
# pieces: the payload itself would not do, because vctrs treats every NaN
# bit pattern as one value and many int64 values are NaN patterns.

zu_register_vctrs <- function(...) {
  ns <- asNamespace("vctrs")
  reg <- function(generic, cls, fun) {
    registerS3method(generic, cls, fun, envir = ns)
  }
  others <- c("integer", "logical", "double", "integer64")
  for (cl in zu_classes_all) {
    reg("vec_cast", paste0("double.", cl), zu_vec_cast_base)
    reg("vec_cast", paste0("integer.", cl), zu_vec_cast_base)
    reg("vec_proxy", cl, zu_vec_proxy)
    reg("vec_restore", cl, zu_vec_restore)
    reg("vec_proxy_equal", cl, zu_vec_proxy_pieces)
    reg("vec_proxy_compare", cl, zu_vec_proxy_pieces)
    reg("vec_proxy_order", cl, zu_vec_proxy_pieces)
    reg("vec_ptype_abbr", cl, zu_vec_ptype_abbr)
    reg("vec_ptype_full", cl, zu_vec_ptype_full)
    for (cl2 in c(zu_classes_all, others)) {
      reg("vec_ptype2", paste0(cl, ".", cl2), zu_vec_ptype2)
      reg("vec_cast", paste0(cl, ".", cl2), zu_vec_cast)
    }
    for (cl2 in others) {
      reg("vec_ptype2", paste0(cl2, ".", cl), zu_vec_ptype2)
    }
  }
  dec <- "zu_decimal128"
  reg("vec_proxy", dec, zu_vec_proxy)
  reg("vec_restore", dec, dec_vec_restore)
  reg("vec_proxy_equal", dec, dec_vec_proxy_pieces)
  reg("vec_proxy_compare", dec, dec_vec_proxy_pieces)
  reg("vec_proxy_order", dec, dec_vec_proxy_pieces)
  reg("vec_ptype_abbr", dec, dec_vec_ptype_abbr)
  reg("vec_ptype_full", dec, dec_vec_ptype_full)
  reg("vec_cast", paste0("double.", dec), dec_vec_cast_base)
  reg("vec_cast", paste0("integer.", dec), dec_vec_cast_base)
  for (cl2 in c(dec, zu_classes_all, others)) {
    reg("vec_ptype2", paste0(dec, ".", cl2), dec_vec_ptype2)
    reg("vec_cast", paste0(dec, ".", cl2), dec_vec_cast)
    if (cl2 != dec) {
      reg("vec_ptype2", paste0(cl2, ".", dec), dec_vec_ptype2)
    }
  }
  for (cl in zu_classes_all) {
    reg("vec_cast", paste0(cl, ".", dec), dec_vec_cast_zuint)
  }
}

zu_register_pillar <- function(...) {
  ns <- asNamespace("pillar")
  for (cl in zu_classes_all) {
    registerS3method("pillar_shaft", cl, zu_pillar_shaft, envir = ns)
    registerS3method("type_sum", cl, zu_vec_ptype_abbr, envir = ns)
  }
  registerS3method(
    "pillar_shaft",
    "zu_decimal128",
    dec_pillar_shaft,
    envir = ns
  )
  registerS3method("type_sum", "zu_decimal128", dec_type_sum, envir = ns)
}

# The proxy is the payload beside a flag that is TRUE for every real row.
# vctrs fills the slots it creates (vec_init(), padding, unmatched join rows,
# an NA index) with its own NA in every column; the payload's NA_real_ or
# NA_complex_ bits are a valid value here, so the flag, which is never NA for
# a real row, is what says the slot is missing.
# vctrs takes a data-frame proxy's names from its row names, which cannot
# hold repeated or empty names, so vctrs operations drop the names of a zuint
# vector, as they do for vctrs' own records. Every proxy must have the same
# columns, so names cannot ride along as a column either.
zu_vec_proxy <- function(x, ...) {
  structure(
    list(bits = zu_bare(x), real = rep(TRUE, length(x))),
    row.names = c(NA, -length(x)),
    class = "data.frame"
  )
}

zu_vec_restore <- function(x, to, ...) {
  code <- zu_code(to)
  if (!is.data.frame(x)) {
    return(zu_new(x, code))
  }
  zu_new(zu_fill_na(x$bits, code, is.na(x$real)), code)
}

zu_vec_proxy_pieces <- function(x, ...) {
  cols <- .Call(zu_pieces_c, x, zu_code(x))
  names(cols) <- paste0("w", seq_along(cols))
  structure(cols, row.names = c(NA, -length(x)), class = "data.frame")
}

zu_abbr <- c("i64", "u64", "i128", "u128")

zu_vec_ptype_abbr <- function(x, ...) zu_abbr[[zu_code(x)]]

zu_vec_ptype_full <- function(x, ...) zu_types[[zu_code(x)]]

# The common type, by the promotion order; doubles adopt the zuint type and
# are checked when cast.
zu_vec_ptype2 <- function(x, y, ..., x_arg = "", y_arg = "") {
  kinds <- c(zu_kind(x), zu_kind(y))
  kinds[kinds == zu_kind_dbl] <- 0L
  code <- zu_common2(kinds[[1L]], kinds[[2L]])
  if (is.na(code)) {
    vctrs::stop_incompatible_type(x, y, x_arg = x_arg, y_arg = y_arg)
  }
  zu_new(zu_alloc_empty(code), code)
}

# x as the type of `to`; a value that does not convert exactly is a lossy
# cast error, as vctrs casts are.
zu_vec_cast <- function(x, to, ..., x_arg = "", to_arg = "") {
  x <- zu_from_bit64(x)
  code <- zu_code(to)
  out <- zu_quiet_cast(zu_cast(x, code))
  lossy <- zu_is_na(out) & !is.na(x)
  if (any(lossy)) {
    return(vctrs::maybe_lossy_cast(
      out,
      x,
      to,
      lossy = lossy,
      x_arg = x_arg,
      to_arg = to_arg
    ))
  }
  out
}

# A zuint vector to double or integer: exact, or vctrs' lossy-cast error.
zu_vec_cast_base <- function(x, to, ..., x_arg = "", to_arg = "") {
  res <- if (is.double(to)) {
    .Call(zu_to_double_c, x, zu_code(x))
  } else {
    .Call(zu_to_integer_c, x, zu_code(x))
  }
  out <- res[[1L]]
  if (res[[2L]] > 0) {
    # a rounded double casts back to a different value; a lost integer is NA
    back <- zu_quiet_cast(zu_cast(out, zu_code(x)))
    lossy <- !zu_is_na(x) & (is.na(out) | !(back == x) %in% TRUE)
    return(vctrs::maybe_lossy_cast(
      out,
      x,
      to,
      lossy = lossy,
      x_arg = x_arg,
      to_arg = to_arg
    ))
  }
  out
}

# ---- decimal128 ---------------------------------------------------------------

dec_vec_ptype_abbr <- function(x, ...) "dec"

dec_vec_ptype_full <- function(x, ...) dec_type_label(dec_p(x), dec_s(x))

dec_type_sum <- function(x) sprintf("dec(%d,%d)", dec_p(x), dec_s(x))

# The payload is int128's, so its proxy is too; the type comes back from `to`.
dec_vec_restore <- function(x, to, ...) {
  if (!is.data.frame(x)) {
    return(dec_new(zu_unclass(x), dec_p(to), dec_s(to)))
  }
  dec_new(zu_fill_na(x$bits, 3L, is.na(x$real)), dec_p(to), dec_s(to))
}

# One scale per vector, and vctrs casts both sides to the common type before
# it compares, so the coefficients' order is the values'.
dec_vec_proxy_pieces <- function(x, ...) {
  cols <- .Call(zu_pieces_c, x, 3L)
  names(cols) <- paste0("w", seq_along(cols))
  structure(cols, row.names = c(NA, -length(x)), class = "data.frame")
}

# DuckDB's common type. A double counts as INTEGER, as DuckDB types an
# integer literal and c() a double of int32 values: vctrs types prototypes,
# not values, so a larger double is then a lossy cast, not a wider type.
dec_vec_ptype2 <- function(x, y, ..., x_arg = "", y_arg = "") {
  sides <- list(x, y)
  ops <- lapply(sides, function(v) {
    if (zu_is_bare_double(v)) {
      list(p = 10L, s = 0L)
    } else {
      dec_operand(v[0L], NULL)
    }
  })
  type <- dec_common(ops, !vapply(sides, is_decimal128, logical(1)))
  dec_new(complex(), type[[1L]], type[[2L]])
}

# x as the type of `to`. A cast that rounds is lossy, like one that loses a
# value: vctrs casts must be exact.
dec_vec_cast <- function(x, to, ..., x_arg = "", to_arg = "") {
  x <- zu_from_bit64(x)
  out <- zu_quiet_cast(dec_cast(x, dec_p(to), dec_s(to), NULL))
  lost <- dec_is_na(out) & !is.na(x)
  changed <- if (is_decimal128(x)) {
    !(out == x) %in% TRUE
  } else if (is.double(x)) {
    !(dec_as_double(out) == x) %in% TRUE
  } else {
    FALSE
  }
  lossy <- lost | (!dec_is_na(out) & changed)
  if (any(lossy)) {
    return(vctrs::maybe_lossy_cast(
      out,
      x,
      to,
      lossy = lossy,
      x_arg = x_arg,
      to_arg = to_arg
    ))
  }
  out
}

# A decimal to a zuint integer type, to integer or to double.
dec_vec_cast_zuint <- function(x, to, ..., x_arg = "", to_arg = "") {
  out <- zu_quiet_cast(dec_to_zuint(x, zu_code(to), NULL))
  lossy <- zu_is_na(out) & !dec_is_na(x)
  if (any(lossy)) {
    return(vctrs::maybe_lossy_cast(
      out,
      x,
      to,
      lossy = lossy,
      x_arg = x_arg,
      to_arg = to_arg
    ))
  }
  out
}

dec_vec_cast_base <- function(x, to, ..., x_arg = "", to_arg = "") {
  if (is.double(to)) {
    out <- dec_as_double(x)
    back <- zu_quiet_cast(dec_cast(out, dec_p(x), dec_s(x), NULL))
    lossy <- !dec_is_na(x) & !(back == x) %in% TRUE
  } else {
    out <- zu_quiet_cast(dec_as_integer(x))
    lossy <- !dec_is_na(x) & is.na(out)
  }
  if (any(lossy)) {
    return(vctrs::maybe_lossy_cast(
      out,
      x,
      to,
      lossy = lossy,
      x_arg = x_arg,
      to_arg = to_arg
    ))
  }
  out
}

dec_pillar_shaft <- function(x, ...) {
  out <- dec_as_character(x)
  pillar::new_pillar_shaft_simple(
    ifelse(is.na(out), pillar::style_na("NA"), out),
    align = "right"
  )
}

zu_pillar_shaft <- function(x, ...) {
  out <- zu_as_character(x)
  pillar::new_pillar_shaft_simple(
    ifelse(is.na(out), pillar::style_na("NA"), out),
    align = "right"
  )
}

#' Helpers for code that drops the class
#'
#' Base functions that build their result from the values without their
#' class, such as [ifelse()] and [vapply()], read a zuint vector's raw bits
#' as numbers. These helpers do the same jobs and keep the type.
#'
#' `zu_ifelse()` takes `yes` and `no` to their common type (see
#' [zu_common_type()]) and is `NA` where `test` is. `zu_vapply()` calls
#' `FUN` on each element of `X` and requires each result to have the length
#' of `FUN.VALUE`, a zuint prototype such as `int64(0)`; the results take its
#' type. Both take [decimal128()] vectors too: `zu_ifelse()` combines `yes`
#' and `no` as [c()] does, and `zu_vapply()` converts each result to the
#' type of `FUN.VALUE` as `x[i] <- value` does, exactly or `NA`.
#'
#' @section Base functions that cannot dispatch:
#' R dispatches most functions on their first argument only, and some read
#' a vector's payload without dispatching at all. Design 4.1 accepts that
#' cost. Each function below returns the raw bits of the values, or drops
#' their class, so the answer is wrong, often with no warning. For
#' `decimal128` the bits are the scaled coefficients.
#'
#' * `c()` and `rbind()` of data frames with a non-zuint first argument or
#'   first column: `c(1L, int128(5))` is complex bits, as is
#'   `rbind(data.frame(x = 1L), data.frame(x = int128(5)))`. Put the zuint
#'   vector first, or use `vctrs::vec_rbind()` or `dplyr::bind_rows()`.
#' * [sum()], [min()], [max()], [range()] and the other `Summary` functions
#'   read only the first argument's class: `sum(int128(5), 1L)` is exact and
#'   `sum(1L, int128(5))` reads the raw bits. Put the zuint vector first.
#' * [is.unsorted()]: use `is.unsorted(xtfrm(x))`, whose ranks are exact.
#' * [complete.cases()] reads the payload's NaN patterns, so its answer is
#'   inverted for negative `int64` values: use `!is.na(x)` on each column.
#' * [aggregate()] and [rowsum()] read the payload, as a group or as the
#'   values. A negative `int64` group vanishes. Group by `as.character(x)`,
#'   and sum each group with `zu_vapply(split(x, g), sum, x[0])`.
#' * [var()] and [cor()] read the payload: `var(int64(1:10))` is 0. Use
#'   `var(as.double(x))`, which rounds to a double. [sd()] is right.
#' * [unlist()], [sapply()] and [vapply()] drop the class. Use
#'   `do.call(c, list)` and `zu_vapply()`.
#' * [ifelse()]: use `zu_ifelse()`.
#' * [formatC()] and `sprintf("%f")` read the bits (`sprintf("%d")` is an
#'   error). Use [format()], [as.character()] or [format_hex()]; `paste()`
#'   and `sprintf("%s")` are right.
#' * A zuint vector as an index or a count of a base function that does not
#'   dispatch on it: `letters[int64(2)]`, `rep(1, int64(3))`, `rep_len()`,
#'   `seq_len()`, `numeric()` and `vector()` are empty, and an `int128` index is
#'   an error. Pass `as.integer(i)`. A zuint vector as the vector being indexed,
#'   or as `rep()`'s `x`, is right.
#' * [base::matrix()], [base::array()], [base::outer()] and [diag()] return the
#'   raw bits. zuint vectors do not form matrices, and the functions that
#'   dispatch refuse them with a `zuint_unsupported_error`: `%*%`,
#'   [base::crossprod()] and [base::tcrossprod()] (the last two from R 4.4.0),
#'   [cbind()], [rbind()], [as.matrix()], [aperm()] and [scale()].
#' * [base::match()], `%in%`, [base::table()], [merge()] and the set functions
#'   compare a bare double as text: see [zu_match()].
#' * [cut()] has a method: see [zu_cut].
#'
#' @section Padding data frames and data.table:
#' Base R fills new rows with its own `NA`, whose bits are a valid `int64`,
#' `uint64`, `int128` or `uint128` value. Growing a data frame by row
#' (`d[nrow(d) + 2, "id"] <- 7L`, through `xpdrows.data.frame()`) strips the
#' class and fills the new rows of every zuint column with that value, not
#' `NA`. The same holds for data.table's `rbindlist(fill = TRUE)`,
#' `d[c(1, NA)]`, `shift()` and `:= NA` on `uint64`, `int128` and `uint128`
#' columns, and a data.table `by` groups the `NA` of a `uint64` column with
#' its neighbouring value (bit64 pads `int64` in base data frames the same
#' way). No zuint method is reached.
#'
#' These pad correctly: `rbind()` of data frames with a zuint first column,
#' [merge()], `vctrs::vec_rbind()` and `dplyr::bind_rows()`. With data.table,
#' fill and join on `as.character()` of the column, or convert the column
#' after the operation. An `int64` column works natively in data.table.
#'
#' @param test A logical vector.
#' @param yes,no Values for `TRUE` and `FALSE`, recycled to `test`.
#' @param X A vector or list.
#' @param FUN A function.
#' @param FUN.VALUE A zuint or `decimal128` vector of the length each result
#'   must have.
#' @param ... More arguments to `FUN`.
#' @return A zuint vector.
#' @examples
#' x <- int64(c("-9223372036854775807", "5", NA))
#' zu_ifelse(x > 0L, x, int64(0))
#' zu_vapply(1:3, function(i) uint64(2)^i, uint64(0))
#' @export
zu_ifelse <- function(test, yes, no) {
  call <- sys.call()
  if (is_decimal128(yes) || is_decimal128(no)) {
    return(dec_ifelse(test, yes, no, call))
  }
  kinds <- c(zu_kind(yes), zu_kind(no))
  zu_check_operands(kinds, list(yes, no), call)
  code <- zu_common_code(kinds, call)
  nm <- names(test)
  test <- as.logical(zu_from_bit64(test))
  n <- length(test)
  # a double follows the rule of c() and the operators: integral and in
  # range, or a zuint_double_error
  for (v in list(yes, no)) {
    if (
      zu_kind(v) == zu_kind_dbl && zu_convert(v, zu_kind_dbl, code)[[2L]] > 0
    ) {
      zu_double_problem(zu_types[[code]], call)
      return(ifelse(test, zu_dbl_quiet(yes), zu_dbl_quiet(no)))
    }
  }
  out <- rep(zu_cast(yes, code, call = call), length.out = n)
  no <- rep(zu_cast(no, code, call = call), length.out = n)
  f <- !is.na(test) & !test
  out[f] <- no[f]
  out[is.na(test)] <- NA
  names(out) <- nm
  out
}

#' @rdname zu_ifelse
#' @export
zu_vapply <- function(X, FUN, FUN.VALUE, ...) {
  call <- sys.call()
  if (is_decimal128(FUN.VALUE)) {
    return(dec_vapply(X, FUN, FUN.VALUE, ..., call = call))
  }
  code <- zu_code(FUN.VALUE)
  if (is.na(code)) {
    zu_abort("`FUN.VALUE` must be a zuint vector.", "type", call = call)
  }
  FUN <- match.fun(FUN)
  k <- length(FUN.VALUE)
  res <- lapply(X, function(el) {
    r <- FUN(el, ...)
    if (length(r) != k) {
      zu_abort(
        sprintf("Each result must have length %d.", k),
        "type",
        call = call
      )
    }
    zu_unclass(zu_cast(r, code, call = call))
  })
  out <- zu_new(
    if (length(res)) unlist(lapply(res, zu_bare)) else zu_alloc_empty(code),
    code
  )
  if (k == 1L) {
    names(out) <- names(X)
  }
  out
}

# A zero-length payload of a type's storage.
zu_alloc_empty <- function(code) if (code <= 2L) double() else complex()

# zu_ifelse() with a decimal: yes and no in their common type, as c() takes
# them.
dec_ifelse <- function(test, yes, no, call) {
  both <- dec_c(unname(yes), unname(no))
  if (!is_decimal128(both)) {
    # a double that is not whole, under options(zuint.double = "allow")
    return(ifelse(test, dec_dbl_quiet(yes), dec_dbl_quiet(no)))
  }
  nm <- names(test)
  test <- as.logical(zu_from_bit64(test))
  n <- length(test)
  ny <- length(yes)
  out <- rep(both[seq_len(ny)], length.out = n)
  no <- rep(both[ny + seq_along(no)], length.out = n)
  f <- !is.na(test) & !test
  out[f] <- no[f]
  out[is.na(test)] <- NA
  names(out) <- nm
  out
}

dec_vapply <- function(X, FUN, FUN.VALUE, ..., call) {
  FUN <- match.fun(FUN)
  k <- length(FUN.VALUE)
  res <- lapply(X, function(el) {
    r <- FUN(el, ...)
    if (length(r) != k) {
      zu_abort(
        sprintf("Each result must have length %d.", k),
        "type",
        call = call
      )
    }
    zu_bare(dec_assign_value(r, FUN.VALUE, call))
  })
  out <- dec_new(
    if (length(res)) unlist(lapply(res, unname)) else complex(),
    dec_p(FUN.VALUE),
    dec_s(FUN.VALUE)
  )
  if (k == 1L) {
    names(out) <- names(X)
  }
  out
}
