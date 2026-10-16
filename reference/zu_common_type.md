# The common type of zuint vectors

The type that mixing these vectors in arithmetic, comparison or
[`c()`](https://rdrr.io/r/base/c.html) gives. Every step is lossless:

## Usage

``` r
zu_common_type(...)
```

## Arguments

- ...:

  zuint vectors, and optionally logical or integer vectors.

## Value

The name of the common type: `"int64"`, `"uint64"`, `"int128"` or
`"uint128"`. With no common type, an error of class
`zuint_incompatible_error`.

## Details

|                                   |                          |
|-----------------------------------|--------------------------|
| x ⊕ y                             | result                   |
| integer ⊕ int64                   | int64                    |
| integer ⊕ uint64                  | uint64                   |
| int64 ⊕ uint64                    | int128                   |
| integer, int64 or uint64 ⊕ int128 | int128                   |
| integer or uint64 ⊕ uint128       | uint128                  |
| int64 or int128 ⊕ uint128         | no common type: an error |

A negative integer meeting an unsigned type is out of range, and the
operation's overflow policy decides what happens to it. A double takes
the type of the zuint operand if every value is integral and in range;
otherwise it is an error of class `zuint_double_error`. Setting
`options(zuint.double = "allow")` makes that a double result with a
warning of class `zuint_double_warning` instead.

## Examples

``` r
zu_common_type(int64(1), uint64(1))
#> [1] "int128"
zu_common_type(uint64(1), 1L)
#> [1] "uint64"
try(zu_common_type(int128(1), uint128(1)))
#> Error in zu_common_type(int128(1), uint128(1)) : 
#>   int128 and uint128 have no common type; convert one explicitly.
```
