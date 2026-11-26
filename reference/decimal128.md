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

  A vector to convert.

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
  zero. With neither `precision` nor `scale` given it is returned as it
  is.

A value that does not fit `precision` digits becomes `NA` with a warning
of class `zuint_cast_warning`. Names are kept.

Arithmetic follows DuckDB's types: `+` and `-` keep the larger scale and
grow the precision by one, `*` adds precisions and scales, and
`precision` stops at 38. As in DuckDB, a product of two operands of at
most 18 digits stops at 18 unless its scale is 18 or more. A result that
does not fit is `NA` with a `zuint_overflow_warning`. An integer operand
counts as `DECIMAL(10, 0)`, `int64` as `DECIMAL(19, 0)`, `uint64` as
`DECIMAL(20, 0)` and the 128-bit types as `DECIMAL(38, 0)`; a whole
double is an integer operand, and any other double follows
`options(zuint.double)`. Comparison is exact across scales. `/`, `%%`,
`%/%`, `^` and the `Math` functions other than
[`abs()`](https://rdrr.io/r/base/MathFun.html) compute in double, as
does [`mean()`](https://rdrr.io/r/base/mean.html);
[`sum()`](https://rdrr.io/r/base/sum.html) is a `DECIMAL(38, scale)`.

[`c()`](https://rdrr.io/r/base/c.html) and vctrs combine vectors in
DuckDB's common type: the largest scale and the most integer digits, and
the scale cut when both do not fit 38 digits. A value the common type
cannot hold exactly is `NA` with a `zuint_cast_warning`.

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
