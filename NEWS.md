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
* Exact arithmetic: `+`, `-`, `*`, `%/%` (floor), `%%` (sign of the
  divisor), `^` with a non-negative integer exponent, unary minus, `abs()`
  and `sign()`. An out-of-range result is `NA` with one
  `zuint_overflow_warning` per call. `/` and other `Math` functions compute
  in double.
* `checked_add()`, `checked_sub()`, `checked_mul()`, `checked_pow()` and
  `checked_neg()` raise a `zuint_overflow_error` instead, and
  `checked_idiv()` and `checked_mod()` a `zuint_division_error` on a zero
  divisor;
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
* With zuarrow installed, zuint registers its four types with zuarrow's
  registry, so `zuarrow::arrow_to_r()`, `zuarrow::arrow_read()` and
  `zuarrow::arrow_array()` read and write `int64`, `uint64` and DuckDB's
  `arrow.opaque` `hugeint`/`uhugeint` exactly (`?zuint-arrow`). A value
  equal to a type's `NA` bit pattern follows zuarrow's `lossy` policy: an
  error by default, `NA` with a warning under `lossy = "warn"`.
* The Arrow and DuckDB functions of the development versions are gone, each
  replaced by zuarrow:
  * `zu_from_arrow()` and `zu_to_arrow()`: `zuarrow::arrow_to_r()` and
    `zuarrow::arrow_array()`. `decimal128(p, 0)` reads as `int128` with
    `to = int128()`; the `decimal = TRUE` export has no replacement.
  * `zu_sentinel_check()`: the `zuarrow_lossy_error` that
    `zuarrow::arrow_to_r()` raises.
  * `zu_duckdb_query()`: `zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))`
    after `SET arrow_lossless_conversion = true`.
  * `zu_duckdb_register()`, `zu_arrow_table()` and `zu_from_arrow_table()`:
    `zuarrow::arrow_stream()`, `zuarrow::arrow_write()` and
    `zuarrow::arrow_read()`.
  * The nanoarrow methods (`convert_array()`, `as_nanoarrow_array()`,
    `infer_nanoarrow_schema()`) and the arrow methods (`as_arrow_array()`,
    `infer_type()`): zuarrow, which reads and writes nanoarrow handles.
* `zu_storage()` and `zu_from_storage()` document the payload shapes and
  `NA` bit patterns as the public representation contract.
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
* `rep()` of an empty vector pads with the type's `NA` (#55); `range()`
  takes `finite`, which drops `NA` (#56); under
  `options(zuint.double = "allow")`, `sum()`, `prod()`, `min()`, `max()`
  and `range()` give base R's double answer (#60); `zu_match()` and
  `%zin%` treat a value the common type cannot hold as no match, as
  `match()` does (#58); `seq_zu()` counts in the elements' own type, so it
  reaches the top of the unsigned ranges (#59).
* The Arrow import refuses a schema whose format is not the array's own
  (`zuint_arrow_error`), which would have read past the data (#61).
* A C table for other packages, `zuint_api_v1` in `inst/include/zuint.h`,
  resolved through `zuint-r.h`: DuckDB's fixed-point `DECIMAL(p, s)` on a
  128-bit coefficient (parse, format, rescale, compare, and conversion to
  and from double, each as DuckDB 2.0.1 does it, with two of DuckDB's bugs
  fixed), and checked 128-bit arithmetic. `zuint.h` includes no R header,
  and every member is safe on any thread (#103).
* `decimal128()` holds DuckDB's `DECIMAL(p, s)` exactly, with
  `is_decimal128()`, `decimal_precision()` and `decimal_scale()`. `+`, `-`,
  `*`, `round()`, `floor()`, `ceiling()`, `trunc()`, `cumsum()`, `c()`,
  `x[i] <- value` and vctrs give DuckDB's result types, and only
  `decimal128()` rounds a value into one; comparison is exact across
  scales and with any integer or double; `match()`, `%in%` and
  `zu_match()` find equal values whatever their scales; `/`, `mean()` and
  the other `Math` functions give doubles; and sorting, hashing, `sum()`,
  `min()` and `max()` work on the coefficients (#104, #108 to #129).
* With vctrs, dplyr and tibble: zuint columns combine by the promotion order,
  cast exactly, arrange, group, summarise, bind and print. data.table keys
  on `int64` natively.
* `zu_ifelse()` and `zu_vapply()` keep the type where `ifelse()` and
  `vapply()` would read raw bits. `unique()` drops names, as base R's does.
* A getting-started vignette, and benchmarks against bit64 in the README.
