#' Arrow C Data Interface
#'
#' Convert between zuint vectors and Arrow arrays through the Arrow C Data
#' Interface, with no R package in between. The arrays and schemas are
#' external pointers to `ArrowArray` and `ArrowSchema` structs, the form
#' nanoarrow's `nanoarrow_array` and `nanoarrow_schema` objects take.
#'
#' | zuint | Arrow format |
#' | --- | --- |
#' | `int64` | `int64` (`l`) |
#' | `uint64` | `uint64` (`L`) |
#' | `int128` | DuckDB's `arrow.opaque` `hugeint` extension (`w:16`); with `decimal = TRUE`, `decimal128(38, 0)` |
#' | `uint128` | DuckDB's `arrow.opaque` `uhugeint` extension (`w:16`) |
#'
#' `zu_from_arrow()` also reads any `decimal128(p, 0)` with `p` up to 38 as
#' `int128`, taking the 128 bits as they are, which is how DuckDB exports
#' `HUGEINT` by default. It copies the data and leaves the structs to their
#' owner. A null becomes `NA` and an `NA` becomes a null. A valid value that
#' happens to equal a type's `NA` bit pattern (for example `UINT64_MAX`)
#' cannot be told from `NA`: it imports as `NA` with a warning of class
#' `zuint_cast_warning`. `zu_sentinel_check()` counts those values without
#' importing.
#'
#' `zu_to_arrow()` exports `int128` as the extension by default because
#' DuckDB reads `decimal128(38, 0)` back as `DECIMAL(38,0)`, not `HUGEINT`.
#' `decimal = TRUE` is for consumers without extension support; a value with
#' more than 38 digits is then an error.
#'
#' When nanoarrow is installed, `nanoarrow::convert_array(array, int64())`
#' and the other constructors' prototypes import through this bridge, and
#' `nanoarrow::as_nanoarrow_array()` exports zuint vectors.
#'
#' @param array An external pointer to an `ArrowArray`, such as a
#'   `nanoarrow_array`.
#' @param schema An external pointer to the array's `ArrowSchema`.
#' @param x A zuint vector.
#' @param decimal Export `int128` as `decimal128(38, 0)`.
#' @return `zu_from_arrow()` returns a zuint vector; `zu_to_arrow()` a list
#'   of external pointers named `array` and `schema`, which release their
#'   structs when garbage collected unless a consumer moved them out;
#'   `zu_sentinel_check()` the number of values that would import as `NA`
#'   though they are not null.
#' @examples
#' x <- uint64(c("18446744073709551614", NA, "1"))
#' a <- zu_to_arrow(x)
#' zu_from_arrow(a$array, a$schema)
#'
#' b <- zu_to_arrow(int128(-1), decimal = TRUE)
#' zu_from_arrow(b$array, b$schema)
#' @name zuint-arrow
NULL

#' @rdname zuint-arrow
#' @export
zu_from_arrow <- function(array, schema) {
  call <- sys.call()
  zu_check_xptrs(array, schema, call)
  res <- zu_arrow_try(.Call(zu_from_arrow_c, array, schema), call)
  code <- res[[3L]]
  zu_warn_lost(res[[2L]], zu_types[[code]], call = sys.call())
  zu_new(res[[1L]], code)
}

#' @rdname zuint-arrow
#' @export
zu_to_arrow <- function(x, decimal = FALSE) {
  code <- zu_code(x)
  if (is.na(code)) {
    zu_abort("`x` must be a zuint vector.", "type", call = sys.call())
  }
  if (!isTRUE(decimal) && !isFALSE(decimal)) {
    zu_abort("`decimal` must be TRUE or FALSE.", "type", call = sys.call())
  }
  if (decimal && code != 3L) {
    zu_abort("`decimal = TRUE` is for int128 only.", "type", call = sys.call())
  }
  out <- zu_arrow_try(.Call(zu_to_arrow_c, x, code, decimal), sys.call())
  names(out) <- c("array", "schema")
  out
}

#' @rdname zuint-arrow
#' @export
zu_sentinel_check <- function(array, schema) {
  call <- sys.call()
  zu_check_xptrs(array, schema, call)
  as.integer(zu_arrow_try(.Call(zu_sentinel_check_c, array, schema), call)[[2L]])
}

zu_check_xptrs <- function(array, schema, call) {
  if (typeof(array) != "externalptr" || typeof(schema) != "externalptr") {
    zu_abort("`array` and `schema` must be external pointers.", "type", call = call)
  }
}

# Arrow-level failures from C (a released struct, an unsupported format)
# as zuint_arrow_error.
zu_arrow_try <- function(expr, call) {
  tryCatch(
    expr,
    error = function(e) zu_abort(sub("^zuint: ", "", conditionMessage(e)), "arrow", call = call)
  )
}

# The zuint type code an ArrowSchema maps to, or NA.
zu_arrow_type <- function(schema) {
  t <- .Call(zu_arrow_type_c, schema)
  if (is.integer(t)) t else NA_integer_
}
