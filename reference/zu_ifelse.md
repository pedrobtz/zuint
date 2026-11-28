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

## Base functions that cannot dispatch

R dispatches most functions on their first argument only, and some read
a vector's payload without dispatching at all. Design 4.1 accepts that
cost. Each function below returns the raw bits of the values, or drops
their class, so the answer is wrong, often with no warning. For
`decimal128` the bits are the scaled coefficients.

- [`c()`](https://rdrr.io/r/base/c.html) and
  [`rbind()`](https://rdrr.io/r/base/cbind.html) of data frames with a
  non-zuint first argument or first column: `c(1L, int128(5))` is
  complex bits, as is
  `rbind(data.frame(x = 1L), data.frame(x = int128(5)))`. Put the zuint
  vector first, or use
  [`vctrs::vec_rbind()`](https://vctrs.r-lib.org/reference/vec_bind.html)
  or
  [`dplyr::bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html).

- [`sum()`](https://rdrr.io/r/base/sum.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html),
  [`range()`](https://rdrr.io/r/base/range.html) and the other `Summary`
  functions read only the first argument's class: `sum(int128(5), 1L)`
  is exact and `sum(1L, int128(5))` reads the raw bits. Put the zuint
  vector first.

- [`is.unsorted()`](https://rdrr.io/r/base/is.unsorted.html): use
  `is.unsorted(xtfrm(x))`, whose ranks are exact.

- [`complete.cases()`](https://rdrr.io/r/stats/complete.cases.html)
  reads the payload's NaN patterns, so its answer is inverted for
  negative `int64` values: use `!is.na(x)` on each column.

- [`aggregate()`](https://rdrr.io/r/stats/aggregate.html) and
  [`rowsum()`](https://rdrr.io/r/base/rowsum.html) read the payload, as
  a group or as the values. A negative `int64` group vanishes. Group by
  `as.character(x)`, and sum each group with
  `zu_vapply(split(x, g), sum, x[0])`.

- [`var()`](https://rdrr.io/r/stats/cor.html) and
  [`cor()`](https://rdrr.io/r/stats/cor.html) read the payload:
  `var(int64(1:10))` is 0. Use `var(as.double(x))`, which rounds to a
  double. [`sd()`](https://rdrr.io/r/stats/sd.html) is right.

- [`unlist()`](https://rdrr.io/r/base/unlist.html),
  [`sapply()`](https://rdrr.io/r/base/lapply.html) and
  [`vapply()`](https://rdrr.io/r/base/lapply.html) drop the class. Use
  `do.call(c, list)` and `zu_vapply()`.

- [`ifelse()`](https://rdrr.io/r/base/ifelse.html): use `zu_ifelse()`.

- [`formatC()`](https://rdrr.io/r/base/formatc.html) and `sprintf("%f")`
  read the bits (`sprintf("%d")` is an error). Use
  [`format()`](https://rdrr.io/r/base/format.html),
  [`as.character()`](https://rdrr.io/r/base/character.html) or
  [`format_hex()`](https://pedrobtz.github.io/zuint/reference/format_hex.md);
  [`paste()`](https://rdrr.io/r/base/paste.html) and `sprintf("%s")` are
  right.

- A zuint vector as an index or a count of a base function that does not
  dispatch on it: `letters[int64(2)]`, `rep(1, int64(3))`,
  [`rep_len()`](https://rdrr.io/r/base/rep.html),
  [`seq_len()`](https://rdrr.io/r/base/seq.html),
  [`numeric()`](https://rdrr.io/r/base/numeric.html) and
  [`vector()`](https://rdrr.io/r/base/vector.html) are empty, and an
  `int128` index is an error. Pass `as.integer(i)`. A zuint vector as
  the vector being indexed, or as
  [`rep()`](https://rdrr.io/r/base/rep.html)'s `x`, is right.

- [`base::matrix()`](https://rdrr.io/r/base/matrix.html),
  [`base::array()`](https://rdrr.io/r/base/array.html),
  [`base::outer()`](https://rdrr.io/r/base/outer.html) and
  [`diag()`](https://rdrr.io/r/base/diag.html) return the raw bits.
  zuint vectors do not form matrices, and the functions that dispatch
  refuse them with a `zuint_unsupported_error`: `%*%`,
  [`base::crossprod()`](https://rdrr.io/r/base/crossprod.html) and
  [`base::tcrossprod()`](https://rdrr.io/r/base/crossprod.html) (the
  last two from R 4.4.0),
  [`cbind()`](https://rdrr.io/r/base/cbind.html),
  [`rbind()`](https://rdrr.io/r/base/cbind.html),
  [`as.matrix()`](https://rdrr.io/r/base/matrix.html),
  [`aperm()`](https://rdrr.io/r/base/aperm.html) and
  [`scale()`](https://rdrr.io/r/base/scale.html).

- [`base::match()`](https://rdrr.io/r/base/match.html), `%in%`,
  [`base::table()`](https://rdrr.io/r/base/table.html),
  [`merge()`](https://rdrr.io/r/base/merge.html) and the set functions
  compare a bare double as text: see
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md).

- [`cut()`](https://rdrr.io/r/base/cut.html) has a method: see
  [zu_cut](https://pedrobtz.github.io/zuint/reference/zu_cut.md).

## Padding data frames and data.table

Base R fills new rows with its own `NA`, whose bits are a valid `int64`,
`uint64`, `int128` or `uint128` value. Growing a data frame by row
(`d[nrow(d) + 2, "id"] <- 7L`, through
[`xpdrows.data.frame()`](https://rdrr.io/r/base/dataframeHelpers.html))
strips the class and fills the new rows of every zuint column with that
value, not `NA`. The same holds for data.table's
`rbindlist(fill = TRUE)`, `d[c(1, NA)]`, `shift()` and `:= NA` on
`uint64`, `int128` and `uint128` columns, and a data.table `by` groups
the `NA` of a `uint64` column with its neighbouring value (bit64 pads
`int64` in base data frames the same way). No zuint method is reached.

These pad correctly: [`rbind()`](https://rdrr.io/r/base/cbind.html) of
data frames with a zuint first column,
[`merge()`](https://rdrr.io/r/base/merge.html),
[`vctrs::vec_rbind()`](https://vctrs.r-lib.org/reference/vec_bind.html)
and
[`dplyr::bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html).
With data.table, fill and join on
[`as.character()`](https://rdrr.io/r/base/character.html) of the column,
or convert the column after the operation. An `int64` column works
natively in data.table.

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
