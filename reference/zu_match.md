# Exact, fast matching

`zu_match()` is [`base::match()`](https://rdrr.io/r/base/match.html) for
zuint vectors, and `%zin%` is `%in%`. Base
[`match()`](https://rdrr.io/r/base/match.html) and `%in%` compare exact
decimal text when both sides are zuint vectors; these hash the values
themselves and are much faster on long vectors. They are also exact when
one side is a bare number, which base
[`match()`](https://rdrr.io/r/base/match.html) is not (see below).

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

  The position to give values not in `table`: one number, truncated to
  an integer, as [`base::match()`](https://rdrr.io/r/base/match.html)
  does.

## Value

`zu_match()` returns an integer vector of positions in `table`; `%zin%`
a logical vector.

## Details

Both arguments take their common type first (see
[`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md));
`NA` matches `NA`. A
[`decimal128()`](https://pedrobtz.github.io/zuint/reference/decimal128.md)
matches by value, whatever the scales: `1.0` matches `1.00` and the
integer `1`.

## Base functions and a bare number

[`base::match()`](https://rdrr.io/r/base/match.html) and `%in%` are not
generic. They turn the zuint side into text with
[`mtfrm()`](https://rdrr.io/r/base/mtfrm.html), and the other side, if
it is a bare double or logical, into text by R's own rules. The two
texts then differ: `1e5` is `"1e+05"`, and `int64(100000) %in% 100000`
is `FALSE`. The answer also changes with `options(scipen =)` and
`OutDec`, and with bit64 attached, whose masked `%in%` answers
differently. A method cannot reach the bare side.

[`base::table()`](https://rdrr.io/r/base/table.html),
[`merge()`](https://rdrr.io/r/base/merge.html) and the set functions
[`base::intersect()`](https://rdrr.io/r/base/sets.html),
[`base::setdiff()`](https://rdrr.io/r/base/sets.html),
[`base::union()`](https://rdrr.io/r/base/sets.html) and
[`base::is.element()`](https://rdrr.io/r/base/sets.html) go through
[`match()`](https://rdrr.io/r/base/match.html) and have the same limit.
`intersect(int64(1e5), 1e5)` is empty, and
[`setdiff()`](https://rdrr.io/r/base/sets.html) and
[`union()`](https://rdrr.io/r/base/sets.html) return the raw bits of the
zuint side.

Use `zu_match()` or `%zin%`, or convert the bare side first, for example
`int64(1e5)`. Two zuint vectors of the same type are always safe.

## Examples

``` r
zu_match(uint64(c("18446744073709551614", "7")), uint64(c(7, 1)))
#> [1] NA  1
int64(5) %zin% int64(1:10)
#> [1] TRUE
# a bare double is compared as text by base R, and by value here
int64(100000) %in% 100000
#> [1] FALSE
int64(100000) %zin% 100000
#> [1] TRUE
```
