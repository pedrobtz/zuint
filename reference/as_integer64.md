# Convert to bit64's integer64

`as_integer64()` returns the values as a plain bit64 `integer64`, for
code that checks the class exactly. `int64` already has bit64's storage,
so for it only the class changes; the other types convert first, exactly
or to `NA` with a warning of class `zuint_cast_warning`. bit64 itself is
not needed.

## Usage

``` r
as_integer64(x)
```

## Arguments

- x:

  A zuint vector or a bit64 `integer64`.

## Value

An `integer64` vector the length of `x`, with its names.

## Details

The other direction is
[`int64()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
which on an `integer64` likewise only swaps the class.

## Examples

``` r
y <- as_integer64(int64("9007199254740993"))
class(y)
#> [1] "integer64"
int64(y)
#> <int64[1]>
#> [1] 9007199254740993
```
