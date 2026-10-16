# Hexadecimal and binary text

`format_hex()` and `format_bin()` write each value with a `0x` or `0b`
prefix. A negative value is written as a sign and a magnitude, `-0x1`,
not as two's complement, so the constructors read every string back as
the same value. `NA` gives `NA_character_`.

## Usage

``` r
format_hex(x, pad = FALSE)

format_bin(x, pad = FALSE)
```

## Arguments

- x:

  A zuint vector.

- pad:

  If `TRUE`, write every digit of the type's width (16 or 32 hex digits,
  64 or 128 binary digits), as for hashes.

## Value

A character vector the length of `x`, with its names.

## Details

The constructors read the same forms: decimal, `0x` hex or `0b` binary
digits, an optional sign, `_` between digits, and surrounding
whitespace. Exponents and fractions are not accepted.

## Examples

``` r
format_hex(uint64("18446744073709551614"))
#> [1] "0xfffffffffffffffe"
format_hex(int64(c(255, -255, NA)))
#> [1] "0xff"  "-0xff" NA     
format_hex(uint64(255), pad = TRUE)
#> [1] "0x00000000000000ff"
format_bin(int128(5))
#> [1] "0b101"
uint64("0xffff_ffff")
#> <uint64[1]>
#> [1] 4294967295
```
