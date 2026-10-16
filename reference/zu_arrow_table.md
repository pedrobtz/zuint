# Arrow tables with zuint columns

`zu_arrow_table()` makes an Arrow Table from a data frame whose zuint
columns keep their exact types (see
[`zu_to_arrow()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)),
and `zu_from_arrow_table()` reads a Table or record batch reader back
into a data frame with zuint columns. Together they carry zuint vectors
through anything arrow writes and reads, such as Parquet files.

## Usage

``` r
zu_arrow_table(data)

zu_from_arrow_table(table)
```

## Arguments

- data:

  A data frame.

- table:

  An Arrow Table or record batch reader.

## Value

`zu_arrow_table()` returns an Arrow Table; `zu_from_arrow_table()` a
data frame.

## Details

They go through nanoarrow rather than arrow's own conversion. arrow
(24.0.0 and 25.0.1) aborts R when it makes an R object for the
`arrow.opaque` extension type that `int128` and `uint128` use
(<https://github.com/apache/arrow/issues/53951>), so
[`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html)
and
[`arrow::infer_type()`](https://arrow.apache.org/docs/r/reference/infer_type.html)
work for `int64` and `uint64` only, and give an error for the 128-bit
types.

Both need the arrow and nanoarrow packages.

## Examples

``` r
df <- data.frame(id = uint64("18446744073709551614"), big = int128("-1"))
tb <- zu_arrow_table(df)
tb$schema
#> Schema
#> id: uint64
#> big: extension<arrow.opaque[storage_type=fixed_size_binary[16], type_name=hugeint, vendor_name=DuckDB]>

f <- tempfile(fileext = ".parquet")
arrow::write_parquet(tb, f)
zu_from_arrow_table(arrow::read_parquet(f, as_data_frame = FALSE))
#>                     id big
#> 1 18446744073709551614  -1
```
