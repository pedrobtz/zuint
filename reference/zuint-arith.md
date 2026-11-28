# Arithmetic with an explicit overflow policy

The operators `+`, `-`, `*`, `%/%`, `%%`, `^` and unary minus give `NA`
with one warning of class `zuint_overflow_warning` per call when a
result is out of range. These functions choose differently:

## Usage

``` r
checked_add(x, y)

checked_sub(x, y)

checked_mul(x, y)

checked_idiv(x, y)

checked_mod(x, y)

checked_pow(x, y)

checked_neg(x)

wrapping_add(x, y)

wrapping_sub(x, y)

wrapping_mul(x, y)

wrapping_pow(x, y)

wrapping_neg(x)
```

## Arguments

- x, y:

  zuint vectors, or a zuint vector and a logical, integer or double
  vector. They are recycled.

## Value

A zuint vector of the common type; for `checked_pow()` and
`wrapping_pow()`, of the base's type when the base is a zuint vector.

## Details

- `checked_*()` raise an error of class `zuint_overflow_error` instead.

- `wrapping_*()` compute modulo \\2^{64}\\ or \\2^{128}\\, for hashing
  and checksums. A result that wraps onto the type's `NA` bit pattern is
  `NA`: `NA`-ness never depends on the policy. A negative integer
  operand of an unsigned type wraps too.

Operands take their common type first (see
[`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md)).
`%/%` rounds towards negative infinity and `%%` takes the sign of the
divisor, as in R; division by zero is `NA`, except in `checked_idiv()`
and `checked_mod()`, where it is an error of class
`zuint_division_error`. `/` divides in double. `^` is exact for a
non-negative integer exponent, however large (at or past the type's
width, only the bases 0, 1 and -1 have an answer; any other overflows),
and computed in double otherwise. `checked_pow()` and `wrapping_pow()`
have no double result: a negative or fractional exponent is an error of
class `zuint_type_error`. `NA ^ 0` and `1 ^ NA` are 1, as in base R.
Comparison is exact across all the types and doubles.

[`sum()`](https://rdrr.io/r/base/sum.html) of the integer types is exact
and keeps the type. [`mean()`](https://rdrr.io/r/base/mean.html) and
[`median()`](https://rdrr.io/r/stats/median.html) return a double: the
exact mean, rounded once to the nearest double with ties to even. They
do not warn when that rounds, as base R's
[`mean()`](https://rdrr.io/r/base/mean.html) and DuckDB's `avg()` do
not; a result past 2^53 may differ from the exact mean. For the exact
answer use [`sum()`](https://rdrr.io/r/base/sum.html) and divide in
integers, for example `sum(x) %/% length(x)` with `sum(x) %% length(x)`
for the remainder. `x / 1L` and `x ^ 0.5` are double too.

int128 and uint128 have no common type, nor do int64 and uint128, so
mixing them in arithmetic or [`c()`](https://rdrr.io/r/base/c.html) is
an error of class `zuint_incompatible_error`. No fixed-width type holds
both ranges (int128 is -2^127 to 2^127 - 1, uint128 is 0 to 2^128 - 1).
Choosing one side would overflow the other without notice, choosing by
the data would make the result's type depend on values, and double is
lossy. The cast is the statement of which range you accept: `int128(y)`
or `uint128(x)`, where values out of range become `NA` with a
`zuint_cast_warning`. Comparison is exempt: `x < y` across the two types
is exact and never an error.

## Examples

``` r
x <- int64("9223372036854775807")
x + 1L
#> Warning: 1 result is out of range. NA produced.
#> <int64[1]>
#> [1] NA
try(checked_add(x, 1L))
#> Error in checked_add(x, 1L) : 1 result is out of range.
wrapping_add(x, 2L)
#> <int64[1]>
#> [1] -9223372036854775807
wrapping_mul(uint64("18446744073709551614"), 31L)
#> <uint64[1]>
#> [1] 18446744073709551554
checked_pow(int128(2), 126L)
#> <int128[1]>
#> [1] 85070591730234615865843651857942052864
```
