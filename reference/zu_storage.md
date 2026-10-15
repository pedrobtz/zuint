# Raw storage of a zuint vector

`zu_storage()` returns the payload a zuint vector is stored in, for code
that reads the bits directly: a double vector whose bits are 64-bit
integers for `int64` and `uint64`, and a complex vector whose real and
imaginary parts hold the low and high 64-bit words for `int128` and
`uint128`. `zu_from_storage()` reverses it. Names are kept both ways.

## Usage

``` r
zu_storage(x)

zu_from_storage(payload, type)
```

## Arguments

- x:

  A zuint vector.

- payload:

  A double or complex vector, as returned by `zu_storage()`.

- type:

  One of `"int64"`, `"uint64"`, `"int128"` or `"uint128"`.

## Value

`zu_storage()` returns a double or complex vector; `zu_from_storage()` a
zuint vector of `type`.

## Details

The payload is not a number: printing it or computing with it is
meaningless. Keeping the representation behind these two functions is
what lets it change without breaking callers.

## Examples

``` r
p <- zu_storage(int128(-1))
p
#> [1] NaN+NaNi
zu_from_storage(p, "int128")
#> <int128[1]>
#> [1] -1
```
