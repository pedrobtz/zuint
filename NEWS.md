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
* Exact arithmetic: `+`, `-`, `*`, `%/%` (floor), `%%` (sign of the
  divisor), `^` with a non-negative integer exponent, unary minus, `abs()`
  and `sign()`. An out-of-range result is `NA` with one
  `zuint_overflow_warning` per call. `/` and other `Math` functions compute
  in double.
* `checked_add()`, `checked_sub()`, `checked_mul()`, `checked_pow()` and
  `checked_neg()` raise a `zuint_overflow_error` instead;
  `wrapping_add()`, `wrapping_sub()`, `wrapping_mul()`, `wrapping_pow()`
  and `wrapping_neg()` compute modulo 2^64 or 2^128.
* Mixed types follow a lossless promotion order (`zu_common_type()`), in
  arithmetic and in `c()`. A double must be integral and in range, unless
  `options(zuint.double = "allow")`.
* Comparison is exact across all types and doubles: `int64(1) == 1.5` is
  `FALSE`, and nothing is compared through double.
* The constructors read `0x` hex and `0b` binary as well as decimal, with an
  optional sign, `_` between digits and surrounding whitespace; `"NA"` and
  blank strings are `NA`. Exponents are not accepted.
* `format_hex()` and `format_bin()`, with `pad = TRUE` for the full width;
  `format()` takes `width` and `big.mark`; `print()` stops at
  `getOption("max.print")`.
* Bit operations: `bit_and()`, `bit_or()`, `bit_xor()`, `bit_not()`,
  `shift_left()`, `shift_right()`, `popcount()`, `clz()` and `ctz()`.
* `zu_from_arrow()` and `zu_to_arrow()` convert through the Arrow C Data
  Interface with no R package in between: `int64`, `uint64`, DuckDB's
  `arrow.opaque` `hugeint`/`uhugeint`, and `decimal128(p, 0)`.
  `zu_sentinel_check()` counts engine values that would import as `NA`.
* With nanoarrow installed, `nanoarrow::convert_array(array, int64())` and
  the other prototypes import through the bridge, and
  `nanoarrow::as_nanoarrow_array()` exports zuint vectors.
* `zu_duckdb_query()` reads DuckDB results with `BIGINT`, `UBIGINT`,
  `HUGEINT` and `UHUGEINT` columns as zuint vectors, exactly, and
  `zu_duckdb_register()` writes them back with their types.
* `zu_arrow_table()` and `zu_from_arrow_table()` carry zuint columns
  through Arrow Tables, and so through Parquet files. With arrow loaded,
  `arrow::as_arrow_array()` and `arrow::infer_type()` work for `int64` and
  `uint64`.
* `as_integer64()` returns a plain bit64 `integer64`.
* `sort()`, and base `order()` and `rank()` through an exact `xtfrm()`,
  with a stable radix sort; `unique()`, `duplicated()` and
  `anyDuplicated()` with an exact hash; `match()`, `%in%` and `table()`
  compare exact values, and `zu_match()` and `%zin%` do it faster.
* `sum()` is type stable and exact, `NA` with a warning when the total does
  not fit; `prod()`, `cumsum()`, `cumprod()`, `cummax()` and `cummin()`;
  `min()`, `max()` and `range()` are exact; `mean()` and `median()` are
  doubles from the exact values; `diff()` and `seq_zu()`.
* `summary()` adds the median and the mean.
* With vctrs, dplyr and tibble: zuint columns combine by the promotion order,
  cast exactly, arrange, group, summarise, bind and print. data.table keys
  on `int64` natively.
* `zu_ifelse()` and `zu_vapply()` keep the type where `ifelse()` and
  `vapply()` would read raw bits.
* A getting-started vignette, and benchmarks against bit64 in the README.
