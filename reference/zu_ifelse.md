# Helpers for code that drops the class

Base functions that build their result from the values without their
class, such as [`ifelse()`](https://rdrr.io/r/base/ifelse.html) and
[`vapply()`](https://rdrr.io/r/base/lapply.html), read a zuint vector's
raw bits as numbers. These helpers do the same jobs and keep the type.

## Usage

``` r
zu_ifelse(test, yes, no)

zu_vapply(X, FUN, FUN.VALUE, ...)
```

## Arguments

- test:

  A logical vector.

- yes, no:

  Values for `TRUE` and `FALSE`, recycled to `test`.

- X:

  A vector or list.

- FUN:

  A function.

- FUN.VALUE:

  A zuint or `decimal128` vector of the length each result must have.

- ...:

  More arguments to `FUN`.

## Value

A zuint vector.

## Details

`zu_ifelse()` takes `yes` and `no` to their common type (see
[`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md))
and is `NA` where `test` is. `zu_vapply()` calls `FUN` on each element
of `X` and requires each result to have the length of `FUN.VALUE`, a
zuint prototype such as `int64(0)`; the results take its type. Both take
[`decimal128()`](https://pedrobtz.github.io/zuint/reference/decimal128.md)
vectors too: `zu_ifelse()` combines `yes` and `no` as
[`c()`](https://rdrr.io/r/base/c.html) does, and `zu_vapply()` converts
each result to the type of `FUN.VALUE` as `x[i] <- value` does, exactly
or `NA`.

The same goes for [`sum()`](https://rdrr.io/r/base/sum.html),
[`min()`](https://rdrr.io/r/base/Extremes.html),
[`max()`](https://rdrr.io/r/base/Extremes.html),
[`range()`](https://rdrr.io/r/base/range.html) and the other `Summary`
functions, which R dispatches on their first argument only:
`sum(int128(5), 1L)` is exact, while `sum(1L, int128(5))` reads the raw
bits. Put the zuint vector first.

## Examples

``` r
x <- int64(c("-9223372036854775807", "5", NA))
zu_ifelse(x > 0L, x, int64(0))
#> <int64[3]>
#> [1]  0  5 NA
zu_vapply(1:3, function(i) uint64(2)^i, uint64(0))
#> <uint64[3]>
#> [1] 2 4 8
```
