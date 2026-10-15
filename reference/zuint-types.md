# Wide integer vectors

Create signed and unsigned 64-bit and 128-bit integer vectors, or
convert to them. Conversion is exact or gives `NA` with a warning of
class `zuint_cast_warning`; it never rounds or clamps.

## Usage

``` r
int64(x = integer())

uint64(x = integer())

int128(x = integer())

uint128(x = integer())
```

## Arguments

- x:

  A vector to convert.

## Value

A vector of the requested type, the same length as `x`.

## Details

`x` can be a logical, integer, double or character vector, another zuint
vector, or a bit64 `integer64`. A double must be integral and in range.
A string is decimal digits with an optional leading `-`. `NA` stays `NA`
without a warning. Names are kept.

Each type reserves one bit pattern for `NA`, so its range is one value
short of the full width: the most negative value for the signed types
and the largest for the unsigned ones.

|           |                        |
|-----------|------------------------|
| Type      | Range                  |
| `int64`   | \\\pm(2^{63} - 1)\\    |
| `uint64`  | \\\[0, 2^{64} - 2\]\\  |
| `int128`  | \\\pm(2^{127} - 1)\\   |
| `uint128` | \\\[0, 2^{128} - 2\]\\ |

`int64` has class `c("zu_int64", "integer64")` and the storage of
bit64's `integer64`, so code that reads `integer64` reads it too.

## Examples

``` r
int64("9007199254740993")
#> <int64[1]>
#> [1] 9007199254740993
uint64(c(0, 2^53))
#> <uint64[2]>
#> [1]                0 9007199254740992
int128("-170141183460469231731687303715884105727")
#> <int128[1]>
#> [1] -170141183460469231731687303715884105727
uint128(NA)
#> <uint128[1]>
#> [1] NA

# Not exact, so NA with a warning:
int64(1.5)
#> Warning: 1 value could not be represented as int64 and became NA.
#> <int64[1]>
#> [1] NA
```
