# vctrs and pillar methods (design 9.2), registered when those packages
# load. The equality and ordering proxy is a data frame of exact 32-bit
# pieces: the payload itself would not do, because vctrs treats every NaN
# bit pattern as one value and many int64 values are NaN patterns.

zu_classes_all <- c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128")

zu_register_vctrs <- function(...) {
  ns <- asNamespace("vctrs")
  reg <- function(generic, cls, fun) registerS3method(generic, cls, fun, envir = ns)
  others <- c("integer", "logical", "double", "integer64")
  for (cl in zu_classes_all) {
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
}

zu_register_pillar <- function(...) {
  ns <- asNamespace("pillar")
  for (cl in zu_classes_all) {
    registerS3method("pillar_shaft", cl, zu_pillar_shaft, envir = ns)
    registerS3method("type_sum", cl, zu_vec_ptype_abbr, envir = ns)
  }
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
  code <- zu_code(to)
  out <- withCallingHandlers(
    zu_cast(x, code),
    zuint_cast_warning = function(w) invokeRestart("muffleWarning")
  )
  lossy <- zu_is_na(out) & !is.na(x)
  if (any(lossy)) {
    return(vctrs::maybe_lossy_cast(out, x, to, lossy = lossy, x_arg = x_arg, to_arg = to_arg))
  }
  out
}

zu_pillar_shaft <- function(x, ...) {
  out <- zu_as_character(x)
  out[is.na(out)] <- NA
  pillar::new_pillar_shaft_simple(ifelse(is.na(out), pillar::style_na("NA"), out), align = "right")
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
#' type.
#'
#' @param test A logical vector.
#' @param yes,no Values for `TRUE` and `FALSE`, recycled to `test`.
#' @param X A vector or list.
#' @param FUN A function.
#' @param FUN.VALUE A zuint vector of the length each result must have.
#' @param ... More arguments to `FUN`.
#' @return A zuint vector.
#' @examples
#' x <- int64(c("-9223372036854775807", "5", NA))
#' zu_ifelse(x > 0L, x, int64(0))
#' zu_vapply(1:3, function(i) uint64(2)^i, uint64(0))
#' @export
zu_ifelse <- function(test, yes, no) {
  call <- sys.call()
  kinds <- c(zu_kind(yes), zu_kind(no))
  zu_check_operands(kinds, list(yes, no), call)
  code <- zu_common_code(kinds, call)
  test <- as.logical(test)
  n <- length(test)
  out <- rep(zu_cast(yes, code, call = call), length.out = n)
  no <- rep(zu_cast(no, code, call = call), length.out = n)
  f <- !is.na(test) & !test
  out[f] <- no[f]
  out[is.na(test)] <- NA
  names(out) <- names(test)
  out
}

#' @rdname zu_ifelse
#' @export
zu_vapply <- function(X, FUN, FUN.VALUE, ...) {
  call <- sys.call()
  code <- zu_code(FUN.VALUE)
  if (is.na(code)) {
    zu_abort("`FUN.VALUE` must be a zuint vector.", "type", call = call)
  }
  FUN <- match.fun(FUN)
  k <- length(FUN.VALUE)
  res <- lapply(X, function(el) {
    r <- FUN(el, ...)
    if (length(r) != k) {
      zu_abort(sprintf("Each result must have length %d.", k), "type", call = call)
    }
    zu_unclass(zu_cast(r, code, call = call))
  })
  out <- zu_new(if (length(res)) unlist(lapply(res, zu_bare)) else zu_alloc_empty(code), code)
  if (k == 1L) {
    names(out) <- names(X)
  }
  out
}
