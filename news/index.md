# Changelog

## zuint 0.0.0.9000

- [`int64()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
  [`uint64()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
  [`int128()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md)
  and
  [`uint128()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md)
  create signed and unsigned 64- and 128-bit integer vectors from
  logical, integer, double, decimal character, bit64 `integer64` and
  each other. Conversion is exact or gives `NA` with a
  `zuint_cast_warning`; it never rounds or clamps.
- `int64` has class `c("zu_int64", "integer64")` and bit64’s storage, so
  code that reads `integer64` reads it unchanged.
- `NA_int64_`, `NA_uint64_`, `NA_int128_` and `NA_uint128_`.
- The base vector protocol for all four types: subsetting and assignment
  (with exact casting of the assigned value),
  [`c()`](https://rdrr.io/r/base/c.html),
  [`rep()`](https://rdrr.io/r/base/rep.html),
  [`rev()`](https://rdrr.io/r/base/rev.html), `length<-`,
  [`is.na()`](https://rdrr.io/r/base/NA.html),
  [`anyNA()`](https://rdrr.io/r/base/NA.html),
  [`as.character()`](https://rdrr.io/r/base/character.html),
  [`as.double()`](https://rdrr.io/r/base/double.html) (with a
  `zuint_precision_warning` when it rounds),
  [`as.integer()`](https://rdrr.io/r/base/integer.html),
  [`as.logical()`](https://rdrr.io/r/base/logical.html),
  [`as.list()`](https://rdrr.io/r/base/list.html), data frame columns,
  [`format()`](https://rdrr.io/r/base/format.html),
  [`print()`](https://rdrr.io/r/base/print.html),
  [`str()`](https://rdrr.io/r/utils/str.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html).
- Exact arithmetic: `+`, `-`, `*`, `%/%` (floor), `%%` (sign of the
  divisor), `^` with a non-negative integer exponent, unary minus,
  [`abs()`](https://rdrr.io/r/base/MathFun.html) and
  [`sign()`](https://rdrr.io/r/base/sign.html). An out-of-range result
  is `NA` with one `zuint_overflow_warning` per call. `/` and other
  `Math` functions compute in double.
- [`checked_add()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`checked_sub()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`checked_mul()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`checked_pow()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`checked_neg()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  raise a `zuint_overflow_error` instead, and
  [`checked_idiv()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`checked_mod()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  a `zuint_division_error` on a zero divisor;
  [`wrapping_add()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`wrapping_sub()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`wrapping_mul()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`wrapping_pow()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`wrapping_neg()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  compute modulo 2^64 or 2^128.
- Mixed types follow a lossless promotion order
  ([`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md)),
  in arithmetic and in [`c()`](https://rdrr.io/r/base/c.html). A double
  must be integral and in range, unless
  `options(zuint.double = "allow")`.
- Comparison is exact across all types and doubles: `int64(1) == 1.5` is
  `FALSE`, and nothing is compared through double.
- The constructors read `0x` hex and `0b` binary as well as decimal,
  with an optional sign, `_` between digits and surrounding whitespace;
  `"NA"` and blank strings are `NA`. Exponents are not accepted.
- [`format_hex()`](https://pedrobtz.github.io/zuint/reference/format_hex.md)
  and
  [`format_bin()`](https://pedrobtz.github.io/zuint/reference/format_hex.md),
  with `pad = TRUE` for the full width;
  [`format()`](https://rdrr.io/r/base/format.html) takes `width` and
  `big.mark`; [`print()`](https://rdrr.io/r/base/print.html) stops at
  `getOption("max.print")`.
- Bit operations:
  [`bit_and()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`bit_or()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`bit_xor()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`bit_not()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`shift_left()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`shift_right()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`popcount()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`clz()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md)
  and
  [`ctz()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md).
- With zuarrow installed, zuint registers its four types with zuarrow’s
  registry, so
  [`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html),
  [`zuarrow::arrow_read()`](https://pedrobtz.github.io/zuarrow/reference/arrow_read.html)
  and
  [`zuarrow::arrow_array()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html)
  read and write `int64`, `uint64` and DuckDB’s `arrow.opaque`
  `hugeint`/`uhugeint` exactly (`?zuint-arrow`). A value equal to a
  type’s `NA` bit pattern follows zuarrow’s `lossy` policy: an error by
  default, `NA` with a warning under `lossy = "warn"`.
- The Arrow and DuckDB functions of the development versions are gone,
  each replaced by zuarrow:
  - `zu_from_arrow()` and `zu_to_arrow()`:
    [`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html)
    and
    [`zuarrow::arrow_array()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html).
    `decimal128(p, 0)` reads as `int128` with `to = int128()`; the
    `decimal = TRUE` export has no replacement.
  - `zu_sentinel_check()`: the `zuarrow_lossy_error` that
    [`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html)
    raises.
  - `zu_duckdb_query()`:
    `zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))` after
    `SET arrow_lossless_conversion = true`.
  - `zu_duckdb_register()`, `zu_arrow_table()` and
    `zu_from_arrow_table()`:
    [`zuarrow::arrow_stream()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html),
    [`zuarrow::arrow_write()`](https://pedrobtz.github.io/zuarrow/reference/arrow_write.html)
    and
    [`zuarrow::arrow_read()`](https://pedrobtz.github.io/zuarrow/reference/arrow_read.html).
  - The nanoarrow methods (`convert_array()`, `as_nanoarrow_array()`,
    `infer_nanoarrow_schema()`) and the arrow methods
    (`as_arrow_array()`, `infer_type()`): zuarrow, which reads and
    writes nanoarrow handles.
- [`zu_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
  and
  [`zu_from_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
  document the payload shapes and `NA` bit patterns as the public
  representation contract.
- [`as_integer64()`](https://pedrobtz.github.io/zuint/reference/as_integer64.md)
  returns a plain bit64 `integer64`.
- [`sort()`](https://rdrr.io/r/base/sort.html), and base
  [`order()`](https://rdrr.io/r/base/order.html) and
  [`rank()`](https://rdrr.io/r/base/rank.html) through an exact
  [`xtfrm()`](https://rdrr.io/r/base/xtfrm.html), with a stable radix
  sort; [`unique()`](https://rdrr.io/r/base/unique.html),
  [`duplicated()`](https://rdrr.io/r/base/duplicated.html) and
  [`anyDuplicated()`](https://rdrr.io/r/base/duplicated.html) with an
  exact hash; [`match()`](https://rdrr.io/r/base/match.html), `%in%` and
  [`table()`](https://rdrr.io/r/base/table.html) compare exact values,
  and
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  and `%zin%` do it faster.
- [`sum()`](https://rdrr.io/r/base/sum.html) is type stable and exact,
  `NA` with a warning when the total does not fit;
  [`prod()`](https://rdrr.io/r/base/prod.html),
  [`cumsum()`](https://rdrr.io/r/base/cumsum.html),
  [`cumprod()`](https://rdrr.io/r/base/cumsum.html),
  [`cummax()`](https://rdrr.io/r/base/cumsum.html) and
  [`cummin()`](https://rdrr.io/r/base/cumsum.html);
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html) and
  [`range()`](https://rdrr.io/r/base/range.html) are exact;
  [`mean()`](https://rdrr.io/r/base/mean.html) and
  [`median()`](https://rdrr.io/r/stats/median.html) are doubles from the
  exact values; [`diff()`](https://rdrr.io/r/base/diff.html) and
  [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md).
- [`summary()`](https://rdrr.io/r/base/summary.html) adds the median and
  the mean.
- [`rep()`](https://rdrr.io/r/base/rep.html) of an empty vector pads
  with the type’s `NA`
  ([\#55](https://github.com/pedrobtz/zuint/issues/55));
  [`range()`](https://rdrr.io/r/base/range.html) takes `finite`, which
  drops `NA` ([\#56](https://github.com/pedrobtz/zuint/issues/56));
  under `options(zuint.double = "allow")`,
  [`sum()`](https://rdrr.io/r/base/sum.html),
  [`prod()`](https://rdrr.io/r/base/prod.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html) and
  [`range()`](https://rdrr.io/r/base/range.html) give base R’s double
  answer ([\#60](https://github.com/pedrobtz/zuint/issues/60));
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  and `%zin%` treat a value the common type cannot hold as no match, as
  [`match()`](https://rdrr.io/r/base/match.html) does
  ([\#58](https://github.com/pedrobtz/zuint/issues/58));
  [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md)
  counts in the elements’ own type, so it reaches the top of the
  unsigned ranges ([\#59](https://github.com/pedrobtz/zuint/issues/59)).
- The Arrow import refuses a schema whose format is not the array’s own
  (`zuint_arrow_error`), which would have read past the data
  ([\#61](https://github.com/pedrobtz/zuint/issues/61)).
- A C table for other packages, `zuint_api_v1` in
  `inst/include/zuint.h`, resolved through `zuint-r.h`: DuckDB’s
  fixed-point `DECIMAL(p, s)` on a 128-bit coefficient (parse, format,
  rescale, compare, and conversion to and from double, each as DuckDB
  2.0.1 does it, with two of DuckDB’s bugs fixed), and checked 128-bit
  arithmetic. `zuint.h` includes no R header, and every member is safe
  on any thread ([\#103](https://github.com/pedrobtz/zuint/issues/103)).
- With vctrs, dplyr and tibble: zuint columns combine by the promotion
  order, cast exactly, arrange, group, summarise, bind and print.
  data.table keys on `int64` natively.
- [`zu_ifelse()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
  and
  [`zu_vapply()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
  keep the type where [`ifelse()`](https://rdrr.io/r/base/ifelse.html)
  and [`vapply()`](https://rdrr.io/r/base/lapply.html) would read raw
  bits.
- A getting-started vignette, and benchmarks against bit64 in the
  README.
