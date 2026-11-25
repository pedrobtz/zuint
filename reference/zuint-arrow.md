# zuint columns from Arrow, through zuarrow

zuint has no Arrow functions of its own. When the
[zuarrow](https://github.com/pedrobtz/zuarrow) package is installed,
zuint registers its four types with zuarrow's registry as soon as both
are loaded, and from then on
[`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html),
[`zuarrow::arrow_read()`](https://pedrobtz.github.io/zuarrow/reference/arrow_read.html)
and
[`zuarrow::arrow_array()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html)
read and write zuint columns exactly.
[`zuarrow::arrow_registry()`](https://pedrobtz.github.io/zuarrow/reference/arrow_register.html)
lists the entries:

## Details

|                |                                        |            |
|----------------|----------------------------------------|------------|
| Key            | Arrow type                             | zuint type |
| `l`            | `int64`                                | `int64`    |
| `L`            | `uint64`                               | `uint64`   |
| `arrow.opaque` | DuckDB's `hugeint` extension (`w:16`)  | `int128`   |
| `arrow.opaque` | DuckDB's `uhugeint` extension (`w:16`) | `uint128`  |

Other `arrow.opaque` types, which DuckDB uses for types Arrow has no
form for, keep zuarrow's own conversion.

A `decimal128(p, 0)` column is a decimal, not an integer, so zuint does
not register for it. Asking for `int128` with `to = int128()` in
[`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html)
reads one with `p` up to 38 as the 128 bits it holds. DuckDB writes
`HUGEINT` that way unless its `arrow_lossless_conversion` setting is on,
so turn the setting on, and `HUGEINT` and `UHUGEINT` arrive as the
extension:

    DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
    zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))

A null reads as `NA` and an `NA` writes as a null. A valid value equal
to a type's `NA` bit pattern, such as `UINT64_MAX` in a `UBIGINT`
column, cannot be held. zuarrow's `lossy` policy decides what happens to
it:

- `"error"` and `"character"` raise `zuarrow_lossy_error`, naming the
  value. `"character"` would give the column as text only when every
  batch held such a value, so it fails like `"error"` instead.

- `"warn"` reads it as `NA` with one `zuarrow_lossy_warning` per batch.

- `"allow"` reads it as `NA` silently.

Writing never loses a value: `int128` and `uint128` are written as the
DuckDB extension, which DuckDB reads back as `HUGEINT` and `UHUGEINT`.

## See also

[`zu_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
for the representation, the contract a package that builds zuint vectors
in C relies on.
