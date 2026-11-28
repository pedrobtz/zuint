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

DuckDB 2.0.1's, arrow's and nanoarrow's answers below are recorded, not
asked live: the tests replay them from `tests/testthat/fixtures/engines.rds`
(`helper-engines.R`), keyed by the query, the inputs and the fingerprint of
what zuint wrote, so a changed output finds no answer and fails. The
fixture's own row is the last one.

<!-- markdownlint-disable MD013 -->
| Boundary | Oracle | Carried by |
| -------- | ------ | ---------- |
| decimal text, decoding | gmp: edge and random values computed with gmp parse back to gmp's strings; out-of-range values become NA | tests/testthat/test-construct.R |
| decimal text, encoding | gmp: `as.character()` of each value equals gmp's decimal string | tests/testthat/test-construct.R |
| hex and binary text, both directions | gmp: `format_hex()` and `format_bin()` equal gmp's base 16 and base 2 strings, and parse back to the same value | tests/testthat/test-text.R |
| malformed text, decoding | equivalent inputs: each malformed string is NA with a warning, never a value; and a reference parser written from the grammar, under the fuzzer | tests/testthat/test-text.R, tools/fuzz/harness.c |
| double to integer | gmp: each edge that a double holds exactly converts to gmp's value; non-integral and out-of-range doubles are NA | tests/testthat/test-construct.R |
| integer to double | gmp, exactly: each result is within half an ulp of the value and on a tie the even neighbour, over the edges, random values and the ties at every power of two (gmp's own `as.double()` truncates, so it is not the oracle) | tests/testthat/test-construct.R |
| `mean()` and `median()` to double | gmp, exactly: the exact rational, rounded to the nearest double with ties to even by comparison with its neighbours, for random vectors of every type and of decimals at five scales, n copies of one value, a small total over a large n, and a remainder past the bits kept (#148) | tests/testthat/test-reduce.R |
| integer64 payload, both directions | reference implementation: bit64 reads `int64` bit for bit, and the int64 suite runs with and without bit64 attached and must agree | tests/testthat/test-storage.R, tests/testthat/test-bit64-parity.R |
| Arrow C Data import (`l`, `L`, `arrow.opaque` hugeint/uhugeint, `d:38,0`) | the bytes the other side sent: DuckDB literals at each type's ends, and arrow's `Table$Equals()` after the round trip | tests/testthat/test-arrow.R, tests/testthat/test-roundtrip.R |
| Arrow C Data import of `c`, `C`, `s`, `S`, `i` and `I` under an `int64()` or `uint64()` prototype | gmp: each format's ends and their neighbours, written by nanoarrow, read as gmp's values (#155) | tests/testthat/test-arrow.R |
| Arrow C Data import under a zuint prototype in `to =` | gmp and zuarrow's own policy: each of the four prototypes on DuckDB's BIGINT, UBIGINT, HUGEINT and UHUGEINT (the extension and the default decimal export), INTEGER, DOUBLE, VARCHAR and DECIMAL(38,0), at the types' ends, under each `lossy` policy, gives gmp's value where the type holds it, and otherwise zuarrow's classes (`zuarrow_lossy_error` under `"error"` and `"character"`, `zuarrow_lossy_warning` under `"warn"`, nothing under `"allow"`) and never a `zuint_cast_warning`; the rows the type holds read the same under every policy (#167) | tests/testthat/test-arrow.R |
| `arrow.opaque` extension JSON, decoding | reference implementation: DuckDB, through arrow, on 26 pairs of metadata string and storage, must read HUGEINT or UHUGEINT exactly where zuint reads int128 or uint128 (#154); test vectors for invalid JSON arrow's lazy parser reads and zuint refuses; and a reference reader written from RFC 8259, under the fuzzer | tests/testthat/test-arrow.R, tools/fuzz/harness.c |
| Arrow decimal format string, decoding | test vectors: the spec's forms, and each wrapping, signed, spaced, partial or extra form refused (#156); and a reference reader written from the C Data Interface's description, under the fuzzer | tests/testthat/test-arrow.R, tools/fuzz/harness.c |
| Arrow C Data export | the bytes the other side received: DuckDB's `DESCRIBE` names BIGINT, UBIGINT, HUGEINT and UHUGEINT, an `IS DISTINCT FROM` join finds no differing value, and arrow's `Schema$Equals()` holds | tests/testthat/test-arrow.R, tests/testthat/test-roundtrip.R |
| Arrow schema metadata, decoding | test vectors: hand-built metadata bytes, valid and corrupt, read as the key or as no metadata; and a reference reader written from the Arrow spec, under the fuzzer | tests/testthat/test-arrow.R, tools/fuzz/harness.c |
| Arrow schema metadata, encoding | the bytes the other side received: DuckDB reads the exported extension as HUGEINT and UHUGEINT | tests/testthat/test-arrow.R |
| Parquet through arrow | round trip: Parquet to R to Parquet keeps the schema and every value | tests/testthat/test-roundtrip.R |
| DECIMAL text, decoding | reference implementations: DuckDB 2.0.1's casts on structured and mutated texts, gmp's exact value of each structured text, and Python's `decimal` on 300,000 more; every difference from DuckDB is one of design 2.2's two deviations; a reference grammar and exact value under the fuzzer | tests/testthat/test-fixed.R, tools/fixed/diff.py, tools/fuzz/harness.c |
| DECIMAL text, encoding | reference implementations: DuckDB writes the same text and reads it back to the same value; DuckDB's formatter written again in R and in Python | tests/testthat/test-fixed.R, tools/fixed/diff.py |
| DECIMAL rescale, add, subtract, multiply and compare | conformance suite: the General Decimal Arithmetic cases that apply to fixed point (2,033); gmp and Python's `decimal`; DuckDB's casts for rescaling | tools/fixed/fixed.c, tests/testthat/test-fixed.R |
| decimal128 vectors: construction, `+ - *`, rounding, comparison, matching and `c()` | reference implementation: DuckDB 2.0.1's `typeof()` and values (as text) for `+ - *` over 121 pairs of types and each integer kind, for `round()` at ten digit counts, `floor`, `ceil` and `trunc` over ten types, for the running `sum`, `max` and `min`, its casts from text, integers, doubles and decimals, its list common type in `c()`, and its `sum`, `min`, `max` and `avg`; gmp for comparison across scales and against doubles' exact values, and for sums; `==` (itself checked against gmp) for `match()` and `%in%` across scales. Not compared with a reference: `/ %% %/% ^` (base R on `as.double()`), the vctrs common types (hand-written, equal to `c()`'s), and the order (a hand-written text key of each coefficient) | tests/testthat/test-decimal.R |
| DECIMAL to and from double | reference implementation: DuckDB's casts, bit for bit; Python's correctly rounded division, and zufast's correctly rounded parser under the fuzzer | tests/testthat/test-fixed.R, tools/fixed/diff.py, tools/fuzz/harness.c |
| `zuint_api_v1`, the C table | the other side: `zuint.h` compiles alone with no R headers; a translation unit resolves the table through `zuint-r.h`; the C binary calls it with no R in the process, from 8 threads at once against one | tests/testthat/test-fixed.R, tools/fixed/fixed.c |
<!-- markdownlint-enable MD013 -->
| recorded engine answers (`engines.rds`) | reference implementation: the live DuckDB, arrow and nanoarrow, recorded afresh and compared answer by answer; two recordings are identical | .github/workflows/oracle.yaml, tools/oracle/compare.R |

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object | Sequences | Fork | Unwind | Owner |
| ------ | --------- | ---- | ------ | ----- |
| exported Arrow array and schema (`zu_to_arrow_c()`) | tests/testthat/test-arrow.R: read after release is a `zuint_arrow_error`, release runs once, collection releases | n/a: plain `malloc` buffers with no PID-bound resource, which a fork copies | gap #91 | tests/testthat/test-arrow.R: the finalizer releases unless a consumer moved the struct out, counted by `zu_arrow_releases_c()`, the array's and its schema's, exactly once each (#73) |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

<!-- markdownlint-disable MD013 -->
| Limit | Unit | Straddled by |
| ----- | ---- | ------------ |
| each type's range | value | tests/testthat/test-construct.R (gmp edges and the values just outside, from text and from double), tests/testthat/test-text.R (hex), tests/testthat/test-arith.R (each operator's result against gmp) |
| 128 bits of text | digits | tests/testthat/test-text.R: 33 hex digits and 60 decimal digits are NA with a warning; the gmp edges are the largest that fit |
| `ZU_METADATA_MAX_ENTRIES` (4096) | metadata entries | tests/testthat/test-arrow.R (4095, 4096 and 4097 entries, the key last; 4096 and 4097 with DuckDB's extension through the handler, which reads int128 or raises `zuint_arrow_error`, #166), and the fuzz corpus's three seeds at the same counts |
| JSON nesting 1024 deep, the top-level object counted | levels | tests/testthat/test-arrow.R (1024 and 1025 levels in the extension's JSON), and the fuzz corpus's two seeds at the same depths |
| `decimal128` precision 38 | decimal digits | tests/testthat/test-arrow.R (`d:37,0`, `d:38,0` and `d:39,0`, with and without `,128`; values read at 37 and 38) |
| decimal product scale at most 38 | scale | tests/testthat/test-decimal.R (products of scale 37, 38 and 39 against DuckDB's `typeof()`; 39 is a `zuint_incompatible_error` where DuckDB refuses) |
| DuckDB's 18-digit product cap | scale and precision | tests/testthat/test-decimal.R (operands of at most 18 digits at product scale 17, 18 and 19, an operand of 19 digits, against DuckDB's `typeof()`) |
| a whole double as INTEGER, BIGINT or HUGEINT | value | tests/testthat/test-decimal.R (2^31 - 1, 2^31, -2^31, -2^31 - 1, 2^63 - 1024, 2^63 and -2^63, each against DuckDB's `typeof()` of the literal) |
| decimal `sum()` and `cumsum()` in DECIMAL(38, s) | decimal digits | tests/testthat/test-decimal.R (10^38 - 1 exactly, 10^38, and 1.2 * 10^38 inside int128; a running sum past 38 digits) |
| DECIMAL precision 1 to 38, scale 0 to p | decimal digits | tests/testthat/test-fixed.R (precision 0, 1, 37, 38, 39; scale -1, p - 1, p, p + 1; 10^38 - 1 and 10^38 at scale 0, and their halfway point) |
| a DECIMAL(p, s) value | decimal digits | tests/testthat/test-fixed.R (10^p - 1 against 10^p for every width class, parsed, formatted and rescaled; rescaling at 128 bits), tools/fixed/diff.py (the same edges, weighted) |
<!-- markdownlint-enable MD013 -->
