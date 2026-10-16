# zuint

## Overview

R has 32-bit integers and doubles, and a double is exact only up to 2⁵³.
Databases and data files have more: Arrow and Parquet have signed and
unsigned 64-bit integers, and DuckDB adds 128-bit ones. Read into R, an
unsigned ID or a `HUGEINT` becomes a double and quietly loses its low
digits, and writing it back loses the column’s type as well.

zuint gives R the four integer types those engines use, `int64`,
`uint64`, `int128` and `uint128`, and moves them in and out of Arrow,
Parquet and DuckDB with every value and every column type intact.

- **Exact or explicit.** A result is exact, or it is `NA` with a
  warning, or an error. Nothing is rounded, truncated or clamped without
  saying so, and nothing is compared through a double.
- **Overflow is a choice.** Operators give `NA` with a warning, as R’s
  integers do; `checked_*()` functions raise an error and `wrapping_*()`
  functions compute modulo 2⁶⁴ or 2¹²⁸.
- **Types mix without loss.** Combining two types gives the smallest
  type that holds both, so `int64` and `uint64` meet in `int128`; where
  there is no such type, it is an error.
- **Compatible with bit64.** `int64` is a bit64 `integer64` underneath,
  so data.table, arrow, duckdb and the database drivers read it as they
  read `integer64`.
- **One bridge to the engines.** Data moves through the [Arrow C Data
  Interface](https://arrow.apache.org/docs/format/CDataInterface.html),
  in C, with no R package in between; nanoarrow, arrow and duckdb are
  only needed for their own conveniences.

| Engine type | R today | zuint |
|----|----|----|
| Arrow `int64`, DuckDB `BIGINT` | a double by default, or bit64 `integer64` | `int64` |
| Arrow `uint64`, DuckDB `UBIGINT` | a double, rounded beyond 2⁵³ | `uint64` |
| DuckDB `HUGEINT` | a double | `int128` |
| DuckDB `UHUGEINT` | a double | `uint128` |

## Installation

zuint is not on CRAN yet. Install the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("pedrobtz/zuint")
```

## Usage

``` r

library(zuint)
```

A number beyond 2⁵³ is exact, where a double has already rounded it:

``` r

x <- uint64("18446744073709551614")
x
#> <uint64[1]>
#> [1] 18446744073709551614
x - 1L
#> <uint64[1]>
#> [1] 18446744073709551613
sprintf("%.0f", 18446744073709551614 - 1)
#> [1] "18446744073709551616"
```

An out-of-range result is `NA` with a warning, unless you choose another
overflow policy:

``` r

big <- int64("9223372036854775807")
big + 1L
#> Warning in Ops.zu_int64(big, 1L): 1 result is out of range. NA produced.
#> <int64[1]>
#> [1] NA
try(checked_add(big, 1L))
#> Error in checked_add(big, 1L) : 1 result is out of range.
wrapping_mul(x, 31L)
#> <uint64[1]>
#> [1] 18446744073709551554
```

Mixing types never loses a value: an `int64` and a `uint64` give an
`int128`, and a product too large for `int64` fits in `int128`:

``` r

int64(-1) + uint64("18446744073709551614")
#> <int128[1]>
#> [1] 18446744073709551613
int128(big) * 4L
#> <int128[1]>
#> [1] 36893488147419103228
```

Values come out of DuckDB as they are stored, and go back with their
types. Here a `UHUGEINT` near the top of its range makes the round trip:

``` r

con <- DBI::dbConnect(duckdb::duckdb())
ids <- zu_duckdb_query(
  con,
  "SELECT 340282366920938463463374607431768211454::UHUGEINT AS id"
)
ids$id
#> <uint128[1]>
#> [1] 340282366920938463463374607431768211454

zu_duckdb_register(con, "ids_back", ids)
DBI::dbGetQuery(con, "SELECT typeof(id) AS type, id::VARCHAR AS id FROM ids_back")
#>       type                                      id
#> 1 UHUGEINT 340282366920938463463374607431768211454
DBI::dbDisconnect(con)
```

Text goes both ways in decimal, hexadecimal and binary:

``` r

format_hex(uint64("0xdead_beef"))
#> [1] "0xdeadbeef"
format_bin(int64(-5))
#> [1] "-0b101"
format(int64(1234567890123), big.mark = ",")
#> [1] "1,234,567,890,123"
```

The constructors are named after the types, and every conversion into a
type, from a double, a string or another type, follows the same rule:
exact, or `NA` with a warning.

## Performance

zuint’s `int64` against bit64’s `integer64` on random values across the
whole range, in milliseconds (median of five runs; R 4.6.1, bit64 4.8.2,
an Apple M-series laptop, 2026-10-16). `match` is
[`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md),
the fast counterpart of base
[`match()`](https://rdrr.io/r/base/match.html). The script is
`inst/bench/bench.R`.

| Elements | Operation | zuint | bit64 | zuint / bit64 |
|----------|-----------|------:|------:|--------------:|
| 10⁶      | `+`       |   2.9 |  11.1 |          0.26 |
|          | `sum`     |   0.5 |   0.6 |          0.83 |
|          | `sort`    |  13.7 |  14.8 |          0.93 |
|          | `match`   |  11.9 |  10.5 |          1.13 |
|          | `unique`  |  10.8 |  10.5 |          1.03 |
| 10⁷      | `+`       |    27 |    78 |          0.35 |
|          | `sum`     |     5 |     6 |          0.83 |
|          | `sort`    |   141 |   158 |          0.89 |
|          | `match`   |   148 |   295 |          0.50 |
|          | `unique`  |   147 |   283 |          0.52 |
| 10⁸      | `+`       |   266 |   781 |          0.34 |
|          | `sum`     |    51 |    58 |          0.88 |
|          | `sort`    |  2364 |  2339 |          1.01 |
|          | `match`   |  3056 |  1579 |          1.94 |
|          | `unique`  |  4148 |  1556 |          2.67 |

zuint is faster or level on most of them. It is slower for `match` and
`unique` at 10⁸ values, where its hash table outgrows memory caches, and
slightly slower for `match` at 10⁶.

## Learn more

- [`vignette("zuint")`](https://pedrobtz.github.io/zuint/articles/zuint.md)
  walks through the types, the promotion order, the overflow policies
  and the engine round trip.
- The [reference index](https://pedrobtz.github.io/zuint/reference/)
  lists every function, with the type ranges in
  [`?int64`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
  the overflow policies in
  [`?checked_add`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and the Arrow bridge in
  [`?zu_from_arrow`](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md).

## Related work

[bit64](https://CRAN.R-project.org/package=bit64) gave R its 64-bit
integers and the `integer64` layout that zuint’s `int64` keeps. The
128-bit arithmetic, parsing and formatting come from
[zufast](https://github.com/pedrobtz/zufast). Arrow arrays move through
the Arrow C Data Interface, and the 128-bit types through DuckDB’s
`arrow.opaque` extension types. The tests check values against
[gmp](https://CRAN.R-project.org/package=gmp).
