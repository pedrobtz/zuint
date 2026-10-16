# Arrow C Data Interface

Convert between zuint vectors and Arrow arrays through the Arrow C Data
Interface, with no R package in between. The arrays and schemas are
external pointers to `ArrowArray` and `ArrowSchema` structs, the form
nanoarrow's `nanoarrow_array` and `nanoarrow_schema` objects take.

## Usage

``` r
zu_from_arrow(array, schema)

zu_to_arrow(x, decimal = FALSE)

zu_sentinel_check(array, schema)
```

## Arguments

- array:

  An external pointer to an `ArrowArray`, such as a `nanoarrow_array`.

- schema:

  An external pointer to the array's `ArrowSchema`.

- x:

  A zuint vector.

- decimal:

  Export `int128` as `decimal128(38, 0)`.

## Value

`zu_from_arrow()` returns a zuint vector; `zu_to_arrow()` a list of
external pointers named `array` and `schema`, which release their
structs when garbage collected unless a consumer moved them out;
`zu_sentinel_check()` the number of values that would import as `NA`
though they are not null.

## Details

|  |  |
|----|----|
| zuint | Arrow format |
| `int64` | `int64` (`l`) |
| `uint64` | `uint64` (`L`) |
| `int128` | DuckDB's `arrow.opaque` `hugeint` extension (`w:16`); with `decimal = TRUE`, `decimal128(38, 0)` |
| `uint128` | DuckDB's `arrow.opaque` `uhugeint` extension (`w:16`) |

`zu_from_arrow()` also reads any `decimal128(p, 0)` with `p` up to 38 as
`int128`, taking the 128 bits as they are, which is how DuckDB exports
`HUGEINT` by default. It copies the data and leaves the structs to their
owner. A null becomes `NA` and an `NA` becomes a null. A valid value
that happens to equal a type's `NA` bit pattern (for example
`UINT64_MAX`) cannot be told from `NA`: it imports as `NA` with a
warning of class `zuint_cast_warning`. `zu_sentinel_check()` counts
those values without importing.

`zu_to_arrow()` exports `int128` as the extension by default because
DuckDB reads `decimal128(38, 0)` back as `DECIMAL(38,0)`, not `HUGEINT`.
`decimal = TRUE` is for consumers without extension support; a value
with more than 38 digits is then an error.

When nanoarrow is installed, `nanoarrow::convert_array(array, int64())`
and the other constructors' prototypes import through this bridge, and
[`nanoarrow::as_nanoarrow_array()`](https://arrow.apache.org/nanoarrow/latest/r/reference/as_nanoarrow_array.html)
exports zuint vectors.

## Examples

``` r
x <- uint64(c("18446744073709551614", NA, "1"))
a <- zu_to_arrow(x)
zu_from_arrow(a$array, a$schema)
#> <uint64[3]>
#> [1] 18446744073709551614                   NA                    1

b <- zu_to_arrow(int128(-1), decimal = TRUE)
zu_from_arrow(b$array, b$schema)
#> <int128[1]>
#> [1] -1
```
