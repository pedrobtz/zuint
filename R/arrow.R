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
#'
#' An `arrow.opaque` column is DuckDB's when its JSON metadata says so at
#' the top level: `vendor_name` `"DuckDB"` and `type_name` `"hugeint"` or
#' `"uhugeint"`. Other `arrow.opaque` types, which DuckDB uses for types
#' Arrow has no form for, keep zuarrow's own conversion, as does metadata
#' that is not valid JSON.
#'
#' With `to = int64()` or `to = uint64()`, 8-, 16- and 32-bit integer
#' columns are read exactly and cast to the prototype.
#'
#' A `decimal128(p, 0)` column is a decimal, not an integer, so zuint does
#' not register for it. Asking for `int128` with `to = int128()` in
#' `zuarrow::arrow_to_r()` reads one with `p` up to 38 as the 128 bits it
#' holds. DuckDB writes `HUGEINT` that way unless its
#' `arrow_lossless_conversion` setting is on, so turn the setting on, and
#' `HUGEINT` and `UHUGEINT` arrive as the extension:
#'
#' ```r
#' DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
#' zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))
#' ```
#'
#' A null reads as `NA` and an `NA` writes as a null. A valid value equal to
#' a type's `NA` bit pattern, such as `UINT64_MAX` in a `UBIGINT` column,
#' cannot be held. zuarrow's `lossy` policy decides what happens to it:
#'
#' * `"error"` and `"character"` raise `zuarrow_lossy_error`, naming the
#'   value. `"character"` would give the column as text only when every
#'   batch held such a value, so it fails like `"error"` instead.
#' * `"warn"` reads it as `NA` with one `zuarrow_lossy_warning` per batch.
#' * `"allow"` reads it as `NA` silently.
#'
#' Writing never loses a value: `int128` and `uint128` are written as the
#' DuckDB extension, which DuckDB reads back as `HUGEINT` and `UHUGEINT`.
#'
#' @name zuint-arrow
#' @seealso [zu_storage()] for the representation, the contract a package
#'   that builds zuint vectors in C relies on.
NULL

zu_register_zuarrow <- function(...) {
  zuarrow::arrow_register(
    "l",
    to = zu_arrow_to(1L),
    from = zu_arrow_from,
    class = "zu_int64",
    package = "zuint"
  )
  zuarrow::arrow_register(
    "L",
    to = zu_arrow_to(2L),
    from = zu_arrow_from,
    class = "zu_uint64",
    package = "zuint"
  )
  zuarrow::arrow_register(
    "arrow.opaque",
    to = zu_arrow_to(NA_integer_),
    from = zu_arrow_from,
    class = c("zu_int128", "zu_uint128"),
    package = "zuint"
  )
}

# A `to` handler for zuarrow. `target` is the zuint type code of the
# registration, or NA for arrow.opaque, whose type comes from the schema.
# zuarrow also calls a handler when a caller names its class as the
# prototype (`to = int128()`), with a column of another format: the import
# is then cast to the registration's type.
zu_arrow_to <- function(target) {
  force(target)
  function(array, schema, lossy) {
    call <- sys.call()
    code <- zu_arrow_try(zu_arrow_type(schema), call)
    if (is.na(code)) {
      if (!is.na(target)) {
        # a small integer column under a zuint prototype: read exactly in
        # C, since an R integer would make INT32_MIN NA (#155)
        res <- zu_arrow_try(.Call(zu_from_arrow_small_c, array, schema), call)
        if (!is.null(res)) {
          return(zu_cast(zu_new(res[[1L]], 1L), target, call = call))
        }
      }
      # zuarrow's own conversion: an arrow.opaque type that is not hugeint
      # or uhugeint, or a column zuint does not read, such as a double
      # under `to = int64()`, which is then cast as the caller asked
      x <- zuarrow::arrow_to_r(array, lossy = lossy)
      if (is.na(target)) {
        return(x)
      }
      return(zu_cast(x, target, call = call))
    }
    res <- zu_arrow_try(.Call(zu_from_arrow_c, array, schema), call)
    if (res[[2L]] > 0) {
      format <- zu_arrow_try(zu_arrow_format(schema), call)
      zu_arrow_lost(res[[2L]], code, format, lossy)
    }
    x <- zu_new(res[[1L]], code)
    if (!is.na(target) && code != target) {
      x <- zu_cast(x, target, call = call)
    }
    x
  }
}

zu_arrow_from <- function(x) {
  zu_arrow_try(.Call(zu_to_arrow_c, x, zu_code(x)), sys.call())
}

# Values equal to the type's NA bit pattern, under zuarrow's policy
# (review X4). zuarrow's own condition classes, so a caller handles them
# with the rest of zuarrow's.
zu_arrow_lost <- function(n, code, format, lossy) {
  type <- zu_types[[code]]
  sentinel <- zu_sentinel_value(code)
  if (lossy %in% c("error", "character")) {
    stop(structure(
      class = c("zuarrow_lossy_error", "zuarrow_error", "error", "condition"),
      list(
        message = sprintf(
          paste(
            "%.0f value%s of an Arrow `%s` column equal%s %s, the bit",
            "pattern of %s's NA, and cannot be read as %s.",
            "Use `lossy = \"warn\"` to read %s as NA."
          ),
          n,
          if (n == 1) "" else "s",
          format,
          if (n == 1) "s" else "",
          sentinel,
          type,
          type,
          if (n == 1) "it" else "them"
        ),
        call = NULL,
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
        message = sprintf(
          "%.0f value%s equal to %s, the bit pattern of %s's NA, read as NA.",
          n,
          if (n == 1) "" else "s",
          sentinel,
          type
        ),
        call = NULL,
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
