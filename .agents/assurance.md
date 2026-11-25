# Assurance

How this package meets the shared `assurance.md` rules. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.

## Kinds

`compiled` `untrusted-input` `spec` `lifecycle` `emits`

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check         | Status  | Where              |
| ------------- | ------- | ------------------ |
| sanitizers    | done    | native-checks.yml  |
| valgrind      | done    | native-checks.yml  |
| rchk          | done    | native-checks.yml  |
| gctorture     | done    | native-checks.yml  |
| analyzers     | done    | native-checks.yml  |
| alloc-failure | done    | alloc-failure.yaml |
| mutation      | done    | mutation.yaml      |
| fuzz          | done    | fuzz.yaml          |
| fuzz-reach    | done    | fuzz.yaml          |

## Boundaries

One row per boundary the package crosses. An oracle knows the answer:

- a conformance suite or test vectors;
- a reference implementation;
- a round trip;
- equivalent inputs compared;
- the bytes the other side received.

"No crash" is not an oracle.

<!-- markdownlint-disable MD013 -->
| Boundary | Oracle | Carried by |
| -------- | ------ | ---------- |
| decimal text, decoding | gmp: edge and random values computed with gmp parse back to gmp's strings; out-of-range values become NA | tests/testthat/test-construct.R |
| decimal text, encoding | gmp: `as.character()` of each value equals gmp's decimal string | tests/testthat/test-construct.R |
| hex and binary text, both directions | gmp: `format_hex()` and `format_bin()` equal gmp's base 16 and base 2 strings, and parse back to the same value | tests/testthat/test-text.R |
| malformed text, decoding | equivalent inputs: each malformed string is NA with a warning, never a value; and a reference parser written from the grammar, under the fuzzer | tests/testthat/test-text.R, tools/fuzz/harness.c |
| double to integer | gmp: each edge that a double holds exactly converts to gmp's value; non-integral and out-of-range doubles are NA | tests/testthat/test-construct.R |
| integer to double | gmp, exactly: each result is within half an ulp of the value and on a tie the even neighbour, over the edges, random values and the ties at every power of two (gmp's own `as.double()` truncates, so it is not the oracle) | tests/testthat/test-construct.R |
| integer64 payload, both directions | reference implementation: bit64 reads `int64` bit for bit, and the int64 suite runs with and without bit64 attached and must agree | tests/testthat/test-storage.R, tests/testthat/test-bit64-parity.R |
| Arrow C Data import (`l`, `L`, `arrow.opaque` hugeint/uhugeint, `d:38,0`) | the bytes the other side sent: DuckDB literals at each type's ends, and arrow's `Table$Equals()` after the round trip | tests/testthat/test-arrow.R, tests/testthat/test-roundtrip.R |
| Arrow C Data export | the bytes the other side received: DuckDB's `DESCRIBE` names BIGINT, UBIGINT, HUGEINT and UHUGEINT, an `IS DISTINCT FROM` join finds no differing value, and arrow's `Schema$Equals()` holds | tests/testthat/test-arrow.R, tests/testthat/test-roundtrip.R |
| Arrow schema metadata, decoding | test vectors: hand-built metadata bytes, valid and corrupt, read as the key or as no metadata; and a reference reader written from the Arrow spec, under the fuzzer | tests/testthat/test-arrow.R, tools/fuzz/harness.c |
| Arrow schema metadata, encoding | the bytes the other side received: DuckDB reads the exported extension as HUGEINT and UHUGEINT | tests/testthat/test-arrow.R |
| Parquet through arrow | round trip: Parquet to R to Parquet keeps the schema and every value | tests/testthat/test-roundtrip.R |
<!-- markdownlint-enable MD013 -->

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object | Sequences | Fork | Unwind | Owner |
| ------ | --------- | ---- | ------ | ----- |
| exported Arrow array and schema (`zu_to_arrow_c()`) | tests/testthat/test-arrow.R: read after release is a `zuint_arrow_error`, release runs once, collection releases | n/a: plain `malloc` buffers with no PID-bound resource, which a fork copies | gap #91 | tests/testthat/test-arrow.R: the finalizer releases unless a consumer moved the struct out, counted by `zu_arrow_releases_c()` |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

<!-- markdownlint-disable MD013 -->
| Limit | Unit | Straddled by |
| ----- | ---- | ------------ |
| each type's range | value | tests/testthat/test-construct.R (gmp edges and the values just outside, from text and from double), tests/testthat/test-text.R (hex), tests/testthat/test-arith.R (each operator's result against gmp) |
| 128 bits of text | digits | tests/testthat/test-text.R: 33 hex digits and 60 decimal digits are NA with a warning; the gmp edges are the largest that fit |
| `ZU_METADATA_MAX_ENTRIES` (4096) | metadata entries | tests/testthat/test-arrow.R (4095, 4096 and 4097 entries, the key last), and the fuzz corpus's three seeds at the same counts |
| `decimal128` precision 38 | decimal digits | tests/testthat/test-arrow.R (`d:37,0`, `d:38,0` and `d:39,0`, with and without `,128`; values read at 37 and 38) |
<!-- markdownlint-enable MD013 -->
