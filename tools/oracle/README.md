# Engine oracles

DuckDB 2.0.1, arrow and nanoarrow know the right answers for zuint's
decimal types and its Arrow round trips (design §12), but they are not
dependencies: the package's tests replay their answers from
`tests/testthat/fixtures/engines.rds` and load none of them.

| File | What it is |
| --- | --- |
| `tests/testthat/helper-engines.R` | the replay: `duck_query()`, `duck_typeof()`, `duck_df()`, `duck_eval()`, `duckdb_to_r()`, `duck_receive()`, `arrow_check()`, `arrow_bytes()` |
| `live.R` | the same calls against the live engines, sourced only when recording |
| `record` | runs the whole suite live and writes the fixture |
| `compare.R` | compares two recordings, answer by answer |
| `test-interop.R` | zuint inside dplyr, tibble and data.table, run only in CI |

## How an answer is keyed

Each answer is keyed by an MD5 of everything it depends on: the SQL, the
connection's setup statements and the inputs, written exactly (doubles in
hex). What zuint *sends* to an engine (DuckDB reading a table zuint wrote,
arrow comparing a table) enters the key as the fingerprint of zuint's own
Arrow export of each column: its class, format, type and bits. So a change
to what zuint writes, or to what a test asks, finds no recorded answer, and
the test fails with "no recorded engine answer" until it is recorded, and so
checked against the engines, again.

What the engines *send* to zuint (DuckDB's Arrow export, a Parquet file read
by arrow) is recorded as the Arrow IPC stream nanoarrow or arrow writes of
it, and replayed through `zuarrow::arrow_read()`. When recording, `live.R`
checks that the stream reads back exactly as the live export does.

## Recording

From the package root, with duckdb (>= 2.0.1), DBI, nanoarrow, arrow and
zuarrow installed:

```sh
tools/oracle/record                       # rewrites the committed fixture
git diff --stat tests/testthat/fixtures   # then commit it with the change
```

A recording runs the whole suite live, so every test passes against the
engines themselves. Table names come from a counter, never from the RNG, so
recording and replaying draw the same random inputs; two recordings are
identical (`compare.R` checks it).

## In CI

`.github/workflows/oracle.yaml`, in the full profile: it records afresh,
compares with the committed fixture (a new DuckDB that changes a rule shows
up here), and runs `test-interop.R`.
