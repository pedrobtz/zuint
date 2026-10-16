# Getting started with zuint

``` r

library(zuint)
```

## The four types

zuint has one type for each wide integer type that Arrow and DuckDB use.
Each type gives up one bit pattern to `NA`, so its range is one value
short of the full width.

| zuint     | Arrow                   | DuckDB     | Range         |
|-----------|-------------------------|------------|---------------|
| `int64`   | `int64`                 | `BIGINT`   | ±(2⁶³ − 1)    |
| `uint64`  | `uint64`                | `UBIGINT`  | 0 to 2⁶⁴ − 2  |
| `int128`  | `arrow.opaque` hugeint  | `HUGEINT`  | ±(2¹²⁷ − 1)   |
| `uint128` | `arrow.opaque` uhugeint | `UHUGEINT` | 0 to 2¹²⁸ − 2 |

The constructors convert from numbers, strings and each other. A
conversion is exact, or it gives `NA` with a warning:

``` r

uint64("18446744073709551614")
#> <uint64[1]>
#> [1] 18446744073709551614
int128("-0x7fff_ffff_ffff_ffff_ffff_ffff_ffff_ffff")
#> <int128[1]>
#> [1] -170141183460469231731687303715884105727
int64(c(2^53, 1.5))
#> Warning in int64(c(2^53, 1.5)): 1 value could not be represented as int64 and
#> became NA.
#> <int64[2]>
#> [1] 9007199254740992               NA
```

`int64` keeps the storage of bit64’s `integer64` and has it as its
second class, so packages that read `integer64` read `int64` unchanged.

## Mixing types

When two types meet, the result is the smallest type that holds both, so
no value is lost. `int128` and `uint128` hold different values, so they
have no common type, and mixing them is an error.

``` r

zu_common_type(int64(1), uint64(1))
#> [1] "int128"
int64(-1) + uint64("18446744073709551614")
#> <int128[1]>
#> [1] 18446744073709551613
try(int128(1) + uint128(1))
#> Error in Ops.zu_int128(int128(1), uint128(1)) : 
#>   int128 and uint128 have no common type; convert one explicitly.
```

A double takes the zuint type if it is a whole number in range, and is
an error otherwise; comparisons with doubles are exact and never an
error:

``` r

int64(10) + 2
#> <int64[1]>
#> [1] 12
try(int64(10) + 0.5)
#> Error in Ops.zu_int64(int64(10), 0.5) : 
#>   A double must be integral and in range of int64 to mix with it. Convert it explicitly, or set options(zuint.double = "allow").
int64("9007199254740993") > 2^53
#> [1] TRUE
```

## Overflow policies

The operators give `NA` with a warning when a result is out of range, as
R’s integers do. The `checked_*()` functions make it an error, and the
`wrapping_*()` functions compute modulo 2⁶⁴ or 2¹²⁸:

``` r

big <- int64("9223372036854775807")
big + 1L
#> Warning in Ops.zu_int64(big, 1L): 1 result is out of range. NA produced.
#> <int64[1]>
#> [1] NA
try(checked_add(big, 1L))
#> Error in checked_add(big, 1L) : 1 result is out of range.
wrapping_mul(uint64("0xffffffff"), uint64("0xffffffff"))
#> <uint64[1]>
#> [1] 18446744065119617025
```

[`sum()`](https://rdrr.io/r/base/sum.html) keeps the type and is exact,
or `NA` with a warning; [`mean()`](https://rdrr.io/r/base/mean.html) and
[`median()`](https://rdrr.io/r/stats/median.html) are doubles computed
from the exact values:

``` r

x <- int128(c("170141183460469231731687303715884105727", "1", "-1"))
sum(x)
#> <int128[1]>
#> [1] 170141183460469231731687303715884105727
mean(int64(1:2))
#> [1] 1.5
```

## Through engines and back

[`zu_duckdb_query()`](https://pedrobtz.github.io/zuint/reference/zu_duckdb_query.md)
reads a query’s wide integer columns exactly, and
[`zu_duckdb_register()`](https://pedrobtz.github.io/zuint/reference/zu_duckdb_query.md)
hands a data frame back to DuckDB with their types:

``` r

con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpXp7rEj/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
df <- zu_duckdb_query(con, "
  SELECT 18446744073709551614::UBIGINT AS id,
         -170141183460469231731687303715884105727::HUGEINT AS total
")
df
#>                     id                                    total
#> 1 18446744073709551614 -170141183460469231731687303715884105727
zu_duckdb_register(con, "back", df)
DBI::dbGetQuery(con, "SELECT typeof(id) AS id, typeof(total) AS total FROM back")
#>        id   total
#> 1 UBIGINT HUGEINT
DBI::dbDisconnect(con)
```

The same columns go through Arrow tables, and so through Parquet files:

``` r

f <- tempfile(fileext = ".parquet")
arrow::write_parquet(zu_arrow_table(df), f)
zu_from_arrow_table(arrow::read_parquet(f, as_data_frame = FALSE))
#>                     id                                    total
#> 1 18446744073709551614 -170141183460469231731687303715884105727
```

Underneath,
[`zu_to_arrow()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)
and
[`zu_from_arrow()`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)
speak the Arrow C Data Interface directly, and
`nanoarrow::convert_array(array, int64())` uses them when nanoarrow is
installed.

## Where the class gets lost

Base functions that build their result from bare values, such as
[`ifelse()`](https://rdrr.io/r/base/ifelse.html) and
[`vapply()`](https://rdrr.io/r/base/lapply.html), read the raw bits as
numbers.
[`zu_ifelse()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
and
[`zu_vapply()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
keep the type:

``` r

x <- int64(c("-9223372036854775807", "5"))
zu_ifelse(x > 0L, x, int64(0))
#> <int64[2]>
#> [1] 0 5
```

For the same reason, `serialize(ascii = TRUE)` and
[`dput()`](https://rdrr.io/r/base/dput.html) do not keep the values of
negative `int64` numbers or of `NA`; R’s default binary serialization
does.
