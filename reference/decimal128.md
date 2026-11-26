# Fixed-point decimal vectors

`decimal128()` creates a vector of DuckDB's `DECIMAL(precision, scale)`:
numbers with at most `precision` digits, `scale` of them after the
point, held exactly as a 128-bit integer coefficient. A DuckDB `DECIMAL`
column, or one written to it, keeps every digit and its type.

## Usage

``` r
decimal128(x = character(), precision = 38L, scale = 0L)

is_decimal128(x)

decimal_precision(x)

decimal_scale(x)
```

## Arguments

- x:

  For `decimal128()`, a vector to convert; for `is_decimal128()`, any
  object; for `decimal_precision()` and `decimal_scale()`, a
  `decimal128` vector.

- precision:

  The number of digits, 1 to 38.

- scale:

  The number of digits after the point, 0 to `precision`.

## Value

`decimal128()` returns a `decimal128` vector the length of `x`.
`is_decimal128()` returns `TRUE` or `FALSE`, and `decimal_precision()`
and `decimal_scale()` a single integer.

## Details

`x` can be text, a logical, integer or double vector, a zuint vector, a
bit64 `integer64` or another `decimal128`.

- Text is read as DuckDB reads a `DECIMAL`: an optional sign, digits
  with an optional point, `_` between digits, an exponent, and
  surrounding whitespace; digits past the scale round half away from
  zero. `"NA"` and blank strings are `NA`.

- Integers and zuint vectors convert exactly.

- A double is rounded to the scale, half away from zero, as DuckDB's
  cast does: `decimal128(2.675, 5, 2)` is `2.68`.

- A `decimal128` of another type is rescaled, rounding half away from
  zero. Without `precision` or `scale` it keeps its own:
  `decimal128(x, 20)` changes only the precision. With neither it is
  returned as it is.

A value that does not fit `precision` digits becomes `NA` with a warning
of class `zuint_cast_warning`. Names are kept.

Arithmetic follows DuckDB's types: `+` and `-` keep the larger scale and
grow the precision by one, `*` adds precisions and scales, and
`precision` stops at 38. As in DuckDB, a product of two operands of at
most 18 digits stops at 18 unless its scale is 18 or more. A result that
does not fit is `NA` with a `zuint_overflow_warning`. An integer operand
counts as `DECIMAL(10, 0)`, `int64` as `DECIMAL(19, 0)`, `uint64` as
`DECIMAL(20, 0)` and the 128-bit types as `DECIMAL(38, 0)`. A whole
double is an integer operand, typed as DuckDB types an integer literal;
any other double follows `options(zuint.double)`.

Comparison is exact across scales, and with every integer and whole
double, even one too large for 38 digits. `/`, `%%`, `%/%` and `^`
compute in double, as do [`mean()`](https://rdrr.io/r/base/mean.html),
[`median()`](https://rdrr.io/r/stats/median.html),
[`prod()`](https://rdrr.io/r/base/prod.html) and the `Math` functions
other than those below; `!`, `&` and `|` give logicals.

These keep a decimal type, DuckDB's:

- [`abs()`](https://rdrr.io/r/base/MathFun.html),
  [`cummax()`](https://rdrr.io/r/base/cumsum.html) and
  [`cummin()`](https://rdrr.io/r/base/cumsum.html) keep the type, and
  [`sum()`](https://rdrr.io/r/base/sum.html) and
  [`cumsum()`](https://rdrr.io/r/base/cumsum.html) are
  `DECIMAL(38, scale)`.

- `round(x, digits)` rounds half away from zero to
  `DECIMAL(precision, digits)`, and is `x` when `digits` is the scale or
  more. A negative `digits` gives scale 0, with one more digit at scale
  0.

- [`floor()`](https://rdrr.io/r/base/Round.html),
  [`ceiling()`](https://rdrr.io/r/base/Round.html) and
  [`trunc()`](https://rdrr.io/r/base/Round.html) are
  `DECIMAL(precision, 0)`.

[`c()`](https://rdrr.io/r/base/c.html), vctrs and `x[i] <- value`
combine values in DuckDB's common type (for `[<-`, `x`'s type): the
largest scale and the most integer digits, and the scale cut when both
do not fit 38 digits. A value the type cannot hold exactly is `NA` with
a `zuint_cast_warning`; only `decimal128()` rounds.
[`sum()`](https://rdrr.io/r/base/sum.html),
[`min()`](https://rdrr.io/r/base/Extremes.html) and the other `Summary`
functions dispatch on their first argument, as R's group generics do, so
write `sum(x, 1L)`, not `sum(1L, x)`.

## Examples

``` r
price <- decimal128(c("19.99", "5.00", NA), 10, 2)
price
#> <decimal128(10, 2)[3]>
#> [1] 19.99  5.00    NA
price * 3L
#> <decimal128(18, 2)[3]>
#> [1] 59.97 15.00    NA
sum(price, na.rm = TRUE)
#> <decimal128(38, 2)[1]>
#> [1] 24.99
decimal_scale(price * price)
#> [1] 4

# Too many digits, so NA with a warning:
decimal128("123.45", 4, 2)
#> Warning: 1 value could not be represented as decimal128(4, 2) and became NA.
#> <decimal128(4, 2)[1]>
#> [1] NA
```
