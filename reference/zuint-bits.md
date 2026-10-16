# Bit operations

Bitwise operations on the two's complement bits of each type's full
width: 64 bits for `int64` and `uint64`, 128 for `int128` and `uint128`.

## Usage

``` r
bit_and(x, y)

bit_or(x, y)

bit_xor(x, y)

bit_not(x)

shift_left(x, n)

shift_right(x, n)

popcount(x)

clz(x)

ctz(x)
```

## Arguments

- x, y:

  zuint vectors, or a zuint vector and an integer vector.

- n:

  Shift amounts: an integer vector, or anything that converts to one
  exactly. Recycled against `x`.

## Value

`bit_*()` and `shift_*()` return a zuint vector; `popcount()`, `clz()`
and `ctz()` an integer vector.

## Details

`bit_and()`, `bit_or()` and `bit_xor()` take their operands to the
common type first (see
[`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md)).
`shift_left()` discards the bits it shifts out; `shift_right()` fills
with zeros for the unsigned types and with the sign bit for the signed
ones, so it rounds towards negative infinity. A shift by a negative
amount, or by the width or more, is `NA`.

A result whose bits are the type's `NA` pattern (for example
`bit_not(int64("9223372036854775807"))`) is out of range: `NA` with a
warning of class `zuint_overflow_warning`, as in arithmetic.

`popcount()` counts the set bits, `clz()` the leading zeros and `ctz()`
the trailing zeros, all of the full width; `clz()` and `ctz()` of zero
are the width.

## Examples

``` r
x <- uint64("0xff00")
format_hex(bit_and(x, uint64("0x0ff0")))
#> [1] "0xf00"
format_hex(shift_left(x, 8L))
#> [1] "0xff0000"
shift_right(int64(-16), 2L)
#> <int64[1]>
#> [1] -4
popcount(uint128("0xffffffffffffffffffff"))
#> [1] 80
clz(uint64(1))
#> [1] 63
ctz(int128(0))
#> [1] 128
```
