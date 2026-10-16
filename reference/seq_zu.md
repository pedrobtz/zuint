# Exact sequences

`seq_zu()` is [`seq()`](https://rdrr.io/r/base/seq.html) for zuint
vectors: `from`, `from + by`, ... up to `to`, or `length.out` values,
computed exactly in the common type of the arguments.

## Usage

``` r
seq_zu(from, to = NULL, by = 1L, length.out = NULL)
```

## Arguments

- from, to:

  The ends: zuint vectors or integers, length 1.

- by:

  The step, length 1, not zero.

- length.out:

  The number of values, instead of `to`.

## Value

A zuint vector.

## Examples

``` r
seq_zu(uint64("18446744073709551600"), uint64("18446744073709551614"), by = 7L)
#> <uint64[3]>
#> [1] 18446744073709551600 18446744073709551607 18446744073709551614
seq_zu(int128(-2), by = int128("1000000000000000000000"), length.out = 3)
#> <int128[3]>
#> [1]                     -2  999999999999999999998 1999999999999999999998
```
