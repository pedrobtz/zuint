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
- [`zu_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
  and
  [`zu_from_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
  expose the raw payload.
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
  raise a `zuint_overflow_error` instead;
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
- [`zu_from_arrow()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)
  and
  [`zu_to_arrow()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)
  convert through the Arrow C Data Interface with no R package in
  between: `int64`, `uint64`, DuckDB’s `arrow.opaque`
  `hugeint`/`uhugeint`, and `decimal128(p, 0)`.
  [`zu_sentinel_check()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)
  counts engine values that would import as `NA`.
- With nanoarrow installed, `nanoarrow::convert_array(array, int64())`
  and the other prototypes import through the bridge, and
  [`nanoarrow::as_nanoarrow_array()`](https://arrow.apache.org/nanoarrow/latest/r/reference/as_nanoarrow_array.html)
  exports zuint vectors.
