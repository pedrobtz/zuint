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
