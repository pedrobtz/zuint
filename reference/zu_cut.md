# Cut a zuint vector into intervals

[`cut()`](https://rdrr.io/r/base/cut.html) of a zuint or
[`decimal128()`](https://pedrobtz.github.io/zuint/reference/decimal128.md)
vector compares each value with the breaks exactly, so values beyond
2^53 fall in the interval they belong to. Base
[`cut()`](https://rdrr.io/r/base/cut.html) reads such a vector's raw
bits.

## Arguments

- x:

  A zuint or `decimal128` vector.

- breaks:

  At least two breaks, in any order.

- labels:

  `NULL` for the default labels, `FALSE` for integer codes, or one label
  for each interval.

- include.lowest:

  Whether the lowest break (the highest, when `right = FALSE`) belongs
  to its interval.

- right:

  Whether the intervals are closed on the right.

- dig.lab:

  Accepted for compatibility; the labels are not rounded.

- ordered_result:

  Whether the factor is ordered.

- ...:

  Not used.

## Value

A factor, or an integer vector for `labels = FALSE`; `NA` for a value
outside every interval and for `NA`.

## Details

The arguments are those of
[`base::cut.default()`](https://rdrr.io/r/base/cut.html). `breaks` is a
zuint vector or a number vector, in any order; the values are compared
with it as `x > b` and `x <= b` are, never through a double. The default
labels write each break in full, so `dig.lab` is accepted and not used.

A single number of intervals as `breaks` is refused with a
`zuint_unsupported_error`: base derives the breaks from the range with a
fractional step, which a vector of integers cannot hold. Give the
breaks. Breaks that are `NA`, repeated or not numbers, a `labels` vector
of the wrong length and a flag that is not `TRUE` or `FALSE` are a
`zuint_type_error`.

## Examples

``` r
x <- int64(c("9007199254740993", "9007199254740994", "-5"))
cut(x, int64(c("-10", "9007199254740993", "9007199254740995")))
#> [1] (-10,9007199254740993]              (9007199254740993,9007199254740995]
#> [3] (-10,9007199254740993]             
#> Levels: (-10,9007199254740993] (9007199254740993,9007199254740995]
cut(x, c(-10, 0, 1e16), labels = FALSE)
#> [1] 2 2 1
```
