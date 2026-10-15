# zuint 0.0.0.9000

* `int64()`, `uint64()`, `int128()` and `uint128()` create signed and
  unsigned 64- and 128-bit integer vectors from logical, integer, double,
  decimal character, bit64 `integer64` and each other. Conversion is exact
  or gives `NA` with a `zuint_cast_warning`; it never rounds or clamps.
* `int64` has class `c("zu_int64", "integer64")` and bit64's storage, so
  code that reads `integer64` reads it unchanged.
* `NA_int64_`, `NA_uint64_`, `NA_int128_` and `NA_uint128_`.
* The base vector protocol for all four types: subsetting and assignment
  (with exact casting of the assigned value), `c()`, `rep()`, `rev()`,
  `length<-`, `is.na()`, `anyNA()`, `as.character()`, `as.double()` (with
  a `zuint_precision_warning` when it rounds), `as.integer()`,
  `as.logical()`, `as.list()`, data frame columns, `format()`, `print()`,
  `str()` and `summary()`.
* `zu_storage()` and `zu_from_storage()` expose the raw payload.
