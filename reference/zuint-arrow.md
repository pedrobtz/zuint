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

|                 |                                        |            |
|-----------------|----------------------------------------|------------|
| Key             | Arrow type                             | zuint type |
| `l`             | `int64`                                | `int64`    |
| `L`             | `uint64`                               | `uint64`   |
| `arrow.opaque`  | DuckDB's `hugeint` extension (`w:16`)  | `int128`   |
| `arrow.opaque`  | DuckDB's `uhugeint` extension (`w:16`) | `uint128`  |
| `zuint.int128`  | none: `to = int128()`, and writing     | `int128`   |
| `zuint.uint128` | none: `to = uint128()`, and writing    | `uint128`  |

An `arrow.opaque` column is DuckDB's when its JSON metadata says so at
the top level: `vendor_name` `"DuckDB"` and `type_name` `"hugeint"` or
`"uhugeint"`. Other `arrow.opaque` types, which DuckDB uses for types
Arrow has no form for, keep zuarrow's own conversion, as does metadata
that is not valid JSON. The `zuint.int128` and `zuint.uint128` keys
match no Arrow column: zuarrow finds a prototype's handler by its class,
so each 128-bit class has a registration of its own.

A zuint prototype in `to =`, such as `to = list(x = uint64())`, gives
that type for a column of any format, or a condition. zuint reads its
own formats and the 8-, 16- and 32-bit integers exactly, and any other
column through zuarrow's own conversion, then casts the values to the
prototype's type. A value the type cannot hold, such as `-1` under
[`uint64()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
`0.5` or the text `"abc"`, follows the `lossy` policy below.

A `decimal128(p, 0)` column is a decimal, not an integer, so zuint does
not register for it. Asking for `int128` with `to = int128()` in
[`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html)
reads one with `p` up to 38 as the 128 bits it holds, and
`to = uint128()` reads its value, so a negative one is lost. DuckDB
writes `HUGEINT` and `UHUGEINT` that way unless its
`arrow_lossless_conversion` setting is on, and a `UHUGEINT` of 2^127 or
more is then a negative decimal. So turn the setting on, and `HUGEINT`
and `UHUGEINT` arrive as the extension:

    DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
    zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))

A null reads as `NA` and an `NA` writes as a null. A valid value equal
to a type's `NA` bit pattern, such as `UINT64_MAX` in a `UBIGINT`
column, cannot be held, nor can a value out of a prototype's range.
zuarrow's `lossy` policy decides what happens to them, in zuarrow's
condition classes:

- `"error"` and `"character"` raise `zuarrow_lossy_error`, naming the
  column, its format and a value. `"character"` would give the column as
  text only for the batches that lose a value, which could not be
  combined with the others, so it fails like `"error"` instead.

- `"warn"` reads them as `NA` with one `zuarrow_lossy_warning` per
  batch.

- `"allow"` reads them as `NA` silently.

Writing never loses a value: `int128` and `uint128` are written as the
DuckDB extension, which DuckDB reads back as `HUGEINT` and `UHUGEINT`.

## See also

[`zu_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
for the representation, the contract a package that builds zuint vectors
in C relies on.
