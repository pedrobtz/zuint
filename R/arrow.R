#' zuint columns from Arrow, through zuarrow
#'
#' zuint has no Arrow functions of its own. When the
#' [zuarrow](https://github.com/pedrobtz/zuarrow) package is installed, zuint
#' registers its four types with zuarrow's registry as soon as both are
#' loaded, and from then on `zuarrow::arrow_to_r()`, `zuarrow::arrow_read()`
#' and `zuarrow::arrow_array()` read and write zuint columns exactly.
#' `zuarrow::arrow_registry()` lists the entries:
#'
#' | Key | Arrow type | zuint type |
#' | --- | --- | --- |
#' | `l` | `int64` | `int64` |
#' | `L` | `uint64` | `uint64` |
#' | `arrow.opaque` | DuckDB's `hugeint` extension (`w:16`) | `int128` |
#' | `arrow.opaque` | DuckDB's `uhugeint` extension (`w:16`) | `uint128` |
#' | `zuint.int128` | none: `to = int128()`, and writing | `int128` |
#' | `zuint.uint128` | none: `to = uint128()`, and writing | `uint128` |
#'
#' An `arrow.opaque` column is DuckDB's when its JSON metadata says so at
#' the top level: `vendor_name` `"DuckDB"` and `type_name` `"hugeint"` or
#' `"uhugeint"`. Other `arrow.opaque` types, which DuckDB uses for types
#' Arrow has no form for, keep zuarrow's own conversion, as does metadata
#' that is not valid JSON. The `zuint.int128` and `zuint.uint128` keys match
#' no Arrow column: zuarrow finds a prototype's handler by its class, so
#' each 128-bit class has a registration of its own.
#'
#' A zuint prototype in `to =`, such as `to = list(x = uint64())`, gives
#' that type for a column of any format, or a condition. zuint reads its
#' own formats and the 8-, 16- and 32-bit integers exactly, and any other
#' column through zuarrow's own conversion, then casts the values to the
#' prototype's type. A value the type cannot hold, such as `-1` under
#' `uint64()`, `0.5` or the text `"abc"`, follows the `lossy` policy below.
#'
#' A `decimal128(p, 0)` column is a decimal, not an integer, so zuint does
#' not register for it. Asking for `int128` with `to = int128()` in
#' `zuarrow::arrow_to_r()` reads one with `p` up to 38 as the 128 bits it
#' holds, and `to = uint128()` reads its value, so a negative one is lost.
#' DuckDB writes `HUGEINT` and `UHUGEINT` that way unless its
#' `arrow_lossless_conversion` setting is on, and a `UHUGEINT` of 2^127 or
#' more is then a negative decimal. So turn the setting on, and `HUGEINT`
#' and `UHUGEINT` arrive as the extension:
#'
#' ```r
#' DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
#' zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))
#' ```
#'
#' A null reads as `NA` and an `NA` writes as a null. A valid value equal to
#' a type's `NA` bit pattern, such as `UINT64_MAX` in a `UBIGINT` column,
#' cannot be held, nor can a value out of a prototype's range. zuarrow's
#' `lossy` policy decides what happens to them, in zuarrow's condition
#' classes:
#'
#' * `"error"` and `"character"` raise `zuarrow_lossy_error`, naming the
#'   column, its format and a value. `"character"` would give the column as
#'   text only for the batches that lose a value, which could not be
#'   combined with the others, so it fails like `"error"` instead.
#' * `"warn"` reads them as `NA` with one `zuarrow_lossy_warning` per batch.
#' * `"allow"` reads them as `NA` silently.
#'
#' Writing never loses a value: `int128` and `uint128` are written as the
#' DuckDB extension, which DuckDB reads back as `HUGEINT` and `UHUGEINT`.
#'
#' @name zuint-arrow
#' @seealso [zu_storage()] for the representation, the contract a package
#'   that builds zuint vectors in C relies on.
NULL

# Five registrations, so that zuarrow's dispatch by prototype class, which
# passes a handler no prototype, reaches a handler that knows its type
# (#167). zuarrow picks the handler of a `to =` prototype by its class, and
# a class in two registrations goes to the first; so each class is in one.
# arrow.opaque reads DuckDB's extension columns and claims no class, and
# zuint.int128 and zuint.uint128, which no Arrow column is known to use,
# carry the 128-bit classes: their `to` for a prototype, their `from` for
# writing, which gives the extension as before.
zu_register_zuarrow <- function(...) {
  register <- function(key, code, class = NULL) {
    zuarrow::arrow_register(
      key,
      to = zu_arrow_to(code),
      from = if (!is.null(class)) zu_arrow_from,
      class = class,
      package = "zuint"
    )
  }
  register("l", 1L, "zu_int64")
  register("L", 2L, "zu_uint64")
  register("arrow.opaque", NA_integer_)
  register("zuint.int128", 3L, "zu_int128")
  register("zuint.uint128", 4L, "zu_uint128")
}

# A `to` handler for zuarrow. `target` is the zuint type code of the
# registration, or NA for arrow.opaque, whose type comes from the schema.
# zuarrow also calls a handler when a caller names its class as the
# prototype (`to = int128()`), with a column of any format: the import is
# then cast to the registration's type, and a value the type cannot hold
# follows the caller's `lossy` policy (#167).
zu_arrow_to <- function(target) {
  force(target)
  function(array, schema, lossy) {
    call <- sys.call()
    code <- zu_arrow_try(zu_arrow_type(schema), call)
    if (is.na(code)) {
      if (is.na(target)) {
        # an arrow.opaque type that is not hugeint or uhugeint: zuarrow's
        # own conversion
        return(zuarrow::arrow_to_r(array, lossy = lossy))
      }
      # a small integer column, read exactly in C, since an R integer would
      # make INT32_MIN NA (#155); any other format through zuarrow, such as
      # a double under `to = int64()`, then cast as the caller asked
      res <- zu_arrow_try(.Call(zu_from_arrow_small_c, array, schema), call)
      x <- if (is.null(res)) {
        zuarrow::arrow_to_r(array, lossy = lossy)
      } else {
        zu_new(res[[1L]], 1L)
      }
      return(zu_arrow_cast(x, target, schema, lossy, call))
    }
    wide <- !is.na(target) && target > 2L
    res <- zu_arrow_try(.Call(zu_from_arrow_c, array, schema, wide), call)
    if (res[[2L]] > 0) {
      zu_arrow_lost(
        schema,
        lossy,
        res[[2L]],
        sprintf(
          "%s %s %s, the bit pattern of %s's NA",
          zu_arrow_count(res[[2L]]),
          if (res[[2L]] == 1) "equals" else "equal",
          zu_sentinel_value(code),
          zu_types[[code]]
        ),
        sprintf(
          "%s equal to %s, the bit pattern of %s's NA, read as NA",
          zu_arrow_count(res[[2L]]),
          zu_sentinel_value(code),
          zu_types[[code]]
        )
      )
    }
    x <- zu_new(res[[1L]], res[[3L]])
    if (is.na(target) || res[[3L]] == target) {
      return(x)
    }
    zu_arrow_cast(x, target, schema, lossy, call)
  }
}

zu_arrow_from <- function(x) {
  zu_arrow_try(.Call(zu_to_arrow_c, x, zu_code(x)), sys.call())
}

# x, a column as read, cast to type `code`. A value the type cannot hold is
# NA, and zuarrow's policy applies to it, never zuint's cast warning (#167).
zu_arrow_cast <- function(x, code, schema, lossy, call) {
  kind <- zu_kind(x)
  if (is.na(kind)) {
    # not a vector zuint converts, such as a date: zuint's type error
    return(zu_cast(x, code, call = call))
  }
  res <- zu_convert(x, kind, code)
  out <- zu_new(res[[1L]], code)
  n <- res[[2L]]
  if (n == 0 || lossy == "allow") {
    return(out)
  }
  # the first value lost; text such as "NA" is NA without a loss
  first <- NULL
  for (i in which(is.na(out) & !is.na(x))) {
    if (zu_convert(x[i], kind, code)[[2L]] > 0) {
      first <- x[[i]]
      break
    }
  }
  type <- zu_types[[code]]
  format <- zu_arrow_try(zu_arrow_format(schema), call)
  hint <- if (startsWith(format, "d:") && code == 4L) {
    paste(
      "A decimal is read by value, and DuckDB writes `UHUGEINT` values of",
      "2^127 and above as negative decimals unless",
      "`SET arrow_lossless_conversion = true`."
    )
  }
  zu_arrow_lost(
    schema,
    lossy,
    n,
    sprintf(
      "%s can't be held by %s%s %s",
      zu_arrow_count(n),
      type,
      if (n == 1) ":" else ", the first",
      zu_arrow_value(first)
    ),
    sprintf("%s that %s can't hold, read as NA", zu_arrow_count(n), type),
    hint
  )
  out
}

# "1 value" or "3 values".
zu_arrow_count <- function(n) {
  sprintf("%.0f value%s", n, if (n == 1) "" else "s")
}

# A lost value for a message: text quoted, a double to 17 digits.
zu_arrow_value <- function(v) {
  if (is.character(v)) {
    encodeString(v, quote = "\"")
  } else if (is.double(v) && !is.object(v)) {
    format(v, digits = 17L)
  } else {
    as.character(v)
  }
}

# Values a column loses, under zuarrow's `lossy` policy (review X4, #167),
# in zuarrow's own condition classes and message form, so a caller handles
# them with the rest of zuarrow's. `error` and `warning` say what the `n`
# values lost were.
# "character" fails like "error": the handler returns one class for every
# batch, and text for only the batches that lose a value could not be
# combined with the others.
zu_arrow_lost <- function(schema, lossy, n, error, warning, hint = NULL) {
  format <- zu_arrow_format(schema)
  name <- .Call(zu_arrow_name_c, schema)
  label <- sprintf(
    "%s (Arrow format `%s`)",
    if (nzchar(name)) sprintf("Column `%s`", name) else "The column",
    format
  )
  column <- if (nzchar(name)) name
  if (lossy %in% c("error", "character")) {
    stop(structure(
      class = c("zuarrow_lossy_error", "zuarrow_error", "error", "condition"),
      list(
        message = paste(
          c(
            sprintf("%s can't be read exactly: %s.", label, error),
            hint,
            sprintf(
              "Use `lossy = \"warn\"` or `lossy = \"allow\"` to read %s as NA.",
              if (n == 1) "it" else "them"
            )
          ),
          collapse = " "
        ),
        call = NULL,
        column = column,
        arrow_type = format,
        package = "zuint"
      )
    ))
  }
  if (lossy == "warn") {
    warning(structure(
      class = c(
        "zuarrow_lossy_warning",
        "zuarrow_warning",
        "warning",
        "condition"
      ),
      list(
        message = sprintf("%s: %s.", label, warning),
        call = NULL,
        column = column,
        arrow_type = format
      )
    ))
  }
  invisible()
}

# The value whose bits are a type's NA, as the type would hold it unsigned
# or signed: INT64_MIN, UINT64_MAX, INT128_MIN, UINT128_MAX.
zu_sentinel_value <- function(code) {
  switch(
    code,
    "-9223372036854775808",
    "18446744073709551615",
    "-170141183460469231731687303715884105728",
    "340282366920938463463374607431768211455"
  )
}

zu_arrow_format <- function(schema) {
  f <- .Call(zu_arrow_format_c, schema)
  if (is.character(f)) f else "?"
}

# Arrow-level failures from C (a released struct, an unsupported format)
# as zuint_arrow_error.
zu_arrow_try <- function(expr, call) {
  tryCatch(
    expr,
    error = function(e) {
      zu_abort(sub("^zuint: ", "", conditionMessage(e)), "arrow", call = call)
    }
  )
}

# The schema in an array handle's tag (nanoarrow's r.h layout).
zu_arrow_tag <- function(array) .Call(zu_arrow_schema_c, array)

# The zuint type code an ArrowSchema maps to, or NA.
zu_arrow_type <- function(schema) {
  type <- .Call(zu_arrow_type_c, schema)
  if (is.integer(type)) type else NA_integer_
}
