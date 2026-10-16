# nanoarrow methods, registered when nanoarrow loads (design 9.1). Nothing
# else in the package calls nanoarrow, which stays a Suggests.

zu_register_nanoarrow <- function(...) {
  ns <- asNamespace("nanoarrow")
  for (cl in c("zu_int64", "zu_uint64", "zu_int128", "zu_uint128")) {
    registerS3method("convert_array", cl, zu_convert_array, envir = ns)
    registerS3method("as_nanoarrow_array", cl, zu_as_nanoarrow_array, envir = ns)
    registerS3method("infer_nanoarrow_schema", cl, zu_infer_nanoarrow_schema, envir = ns)
  }
}

# convert_array(array, int64()) and friends: the bridge when the array's
# type is one zuint imports, nanoarrow's own conversion otherwise; then the
# requested type.
zu_convert_array <- function(array, to, ...) {
  schema <- nanoarrow::infer_nanoarrow_schema(array)
  x <- if (!is.na(zu_arrow_type(schema))) {
    zu_from_arrow(array, schema)
  } else {
    nanoarrow::convert_array(array, NULL)
  }
  zu_cast(x, zu_code(to), call = sys.call())
}

zu_as_nanoarrow_array <- function(x, ..., schema = NULL) {
  out <- zu_to_arrow(x)
  if (!is.null(schema)) {
    return(nanoarrow::as_nanoarrow_array(zu_nanoarrow_move(out)$array, schema = schema))
  }
  zu_nanoarrow_move(out)$array
}

zu_infer_nanoarrow_schema <- function(x, ...) {
  zu_nanoarrow_move(zu_to_arrow(x[0L]))$schema
}

# Our exported structs moved into nanoarrow's own objects.
zu_nanoarrow_move <- function(exported) {
  schema <- nanoarrow::nanoarrow_allocate_schema()
  nanoarrow::nanoarrow_pointer_move(exported$schema, schema)
  array <- nanoarrow::nanoarrow_allocate_array()
  nanoarrow::nanoarrow_pointer_move(exported$array, array)
  nanoarrow::nanoarrow_array_set_schema(array, schema)
  list(array = array, schema = schema)
}
