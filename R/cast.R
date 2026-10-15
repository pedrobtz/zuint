# Source kinds for zu_cast_c(); positive values are type codes.
zu_from_int <- 0L
zu_from_dbl <- -1L
zu_from_chr <- -2L

# x as zuint type `code`, names kept. Lost values warn, reported against
# `call`.
zu_cast <- function(x, code, call = sys.call(-1L)) {
  from <- zu_code(x)
  if (!is.na(from)) {
    if (from == code) {
      # the same type, or a bit64 integer64 for int64: only the class changes
      return(zu_new(x, code))
    }
  } else if (is.null(x)) {
    x <- integer()
    from <- zu_from_int
  } else if (is.object(x) || !is.atomic(x)) {
    zu_abort(
      sprintf(
        "Can't convert an object of class <%s> to %s.",
        paste(class(x), collapse = "/"),
        zu_types[[code]]
      ),
      "type",
      call = call
    )
  } else {
    from <- switch(
      typeof(x),
      logical = ,
      integer = zu_from_int,
      double = zu_from_dbl,
      character = zu_from_chr,
      zu_abort(
        sprintf(
          "Can't convert a %s vector to %s.",
          typeof(x),
          zu_types[[code]]
        ),
        "type",
        call = call
      )
    )
  }
  res <- .Call(zu_cast_c, zu_bare(x), from, code)
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
