# Query DuckDB into zuint columns

`zu_duckdb_query()` runs a query through DuckDB's Arrow export and
returns a data frame in which `BIGINT`, `UBIGINT`, `HUGEINT` and
`UHUGEINT` columns are `int64`, `uint64`, `int128` and `uint128`,
exactly. Other columns convert as nanoarrow converts them.
`zu_duckdb_register()` goes the other way: it registers a data frame
with DuckDB as a view whose zuint columns have those four types.

## Usage

``` r
zu_duckdb_query(con, sql)

zu_duckdb_register(con, name, data)
```

## Arguments

- con:

  A DuckDB connection.

- sql:

  A query.

- name:

  The name of the view to register.

- data:

  A data frame.

## Value

`zu_duckdb_query()` returns a data frame; `zu_duckdb_register()` returns
`con`, invisibly. Unregister the view with
[`duckdb::duckdb_unregister_arrow()`](https://r.duckdb.org/reference/duckdb_register_arrow.html).

## Details

`zu_duckdb_query()` sets `arrow_lossless_conversion = true` on the
connection, which stays set: without it DuckDB exports `UHUGEINT` as a
decimal and values of \\2^{127}\\ and above read back as negative.

Both need the duckdb, DBI, arrow and nanoarrow packages.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpWIjA47/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
zu_duckdb_query(con, "SELECT 18446744073709551614::UBIGINT AS id")
#>                     id
#> 1 18446744073709551614

zu_duckdb_register(con, "t", data.frame(h = int128("-170141183460469231731687303715884105727")))
DBI::dbGetQuery(con, "SELECT typeof(h) AS type, h::VARCHAR AS value FROM t")
#>      type                                    value
#> 1 HUGEINT -170141183460469231731687303715884105727
DBI::dbDisconnect(con, shutdown = TRUE)
```
