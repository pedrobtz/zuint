# Missing values of each type

The `NA` of each zuint type, a vector of length one.

## Usage

``` r
NA_int64_

NA_uint64_

NA_int128_

NA_uint128_
```

## Format

A zuint vector of length 1.

## Examples

``` r
is.na(NA_int64_)
#> [1] TRUE
c(int64(1), NA_int64_)
#> <int64[2]>
#> [1]  1 NA
```
