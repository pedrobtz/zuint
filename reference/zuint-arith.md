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

A zuint vector of the common type.

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
non-negative integer exponent and computed in double otherwise.
Comparison is exact across all the types and doubles.

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
