# Conditions zuint signals

Every error and warning zuint raises has a class, which is part of its
interface and safe to test for; the message text is not. Each also has
the class `zuint_error` or `zuint_warning`.

## Details

Errors:

- `zuint_type_error`: an argument of the wrong kind.

- `zuint_incompatible_error`: two types with no common type, such as
  `int128` and `uint128` (see
  [`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md)).

- `zuint_double_error`: a double that is not integral or not in range,
  in arithmetic, comparison-free mixing or
  [`c()`](https://rdrr.io/r/base/c.html); see `options(zuint.double)`.

- `zuint_overflow_error`: a result out of range under a `checked_*()`
  function (see
  [`checked_add()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)).

- `zuint_division_error`: a zero divisor in
  [`checked_idiv()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  or
  [`checked_mod()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md).

- `zuint_arrow_error`: an Arrow array zuint cannot read, or a released
  struct (see
  [`zu_from_arrow()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)).

- `zuint_unsupported_error`: an operation zuint does not do, such as
  [`quantile()`](https://rdrr.io/r/stats/quantile.html) or a matrix.

Warnings:

- `zuint_cast_warning`: values that could not be represented became
  `NA`.

- `zuint_overflow_warning`: a result out of range became `NA`.

- `zuint_precision_warning`: a conversion to double rounded.

- `zuint_double_warning`: a double was computed in double, under
  `options(zuint.double = "allow")`.

- `zuint_recycling_warning`: operand lengths are not multiples.

- `zuint_empty_warning`: [`min()`](https://rdrr.io/r/base/Extremes.html)
  or [`max()`](https://rdrr.io/r/base/Extremes.html) of nothing.

## Examples

``` r
tryCatch(int128(1) + uint128(1), zuint_incompatible_error = function(e) "no common type")
#> [1] "no common type"
withCallingHandlers(int64(1.5), zuint_cast_warning = function(w) invokeRestart("muffleWarning"))
#> <int64[1]>
#> [1] NA
```
