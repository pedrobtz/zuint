# Exact, fast matching

`zu_match()` is [`match()`](https://rdrr.io/r/base/match.html) for zuint
vectors, and `%zin%` is `%in%`. Base
[`match()`](https://rdrr.io/r/base/match.html) and `%in%` give the same
answers on zuint vectors, by comparing exact decimal text; these hash
the values themselves and are much faster on long vectors.

## Usage

``` r
zu_match(x, table, nomatch = NA_integer_)

x %zin% table
```

## Arguments

- x:

  Values to look up: a zuint vector, or an integer vector when `table`
  is one.

- table:

  Values to look them up in.

- nomatch:

  The position to give values not in `table`.

## Value

`zu_match()` returns an integer vector of positions in `table`; `%zin%`
a logical vector.

## Details

Both arguments take their common type first (see
[`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md));
`NA` matches `NA`.

## Examples

``` r
zu_match(uint64(c("18446744073709551614", "7")), uint64(c(7, 1)))
#> [1] NA  1
int64(5) %zin% int64(1:10)
#> [1] TRUE
```
