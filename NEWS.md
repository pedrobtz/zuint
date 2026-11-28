# zuint 0.0.0.9000

* `cut()` of a zuint or decimal vector compares exactly against the breaks,
  zuint or numbers, with base's `labels`, `right`, `include.lowest` and
  `ordered_result`; the default labels write the breaks in full. A single
  number of intervals is a `zuint_unsupported_error` (#165).
* The help says what base R cannot dispatch (#149, #162, #165): `?zu_match`
  no longer claims base `match()` and `%in%` agree with it, because a bare
  double is compared as text, and `?zu_ifelse` lists the base functions
  that read the payload, each with its zuint route, and the data-frame and
  data.table row padding that writes R's NA bits as a value.
* Arguments zuint methods ignored are now honoured or refused (#163):
  `mean()` and `median()` read `na.rm` as a logical (`NA` or text is a
  `zuint_type_error`); `sort()` returns `list(x, ix)` for `index.return =
  TRUE`, checks `na.last`, and refuses `partial` with a
  `zuint_unsupported_error`; `duplicated()`, `unique()` and
  `anyDuplicated()` honour `incomparables`; `format()` honours
  `big.interval`, `zero.print`, `trim` and a textual `width`, and
  `format(big.mark = ".")` no longer warns under `options(OutDec = ",")`;
  `diff()` refuses a `lag` or `differences` below 1 or fractional;
  `zu_match()` refuses a `nomatch` of length other than one; `print()`
  accepts `quote` and truncates a fractional `max` as base R does, and
  refuses a missing, negative or non-numeric one.
* `seq_zu()` and `seq()` of a zuint vector no longer ignore `to` when
  `length.out` is given: the whole step between them is computed, and a
  fractional one is a `zuint_type_error`. The step defaults to -1 when `to`
  is below `from`, `seq(n)` is `1:n`, and a fractional `length.out` rounds up
  as in base R; a negative or `NA` one is a `zuint_type_error` (#159).
* `round()` and `signif()` take a fractional `digits` as base R does (round
  half up, so `round(x, 2.5)` rounds to 3 digits), and an infinite or very
  large one no longer fails with an unclassed error; an `NA` `digits` is a
  `zuint_type_error` (#157).
* `x ^ y` with an integral double exponent of 2^128 or more stays in the
  type: 0, 1 and -1 have their exact answers and any other base overflows.
  `NA ^ 0` and `1 ^ NA` are 1, as in base R and bit64 (#158).
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
* `mean()` and `median()` of every type, decimals included, are the exact
  mean rounded once to the nearest double; they had rounded the sum first,
  so a mean could lie above `max()` (#148).
* DuckDB's `arrow.opaque` extension is recognised by reading its JSON as
  DuckDB does: the top-level `vendor_name` must be `"DuckDB"` and the
  top-level `type_name` `"hugeint"` or `"uhugeint"`, escapes decoded.
  Another vendor's type, or a `type_name` nested deeper, no longer reads
  as `int128`, and DuckDB's own metadata with the keys in another order or
  written with escapes no longer reads as raw bytes. A decimal under any
  other `arrow.opaque` type no longer reads as `int128` (#154).
* `to = int64()` and `to = uint64()` read 8-, 16- and 32-bit integer
  columns exactly: `-2147483648` had been lost as R's `NA_integer_` (#155).
* The Arrow decimal format `d:P,S` is read in the specification's form
  only: a precision or scale past `INT_MAX` no longer wraps into range, and
  signs and spaces are refused (#156).
* Errors about an Arrow schema are `zuint_arrow_error`, and a schema with
  more than 4096 metadata entries is one too, where a DuckDB `HUGEINT`
  column had silently read as raw bytes (#166).
* A plain bit64 `integer64` operand is read by its values when bit64 is not
  loaded: in `&`, `|` and `xor()`, `zu_match()` and `%zin%`, `zu_ifelse()`'s
  `test`, `checked_idiv()` and `checked_mod()`, `seq_zu()`'s `by`,
  `round()`'s `digits`, comparisons and `&` with a `decimal128`, and vctrs
  casts to every zuint type. Base R had read its bits, where `-1` is `NA`
  and `NA` is a value (#150).
* With bit64 attached, `integer64 * uint64`, `/`, `^` and assigning a
  uint64 into an `integer64` are exact: bit64 had computed on the uint64's
  bits (#151).
* `Conj()`, `Re()`, `Im()`, `Mod()` and `Arg()` are a
  `zuint_unsupported_error` for every type, where they had computed on the
  payload and kept the class (#152).
* A zuint or `integer64` count is read as the number it stands for, as an
  index is: `rep()`'s `times`, `each` and `length.out`, `diff()`'s `lag`
  and `differences`, `head()` and `tail()`, `length<-`, `seq_zu()`'s and
  `seq()`'s `length.out`, and `format()`'s `width`, `print()`'s `max` and
  `str()`'s `vec.len` (#153).
* `%*%`, and from R 4.4.0 `crossprod()` and `tcrossprod()`, are a
  `zuint_unsupported_error` for every type, with or without bit64; for
  int64 the answer had depended on whether bit64 was loaded. `matrix()`,
  `array()`, `outer()` and `diag()` cannot be intercepted, as
  `?zu_ifelse` says (#160).
* With bit64 attached, its `setdiff()`, `union()`, `intersect()`,
  `is.element()` and `setequal()` work on int64: zuint declares
  `zu_int64` a subclass of `integer64` for `methods::as()` (#161).
* `abs()`, `sign()`, the other `Math` functions computed in double, `!`,
  `&`, `|` and the double fallback of `options(zuint.double = "allow")` in
  arithmetic, `^` and `c()` keep names, as base R does (#164).
