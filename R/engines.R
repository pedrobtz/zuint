# Engine bridges (design 9.2). Each needs its Suggests packages and says so;
# none of them is used anywhere else.

zu_need <- function(pkgs, call) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    zu_abort(
      sprintf("This needs the %s package%s.", paste(missing, collapse = ", "), if (length(missing) > 1) "s" else ""),
      "unsupported",
      call = call
    )
  }
}

#' Convert to bit64's integer64
#'
#' `as_integer64()` returns the values as a plain bit64 `integer64`, for
#' code that checks the class exactly. `int64` already has bit64's storage,
#' so for it only the class changes; the other types convert first, exactly
#' or to `NA` with a warning of class `zuint_cast_warning`. bit64 itself is
#' not needed.
#'
#' The other direction is [int64()], which on an `integer64` likewise only
#' swaps the class.
#'
#' @param x A zuint vector or a bit64 `integer64`.
#' @return An `integer64` vector the length of `x`, with its names.
#' @examples
#' y <- as_integer64(int64("9007199254740993"))
#' class(y)
#' int64(y)
#' @export
as_integer64 <- function(x) {
  x <- zu_cast(x, 1L, call = sys.call())
  oldClass(x) <- "integer64"
  x
}

#' Query DuckDB into zuint columns
#'
#' `zu_duckdb_query()` runs a query through DuckDB's Arrow export and returns
#' a data frame in which `BIGINT`, `UBIGINT`, `HUGEINT` and `UHUGEINT` columns
#' are `int64`, `uint64`, `int128` and `uint128`, exactly. Other columns
#' convert as nanoarrow converts them. `zu_duckdb_register()` goes the other
#' way: it registers a data frame with DuckDB as a view whose zuint columns
#' have those four types.
#'
#' `zu_duckdb_query()` sets `arrow_lossless_conversion = true` on the
#' connection, which stays set: without it DuckDB exports `UHUGEINT` as a
#' decimal and values of \eqn{2^{127}} and above read back as negative.
#'
#' Both need the duckdb, DBI, arrow and nanoarrow packages.
#'
#' @param con A DuckDB connection.
#' @param sql A query.
#' @param name The name of the view to register.
#' @param data A data frame.
#' @return `zu_duckdb_query()` returns a data frame; `zu_duckdb_register()`
#'   returns `con`, invisibly. Unregister the view with
#'   `duckdb::duckdb_unregister_arrow()`.
#' @examplesIf all(vapply(c("duckdb", "DBI", "arrow", "nanoarrow"), requireNamespace, TRUE, quietly = TRUE))
#' con <- DBI::dbConnect(duckdb::duckdb())
#' zu_duckdb_query(con, "SELECT 18446744073709551614::UBIGINT AS id")
#'
#' zu_duckdb_register(con, "t", data.frame(h = int128("-170141183460469231731687303715884105727")))
#' DBI::dbGetQuery(con, "SELECT typeof(h) AS type, h::VARCHAR AS value FROM t")
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' @export
zu_duckdb_query <- function(con, sql) {
  call <- sys.call()
  zu_need(c("duckdb", "DBI", "arrow", "nanoarrow"), call)
  DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
  res <- DBI::dbSendQuery(con, sql, arrow = TRUE)
  on.exit(DBI::dbClearResult(res))
  stream <- nanoarrow::as_nanoarrow_array_stream(duckdb::duckdb_fetch_arrow(res))
  zu_stream_to_df(stream)
}

#' @rdname zu_duckdb_query
#' @export
zu_duckdb_register <- function(con, name, data) {
  call <- sys.call()
  zu_need(c("duckdb", "DBI", "arrow", "nanoarrow"), call)
  if (!is.data.frame(data)) {
    zu_abort("`data` must be a data frame.", "type", call = call)
  }
  # a Table, not a reader: DuckDB scans a registered reader only once
  duckdb::duckdb_register_arrow(con, name, zu_arrow_table(data))
  invisible(con)
}

#' Arrow tables with zuint columns
#'
#' `zu_arrow_table()` makes an Arrow Table from a data frame whose zuint
#' columns keep their exact types (see [zu_to_arrow()]), and
#' `zu_from_arrow_table()` reads a Table or record batch reader back into a
#' data frame with zuint columns. Together they carry zuint vectors through
#' anything arrow writes and reads, such as Parquet files.
#'
#' They go through nanoarrow rather than arrow's own conversion. arrow
#' 24.0.0 aborts R when it makes an R object for the `arrow.opaque`
#' extension type that `int128` and `uint128` use, so
#' `arrow::as_arrow_array()` and `arrow::infer_type()` work for `int64` and
#' `uint64` only, and give an error for the 128-bit types.
#'
#' Both need the arrow and nanoarrow packages.
#'
#' @param data A data frame.
#' @param table An Arrow Table or record batch reader.
#' @return `zu_arrow_table()` returns an Arrow Table;
#'   `zu_from_arrow_table()` a data frame.
#' @examplesIf all(vapply(c("arrow", "nanoarrow"), requireNamespace, TRUE, quietly = TRUE))
#' df <- data.frame(id = uint64("18446744073709551614"), big = int128("-1"))
#' tb <- zu_arrow_table(df)
#' tb$schema
#'
#' f <- tempfile(fileext = ".parquet")
#' arrow::write_parquet(tb, f)
#' zu_from_arrow_table(arrow::read_parquet(f, as_data_frame = FALSE))
#' @export
zu_arrow_table <- function(data) {
  call <- sys.call()
  zu_need(c("arrow", "nanoarrow"), call)
  if (!is.data.frame(data)) {
    zu_abort("`data` must be a data frame.", "type", call = call)
  }
  arrow::as_arrow_table(zu_df_to_nanoarrow(data))
}

#' @rdname zu_arrow_table
#' @export
zu_from_arrow_table <- function(table) {
  zu_need(c("arrow", "nanoarrow"), sys.call())
  zu_stream_to_df(nanoarrow::as_nanoarrow_array_stream(table))
}

# A data frame from a stream of struct arrays: zuint columns through the
# bridge, the rest through nanoarrow.
zu_stream_to_df <- function(stream) {
  schema <- stream$get_schema()
  batches <- list()
  while (!is.null(b <- stream$get_next())) {
    batches[[length(batches) + 1L]] <- b
  }
  cols <- lapply(seq_along(schema$children), function(j) {
    child <- schema$children[[j]]
    parts <- lapply(batches, function(b) b$children[[j]])
    code <- zu_arrow_type(child)
    if (is.na(code)) {
      nanoarrow::convert_array_stream(nanoarrow::basic_array_stream(parts, schema = child))
    } else if (length(parts) == 0L) {
      zu_new(zu_alloc_empty(code), code)
    } else {
      do.call(c, lapply(parts, zu_from_arrow, schema = child))
    }
  })
  names(cols) <- names(schema$children)
  as.data.frame(structure(cols, row.names = c(NA, -length(cols[[1L]])), class = "data.frame"))
}

zu_alloc_empty <- function(code) if (code <= 2L) double() else complex()

# A nanoarrow struct array of a data frame's columns.
zu_df_to_nanoarrow <- function(data) {
  arrays <- lapply(data, function(col) {
    if (is.na(zu_code(col))) nanoarrow::as_nanoarrow_array(col) else zu_as_nanoarrow_array(col)
  })
  schemas <- lapply(arrays, nanoarrow::infer_nanoarrow_schema)
  struct <- nanoarrow::nanoarrow_array_init(nanoarrow::na_struct(schemas))
  nanoarrow::nanoarrow_array_modify(struct, list(length = nrow(data), children = arrays))
}

# arrow methods, registered when arrow loads. The 128-bit types get an
# error instead: arrow 24.0.0 aborts R when it wraps their arrow.opaque
# type in an R object (see zu_arrow_table()).
zu_register_arrow <- function(...) {
  ns <- asNamespace("arrow")
  for (cl in c("zu_int64", "zu_uint64")) {
    registerS3method("as_arrow_array", cl, zu_as_arrow_array, envir = ns)
    registerS3method("infer_type", cl, zu_infer_type, envir = ns)
  }
  for (cl in c("zu_int128", "zu_uint128")) {
    registerS3method("as_arrow_array", cl, zu_arrow_unsupported, envir = ns)
    registerS3method("infer_type", cl, zu_arrow_unsupported, envir = ns)
  }
}

zu_arrow_unsupported <- function(x, ...) {
  zu_abort(
    "arrow cannot hold int128 or uint128 as an R object yet; use zu_arrow_table() or zu_to_arrow().",
    "unsupported",
    call = sys.call()
  )
}

zu_as_arrow_array <- function(x, ..., type = NULL) {
  out <- arrow::as_arrow_array(zu_as_nanoarrow_array(x))
  if (is.null(type)) out else out$cast(type)
}

zu_infer_type <- function(x, ...) {
  arrow::as_data_type(zu_infer_nanoarrow_schema(x))
}
