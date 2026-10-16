# Operand kinds, shared with the C code: 1 to 4 are the type codes, the rest
# are bare base vectors. NA is anything zuint does not convert.
zu_kind_int <- 0L
zu_kind_dbl <- -1L
zu_kind_chr <- -2L

zu_kind <- function(x) {
  code <- zu_code(x)
  if (!is.na(code)) {
    return(code)
  }
  if (is.null(x)) {
    return(zu_kind_int)
  }
  if (is.object(x) || !is.atomic(x)) {
    return(NA_integer_)
  }
  switch(
    typeof(x),
    logical = ,
    integer = zu_kind_int,
    double = zu_kind_dbl,
    character = zu_kind_chr,
    NA_integer_
  )
}

zu_kind_label <- function(x) {
  if (is.object(x)) paste0("<", paste(class(x), collapse = "/"), ">") else paste("a", typeof(x), "vector")
}

# x, of kind `kind`, as a bare payload of type `code`, and how many values
# were lost to NA.
# For the same type x comes back as it is, attributes included: the C code
# ignores them, and stripping them would copy the vector.
zu_convert <- function(x, kind, code) {
  if (kind == code) {
    return(list(x, 0))
  }
  if (is.null(x)) {
    x <- integer()
  }
  .Call(zu_cast_c, x, kind, code)
}

# x as zuint type `code`, names kept. Lost values warn, reported against
# `call`.
zu_cast <- function(x, code, call = sys.call(-1L)) {
  kind <- zu_kind(x)
  if (is.na(kind)) {
    zu_abort(
      sprintf("Can't convert %s to %s.", zu_kind_label(x), zu_types[[code]]),
      "type",
      call = call
    )
  }
  if (kind == code) {
    # the same type as it is (setting the class again would copy), or a
    # bit64 integer64 for int64, where only the class changes
    if (identical(oldClass(x), zu_classes[[code]])) {
      return(x)
    }
    return(zu_new(x, code))
  }
  res <- zu_convert(x, kind, code)
  zu_warn_lost(res[[2L]], zu_types[[code]], call = call)
  out <- res[[1L]]
  names(out) <- names(x)
  zu_new(out, code)
}

# The vector without attributes.
zu_bare <- function(x) {
  attributes(x) <- NULL
  x
}
