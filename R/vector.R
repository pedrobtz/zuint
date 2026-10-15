# The base vector protocol, shared by the four classes. Each method works on
# the payload and puts the class back. Every generic bit64 defines for
# integer64 must have a method here too, or zu_int64 falls through to bit64's
# whenever bit64 is loaded (design 4.1).

# generic = method. Registered for each class by zu_s3_registrations().
zu_methods <- c(
  "[" = "zu_subset",
  "[[" = "zu_subset2",
  "[<-" = "zu_subassign",
  "[[<-" = "zu_subassign2",
  "length<-" = "zu_set_length",
  c = "zu_c",
  rep = "zu_rep",
  rev = "zu_rev",
  is.na = "zu_is_na",
  "is.na<-" = "zu_set_na",
  anyNA = "zu_any_na",
  as.character = "zu_as_character",
  as.double = "zu_as_double",
  as.integer = "zu_as_integer",
  as.logical = "zu_as_logical",
  as.list = "zu_as_list",
  as.data.frame = "zu_as_data_frame",
  format = "zu_format",
  print = "zu_print",
  str = "zu_str",
  summary = "zu_summary",
  Ops = "zu_ops",
  Math = "zu_math",
  chooseOpsMethod = "zu_choose_ops_method"
)

# NAMESPACE lines, written by roxygen through @evalNamespace.
zu_s3_registrations <- function() {
  classes <- c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128")
  grid <- expand.grid(
    generic = names(zu_methods),
    class = classes,
    stringsAsFactors = FALSE
  )
  sprintf(
    'S3method("%s", %s, %s)',
    grid$generic,
    grid$class,
    zu_methods[grid$generic]
  )
}

#' @evalNamespace zu_s3_registrations()
NULL

# The payload with every attribute but names; the class goes back on with
# zu_new().
zu_unclass <- function(x) {
  attributes(x) <- if (is.null(names(x))) NULL else list(names = names(x))
  x
}

zu_type_name <- function(x) zu_types[[zu_code(x)]]

# Positions of `x[i]` that fell outside x: base fills them with its own NA,
# whose bits are a valid value here. Found by indexing a vector that has no
# NA of its own the same way.
zu_out_of_range <- function(x, i) {
  probe <- seq_along(x)
  names(probe) <- names(x)
  is.na(probe[i])
}

zu_fill_na <- function(payload, code, where) {
  if (!any(where)) {
    return(payload)
  }
  out <- .Call(zu_fill_na_c, zu_bare(payload), code, where)
  attributes(out) <- attributes(payload)
  out
}

zu_subset <- function(x, i, ...) {
  code <- zu_code(x)
  s <- zu_unclass(x)
  if (missing(i)) {
    return(x)
  }
  if (...length() > 0L) {
    zu_abort("zuint vectors have one dimension.", "type", call = sys.call())
  }
  zu_new(zu_fill_na(s[i], code, zu_out_of_range(x, i)), code)
}

zu_subset2 <- function(x, i, ...) {
  code <- zu_code(x)
  s <- zu_unclass(x)
  out <- s[[i, ...]]
  zu_new(out, code)
}

# Positions that an assignment to `x[i]` padded rather than assigned: an
# integer probe pads with NA too.
zu_padded <- function(x, i, double = FALSE) {
  probe <- integer(length(x))
  names(probe) <- names(x)
  if (double) {
    probe[[i]] <- 0L
  } else if (missing(i)) {
    probe[] <- 0L
  } else {
    probe[i] <- 0L
  }
  is.na(probe)
}

zu_subassign <- function(x, i, ..., value) {
  code <- zu_code(x)
  if (...length() > 0L) {
    zu_abort("zuint vectors have one dimension.", "type", call = sys.call())
  }
  value <- zu_unclass(zu_cast(value, code, call = sys.call()))
  s <- zu_unclass(x)
  if (missing(i)) {
    s[] <- value
    return(zu_new(s, code))
  }
  s[i] <- value
  if (length(s) > length(x)) {
    s <- zu_fill_na(s, code, zu_padded(x, i))
  }
  zu_new(s, code)
}

zu_subassign2 <- function(x, i, ..., value) {
  code <- zu_code(x)
  value <- zu_unclass(zu_cast(value, code, call = sys.call()))
  s <- zu_unclass(x)
  s[[i, ...]] <- value
  if (length(s) > length(x)) {
    s <- zu_fill_na(s, code, zu_padded(x, i, double = TRUE))
  }
  zu_new(s, code)
}

zu_set_length <- function(x, value) {
  code <- zu_code(x)
  n <- length(x)
  s <- zu_unclass(x)
  length(s) <- value
  if (length(s) > n) {
    s <- zu_fill_na(s, code, seq_along(s) > n)
  }
  zu_new(s, code)
}

# Every argument takes the common type of the promotion order (design 5).
# Strings are parsed into it. A negative integer an unsigned type cannot take
# becomes NA with a warning, as in any conversion.
zu_c <- function(...) {
  args <- list(...)
  call <- sys.call()
  kinds <- vapply(args, zu_kind, integer(1))
  if (anyNA(kinds)) {
    zu_abort(
      sprintf("Can't combine %s with a zuint vector.", zu_kind_label(args[[which(is.na(kinds))[[1L]]]])),
      "type",
      call = call
    )
  }
  code <- zu_common_code(kinds, call)
  parts <- vector("list", length(args))
  lost <- 0
  for (i in seq_along(args)) {
    r <- zu_convert(args[[i]], kinds[[i]], code)
    if (kinds[[i]] == zu_kind_dbl && r[[2L]] > 0) {
      zu_double_problem(zu_types[[code]], call)
      return(unlist(lapply(args, zu_dbl_quiet)))
    }
    lost <- lost + r[[2L]]
    parts[[i]] <- r[[1L]]
    names(parts[[i]]) <- names(args[[i]])
  }
  zu_warn_lost(lost, zu_types[[code]], call = call)
  names(parts) <- names(args)
  zu_new(do.call(c, parts), code)
}

zu_rep <- function(x, ...) {
  zu_new(rep(zu_unclass(x), ...), zu_code(x))
}

zu_rev <- function(x) {
  if (length(x)) x[length(x):1L] else x
}

zu_is_na <- function(x) {
  out <- .Call(zu_is_na_c, zu_bare(x), zu_code(x))
  names(out) <- names(x)
  out
}

zu_set_na <- function(x, value) {
  x[value] <- NA
  x
}

zu_any_na <- function(x, recursive = FALSE) {
  any(zu_is_na(x))
}

zu_as_character <- function(x, ...) {
  .Call(zu_to_character_c, zu_bare(x), zu_code(x))
}

zu_as_double <- function(x, ...) {
  res <- .Call(zu_to_double_c, zu_bare(x), zu_code(x))
  if (res[[2L]] > 0) {
    zu_warn(
      sprintf(
        "%s value%s rounded in the conversion to double.",
        format(res[[2L]], scientific = FALSE),
        if (res[[2L]] == 1) " was" else "s were"
      ),
      "precision",
      call = sys.call()
    )
  }
  res[[1L]]
}

zu_as_integer <- function(x, ...) {
  res <- .Call(zu_to_integer_c, zu_bare(x), zu_code(x))
  zu_warn_lost(res[[2L]], "integer", call = sys.call())
  res[[1L]]
}

zu_as_logical <- function(x, ...) {
  zu_as_character(x) != "0"
}

zu_as_list <- function(x, ...) {
  out <- lapply(seq_along(x), function(i) x[[i]])
  names(out) <- names(x)
  out
}

zu_as_data_frame <- function(
  x,
  row.names = NULL,
  optional = FALSE,
  ...,
  nm = deparse1(substitute(x))
) {
  as.data.frame.vector(
    x,
    row.names = row.names,
    optional = optional,
    ...,
    nm = nm
  )
}

# Numbers are right-justified whatever `justify` says, as format() does for
# doubles; format.data.frame() passes "left".
zu_format <- function(x, ..., justify = "right") {
  s <- zu_as_character(x)
  s[is.na(s)] <- "NA"
  out <- format(s, justify = "right", ...)
  names(out) <- names(x)
  out
}

zu_print <- function(x, ...) {
  type <- zu_type_name(x)
  if (length(x) == 0L) {
    cat(type, "(0)\n", sep = "")
  } else {
    cat("<", type, "[", length(x), "]>\n", sep = "")
    print(zu_format(x), quote = FALSE, ...)
  }
  invisible(x)
}

zu_str <- function(object, ..., vec.len = 4) {
  n <- length(object)
  shown <- object[seq_len(min(n, max(1L, round(2.5 * vec.len))))]
  vals <- zu_as_character(shown)
  vals[is.na(vals)] <- "NA"
  cat(
    " ",
    zu_type_name(object),
    " ",
    if (n == 1L) "" else paste0("[1:", n, "] "),
    paste(vals, collapse = " "),
    if (length(shown) < n) " ...",
    "\n",
    sep = ""
  )
  invisible()
}

# Minimum, maximum and the NA count. Quartiles wait for sorting (Stage 6).
zu_summary <- function(object, ...) {
  code <- zu_code(object)
  r <- zu_as_character(zu_new(
    .Call(zu_range_c, zu_bare(object), code, TRUE),
    code
  ))
  n_na <- sum(zu_is_na(object))
  out <- c("Min." = r[[1L]], "Max." = r[[2L]])
  if (n_na > 0L) {
    out <- c(out, "NA's" = as.character(n_na))
  }
  out[is.na(out)] <- "NA"
  noquote(out)
}

# Claim mixed calls such as zu_int64 + integer64, which R would otherwise
# run on the raw bits after an "incompatible methods" warning (design 4.1).
zu_choose_ops_method <- function(x, y, mx, my, cl, reverse) TRUE
