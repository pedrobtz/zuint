# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

<!-- r-skills: shared-rules -->

The portfolio's shared rules (`workflow`, `r-package`, `ci`, `native-code`,
`correctness`, `assurance`) come from the
[r-skills](https://github.com/pedrobtz/r-skills) plugin's `rules/`, loaded at
session start because of the marker above. Never copy them here. Where this
file and a shared rule disagree, this file wins for this package. Cloud
sessions do not load the plugin and run without them.

## What this is

zuint gives R lossless wide integer vectors, `int64`, `uint64`, `int128` and
`uint128`, so that every integer type Arrow and DuckDB produce survives the
trip into R and back with its schema and values intact. All four types share
one C core and one promotion lattice. `int64` keeps the bit64 `integer64`
layout so existing consumers read it unchanged, and within that layout it is
a stricter second implementation: exact or explicit, overflow as a policy,
summaries in the right type (design §0.1). Dependencies outside the zu-*
family are allowed only in `Suggests` (design §2.1): zufast (>= 0.1.1) is
`LinkingTo` only, R (>= 4.3.0) is required for `chooseOpsMethod()`, stats
(part of R) is imported for the `median()` generic, and bit64, zuarrow,
vctrs, pillar and gmp are Suggests used in tests and lazily registered
methods; arrow, duckdb, DBI and nanoarrow are test oracles only. It does not
fork bit64, do arithmetic on small integer types, offer arbitrary precision,
or do matrix algebra. Fixed-point `DECIMAL(p, s)` on `int128`, with an
R-free C table for zugodb, is in 0.1.0 as roadmap Stages 9.1 and 9.2
(design §2.2, #88). zuint does not depend on the `decimal` package, nor
it on zuint.

The specification is [`.agents/design.md`](.agents/design.md), adopted from
[RFC 0009](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0009-zuint-wide-integers.md).
It outranks this file: `CLAUDE.md` orients, the design doc decides.

## Current state

Stages 0 to 9 of [`.agents/roadmap.md`](.agents/roadmap.md) are done
(2026-11-25): the four types, arithmetic, text and bits, sorting, hashing
and reductions, vctrs and pillar, and the Arrow bridge handed to zuarrow.
Stages 9.1 and 9.2 (fixed-point decimals, added 2026-11-25), Stage 10
(v0.1.0 readiness) and Stage 11 (Review) remain. The design's
milestones number versions differently (its first CRAN release is "v0.3");
the roadmap maps them onto 0.1.0.

## Versions and dependents

The current version's parent issue is
[#1](https://github.com/pedrobtz/zuint/issues/1) for `v0.1.0`. Sibling
packages that depend on this one before CRAN does: zuspark (Suggests,
through `Remotes:`). zugodb's engine and R package (libzugodb#55,
zugodb#72) are to use the fixed-point C table (#88) once zuint is on
CRAN.

zuint itself waits on two siblings, so both must be on CRAN before zuint is
submitted:

- **zufast**, for the 128-bit primitives in its `wide.h` header.
  `DESCRIPTION` has `LinkingTo: zufast (>= 0.1.0.9000)`. When zufast 0.1.1
  is released, raise it to `>= 0.1.1` and drop it from `Remotes:` in the
  same commit.
- **zuarrow**, in Suggests, for the Arrow bridge. Drop it from `Remotes:`
  once it is on CRAN.

CRAN rejects a `Remotes:` field, so removing it is part of entering
`Pre-flight`.

## Commands

The fallback for compilers without `__int128` is built by setting
`ZUINT_CPPFLAGS=-DZUF_NO_INT128` in the environment, which
[`src/Makevars`](src/Makevars) passes to the compiler. Clean the old objects
first, and set `ZUINT_EXPECT_INT128=false` so `test-storage.R` confirms the
fallback really was built:

```sh
Rscript -e 'devtools::clean_dll()'
ZUINT_CPPFLAGS=-DZUF_NO_INT128 ZUINT_EXPECT_INT128=false \
  Rscript -e 'devtools::test()'
Rscript -e 'devtools::clean_dll()'               # back to the native build
```

CI runs this as the `no-int128` job of `R-CMD-check.yaml`, on every pull
request. It is occasional locally; the default loop is the shared
`devtools` commands.

`tools/verify-vendor` checks the vendored Arrow header against upstream (see
Vendored native code); run it after touching `src/vendor/`.

`make -C tools/fuzz driver && tools/fuzz/driver tools/fuzz/corpus/*` runs
the fuzz harness locally without libFuzzer, under ASan and UBSan: the
corpus, then 200,000 generated inputs (`ZU_FUZZ_RUNS` changes the count).
Run it after touching `src/zu_parse.c`, `src/zu_metadata.c` or
`src/zu_fixed.c`.

The fixed-point core's C tests run without R (`fixed.yaml` in CI):

```sh
make -C tools/fixed
tools/fixed/fetch-dectest /tmp/dectest
tools/fixed/fixed dectest /tmp/dectest/*.decTest
python3 tools/fixed/diff.py 200000 1 | tools/fixed/fixed diff
tools/fixed/fixed threads 8
make -C tools/fixed clean
```

`make -C tools/fixed SAN=thread` builds it under ThreadSanitizer, and
`CPPFLAGS=-DZUF_NO_INT128` with zufast's fallback.

## Architecture

Grows with the stages; `.agents/design.md` §10 has the planned C layout.

- [`src/zu_wide.h`](src/zu_wide.h) is the type layer: the type codes, the
  NA sentinels, raw word access to the REALSXP and CPLXSXP payloads, and
  `zu_val`, a sign plus a 128-bit magnitude that slow paths use to move a
  value between types with one range check (`zu_val_fits()`).
- [`src/zu_cast.c`](src/zu_cast.c) holds construction and conversion. Entry
  points that can lose a value return `list(result, n_lost)` and R raises
  the warning, so condition classes live only in R. Text goes through the
  one parser in [`src/zu_parse.c`](src/zu_parse.c), and out through
  [`src/zu_format.c`](src/zu_format.c).
- [`src/zu_bits.c`](src/zu_bits.c) and [`R/bits.R`](R/bits.R) are the bit
  operations; [`R/text.R`](R/text.R) is `format_hex()` and `format_bin()`.
- [`src/zu_arrow.c`](src/zu_arrow.c) holds the Arrow C Data Interface
  kernels, [`src/zu_metadata.c`](src/zu_metadata.c) the reader of Arrow's
  binary schema metadata, and [`R/arrow.R`](R/arrow.R) the `to` and `from`
  handlers that [`R/zzz.R`](R/zzz.R) registers with zuarrow when zuarrow
  loads (design
  §9.4). zuint has no Arrow functions of its own since Stage 9; the R
  surface is zuarrow's.
- [`src/zu_sort.c`](src/zu_sort.c) is a stable LSD radix sort on unsigned
  keys (sign bit flipped for the signed types), behind `sort()` and
  `xtfrm()`; [`src/zu_hash.c`](src/zu_hash.c) an open-addressing hash on the
  raw words, behind `unique()`, `duplicated()` and `zu_match()`;
  [`src/zu_reduce.c`](src/zu_reduce.c) the exact sums, products, cumulative
  functions and the mean. [`R/reduce.R`](R/reduce.R) holds their methods
  and `seq_zu()`.
- [`R/vctrs.R`](R/vctrs.R) holds the vctrs and pillar methods, registered
  lazily like the others, and `zu_ifelse()` / `zu_vapply()`.
  [`inst/bench/bench.R`](inst/bench/bench.R) benchmarks int64 against bit64;
  its results are in the README.
- [`src/zu_fixed.c`](src/zu_fixed.c) is the fixed-point `DECIMAL(p, s)`
  core (design §2.2), R-free; [`src/zu_api.c`](src/zu_api.c) builds
  `zuint_api_v1`, the C table of
  [`inst/include/zuint.h`](inst/include/zuint.h), which `init.c`
  registers as the callable `zuint_get_api` and
  [`inst/include/zuint-r.h`](inst/include/zuint-r.h) resolves.
  [`src/zu_fixed_r.c`](src/zu_fixed_r.c) holds its R entry points, and
  [`tools/fixed/`](tools/fixed) its C tests.
- [`R/bit64.R`](R/bit64.R) holds the bit64 methods and `as_integer64()`.
- [`R/types.R`](R/types.R) has the constructors, the `NA_*_` constants and
  `zu_storage()`; [`R/cast.R`](R/cast.R) is the one conversion path every
  method uses; [`R/conditions.R`](R/conditions.R) lists the condition
  classes.
- [`R/vector.R`](R/vector.R) holds the base vector methods, written once and
  registered for all four classes from the `zu_methods` table through
  `@evalNamespace`. To add a method, add it to that table.
- [`R/promote.R`](R/promote.R) is the promotion order (`zu_common2()`), and
  [`R/ops.R`](R/ops.R) the `Ops` and `Math` group methods and the
  `checked_*` / `wrapping_*` functions. R picks the common type and
  converts zuint and double operands to it; integer operands go to C as
  they are.
- [`src/zu_ops.h`](src/zu_ops.h) is the policy layer over zufast's checked
  and wrapping primitives: each operation reports OK, NA or overflow, and
  the caller applies the policy. [`src/zu_arith.c`](src/zu_arith.c) holds
  the vectorised loops, `^` by squaring, and exact comparison of any two
  operand kinds, doubles included.

## Invariants that are easy to break

- **`int64` keeps the bit64 layout**: a REALSXP whose bits are `int64_t`,
  class `c("zu_int64", "integer64")`. data.table, arrow, duckdb and others
  read `REAL(x)` as `int64_t*`; any other layout breaks them silently.
- **Never register methods on bare `integer64`**, only on `zu_*` classes.
  Otherwise zuint changes bit64's behaviour for everyone who loads it.
- **Every method bit64 defines for `integer64`, zuint defines for
  `zu_int64`.** A missing one falls through to bit64's method when bit64 is
  loaded and to base R on the raw bits when it is not, so the answer would
  depend on what else is attached.
- **`chooseOpsMethod()` must return TRUE for every `zu_*` class.** Without
  it, `zu_int64 + integer64` warns "incompatible methods" and R does double
  arithmetic on the bits. This is why `R (>= 4.3.0)`. bit64 4.8 defines
  `chooseOpsMethod.integer64()` returning TRUE as well, and R asks the left
  operand first, so `integer64 + zu_int64` runs bit64's (exact) method and
  returns an `integer64`. Changing that would need a method on bare
  `integer64`, which the rule above forbids. For the wider types bit64 asks
  `is.numeric()` (TRUE for every zuint type) and then `as.integer64()`,
  whose zuint methods (`R/bit64.R`, registered when bit64 loads) convert
  exactly or give NA with a `zuint_cast_warning`; without them bit64
  converted an int128 operand through double.
- **`test-bit64-parity.R` diffs bit64's method list against ours.** A base
  generic bit64 gives an `integer64` method needs a `zu_int64` method, or an
  entry in that test's allowlist (group generics, functions bit64 masks).
- **128-bit values cross the Arrow bridge as the `arrow.opaque`
  hugeint/uhugeint extension**, not as `decimal128(38, 0)`: DuckDB reads the
  decimal back as DECIMAL, and the decimal form reads UHUGEINT ≥ 2¹²⁷ as
  negative (design §9.1).
- **128-bit arithmetic comes from `zufast/wide.h`**, not from code written
  here. `zu_ops.h` holds only the NA and overflow-policy layer, so zuint and
  zutempo share one implementation. The portable fallback
  (`ZUF_NO_INT128`) must keep building.
- **Signed overflow must never reach C undefined behaviour.** Check before
  the operation, using the checked or wrapping primitives.
- **Mixed-type operations are lossless or an error**, following the
  promotion lattice in design §5. Never coerce through double.
- **Base R pads with its own NA, which is a valid value here.** `x[i]` past
  the end, `x[i] <- v` past the end and `length<-` fill with `NA_real_` or
  `NA_complex_`, whose bits are an ordinary int64 or int128. The methods in
  `R/vector.R` find the padded positions and write the type's sentinel;
  any new method that can grow a vector must do the same.
- **Bits move between doubles and integers by `memcpy` only.** A cast
  through `double` would canonicalise the NaN payloads that negative int64
  values and the unsigned NAs occupy.
- **The `NA_*_` constants are built in pure R at install time**, from bit
  patterns (`-0` is INT64_MIN), because the shared object is not loaded
  when the package's R code is evaluated.
- **Integer operands reach the C arithmetic unconverted.** A negative
  integer meeting an unsigned type is part of the operation (an overflow,
  or under wrapping its value modulo 2^width). Converted to a payload
  first, -1 would wrap onto the unsigned NA pattern and read as NA.
- **A wrapped result on the NA pattern is NA, but an exact result on it is
  an overflow.** `zu_ops.h` reports both as overflow; only the wrapping
  policy stores the bits, which then read as NA (design §6).
- **Never write and read one variable in the arguments of a single call.**
  `f(g(&r), r)` reads `r` before or after `g()` writes it, as the compiler
  pleases: gcc at `-O0` read it first and stored garbage, which only the
  coverage build (gcc, `-O0`, Linux) showed. Compute into a local first.
- **Hex and binary text is sign and magnitude, never two's complement.**
  `format_hex(int64(-1))` is `"-0x1"`, so every string the package writes
  reads back as the same value; `"0xffffffffffffffff"` is a uint64.
- **Shifts by the full width are undefined.** `x >> 64` on a `uint64_t`
  is UB, and UBSan caught one in Stage 1; shift 128-bit values with
  zufast's `zuf_int_u128_shr()`/`shl()`, which take 0..127.
- **An exported Arrow struct must never call into R.** A consumer may call
  `release` from any thread, so `zu_to_arrow_c()` allocates the structs and
  buffers with `malloc`, and the release callbacks only `free`. It returns
  an array handle in nanoarrow's `r.h` layout (class `nanoarrow_array`, the
  schema's external pointer in its tag), which is what zuarrow requires of
  a `from` handler.
- **A sentinel value is zuarrow's policy, in zuarrow's classes.** The `to`
  handler raises `zuarrow_lossy_error` under `"error"` and `"character"`
  and `zuarrow_lossy_warning` under `"warn"` (design §9.1, review X4), never
  a zuint class, so a caller handles it with zuarrow's other conditions.
- **Import borrows; it never releases the caller's structs.** The struct
  owner (nanoarrow, an engine) releases them. Our own exported structs are
  released by their external pointer's finalizer unless a consumer moved
  them out, which sets `release` to NULL; `test-arrow.R` counts the calls.
- **A decimal128 imports as its bits, with no 38-digit range check,** and
  only when the caller asks with `to = int128()`: zuint registers no `d:*`
  key (review X5). DuckDB's default export writes HUGEINT values beyond 38
  digits that way.
- **The Arrow import refuses what it cannot read as values.** A
  dictionary-encoded array has its indices' format (`l` for int64 indices)
  and a schema with children is nested; both are `zuint_arrow_error`. The
  binary metadata has no total length, so its parser rejects negative counts
  and lengths and caps the entries; `zu_metadata_get_c()` tests it bounded.
- **arrow aborts R on the `arrow.opaque` type as an R object.**
  `arrow::as_arrow_array()`, `infer_type()` and `as_data_type()` crash on
  it in arrow 24.0.0 and 25.0.1, with or without zuint: an unchecked cast in
  `ExtensionType__r6_class()`, reported as
  [apache/arrow#53951](https://github.com/apache/arrow/issues/53951). So the
  tests move tables between zuarrow and arrow as IPC streams
  (`helper-arrow.R`), which never make that R object.
- **Register an Arrow Table with DuckDB, not a record batch reader.** A
  registered reader is consumed by the first query and is empty after.
- **Open DuckDB with `shared_home = FALSE` in tests** (#74), or it writes
  under `~/.duckdb`.
- **`xtfrm()` must return exact integer ranks.** Base `order()`, `rank()`
  and `sort()` on several keys go through it; a double proxy would tie
  values beyond 2^53. `match()`, `%in%` and `table()` go through `mtfrm()`,
  which returns the exact decimal text, because `match()` is not generic and
  no other atomic vector maps these values one to one. `zu_match()` and
  `%zin%` are the fast, hash-based equivalents.
- **A 128-bit sum counts its wrap-arounds.** `sum()` of an int128 that
  passes beyond the range and comes back is exact, so the accumulator wraps
  modulo 2^128 and counts each wrap; only a non-zero count, or the NA
  pattern, at the end is an overflow.
- **bit64 masks `order`, `match`, `%in%`, `table` and `rank` as functions,**
  not methods. For int64 they agree with base R except `rank()`, which keeps
  NA as NA under bit64 and ranks it last under base R. The parity tests
  cover the generics; these are bit64's to define.
- **The vctrs equality and ordering proxy is exact 32-bit pieces, never the
  payload.** vctrs treats every NaN bit pattern as one value, and many int64
  values are NaN patterns as doubles (-1 and -2 among them).
- **vctrs' proxy carries a flag next to the payload.** vctrs fills the slots
  it creates (`vec_init()`, padding, unmatched joins, an NA index) with
  `NA_real_` or `NA_complex_`, whose bits are a valid value here; the flag
  column, never NA for a real row, is how `vec_restore()` knows to write the
  type's NA instead. Every proxy must have the same columns, so vctrs
  operations drop names, as for vctrs' own records.
- **Hot paths pass classed objects straight to C.** `attributes(x) <- NULL`
  (`zu_bare()`) copies the vector; the C code ignores attributes. Strip only
  where an R-level `c()` would otherwise dispatch back to the method.
- **`src/zu_parse.c` and `src/zu_metadata.c` never call R.** The fuzz
  target and the mutation driver (`tools/fuzz/`) build them with R's
  headers but without libR; an `Rf_*` call there breaks both builds.
- **`src/zu_fixed.c` and `src/zu_api.c` never include R or call it.**
  Another package calls them through `zuint_api_v1` on any thread, and
  `tools/fixed/` builds them with no R headers at all; `zuint.h` includes
  only `<stddef.h>` and `<stdint.h>`.
- **`zuint_api_v1` only grows.** Members are appended, never reordered or
  removed; an append grows `struct_size` and keeps `ZUINT_ABI_VERSION`,
  any other change bumps it. `zu_api_c()` and `test-fixed.R` list every
  member, so a new one must be added there too.
- **The DECIMAL parser follows DuckDB 2.0.0's acceptance, not its
  values.** Which texts are read comes from the port of DuckDB's state
  machine (`dk_*`, credited in `inst/COPYRIGHTS`); the value comes from
  the digits, exactly. Its two deviations from DuckDB are in design §2.2,
  and `test-fixed.R` allows no other difference.
- **Native routines are called through their registered symbols.**
  `init.c` calls `R_forceSymbols()`, so `.Call("name", ...)` with a string
  fails; use the symbol `useDynLib(.registration = TRUE)` defines.

Add each new one when a stage establishes it.

## Testing

- **gmp is the oracle for values.** `helper-oracle.R` gives each type's
  range, edge values, out-of-range values and random fills, computed with
  gmp, and skips without it.
- **Run the int64 tests with and without bit64 attached.** Any difference
  means a method is missing on `zu_int64` (see Invariants). The
  bit64-attached run also covers mixed `zu_int64` ⊕ `integer64` dispatch.
  `helper-bit64.R` runs a string of R code in two fresh Rscript processes,
  one with bit64 attached and one where it never loaded, because S3 methods
  stay registered once a namespace has loaded; it skips on CRAN. The code it
  compares is the named list `bit64_parity_code`, evaluated once per run for
  every test.
- **The round-trip matrix is `test-roundtrip.R`** (design §12): DuckDB,
  Arrow and Parquet paths for BIGINT, UBIGINT, HUGEINT and UHUGEINT, through
  zuarrow, with the values of `matrix_values()` in `helper-arrow.R`. It
  skips without zuarrow, duckdb, DBI, arrow and nanoarrow; CI installs them,
  zuarrow from GitHub until it is on CRAN. Each Arrow test starts with
  `skip_without_zuarrow()`.
- **The suite runs in about 10 seconds locally** (2026-10-16), most of it
  the bit64 processes and DuckDB.

## Continuous integration

The shared workflows this package calls:

- `R-CMD-check.yaml`: `r-cmd-check.yml` with `nosuggests` and `nold` on,
  and a second job, `no-int128`, that builds zufast's portable fallback (see
  Commands). `tools/ci-binaries.R` installs duckdb from r-universe's R-devel
  binaries when they exist, and the timeout is 90 minutes for a cold cache
  that builds it from source.
- `native-checks.yml`: `sanitizers.yml`, `valgrind.yml` (with
  `tools/valgrind.supp` for arrow's worker threads), `lto.yml`,
  `gctorture.yml` (step 20 with a 180-minute timeout: the full suite
  takes about 140), `rchk.yml`, `analyzers.yml`, `cran-special.yml` and
  `vendor.yml`. Until zufast 0.1.1 is on CRAN, `rchk.yml` installs it
  through `github-packages`, because the rchk image ignores `Remotes:`.
- `coverage.yaml`: `coverage.yml`, pinned to a commit, with its badge on
  `gh-pages` because `main` takes no direct pushes.
- `pkgdown.yaml`: `pkgdown.yml`, which keeps `CLAUDE.md` off the site.
- `cran-release.yaml`: `cran-release.yml`, pinned to a commit.
- `assurance.yaml`: `assurance.yml`, which checks
  [`.agents/assurance.md`](.agents/assurance.md).
- `fuzz.yaml`: `fuzz.yml` over `tools/fuzz/harness.c`, which compares the
  text parser and the metadata reader with references written from their
  specs. 120 seconds on a pull request, half an hour on a dispatch.
- `fixed.yaml`, the package's own: `tools/fixed/fixed` (Commands) under
  ASan and UBSan, with zufast's fallback, and under ThreadSanitizer,
  gated by `changes.yml`; 200,000 differential cases on the quick
  profile, 5,000,000 on the full.
- `mutation.yaml` and `alloc-failure.yaml`, on dispatch only:
  `mutation.yml` runs `tools/fuzz/driver` against each mutant of the two
  readers, and `alloc-failure.yml` fails each allocation of
  `tools/alloc-exercise.R` in turn.
- `format.yaml`, the package's own: `air format . --check`, gated by
  `changes.yml`. Run `air format .` before pushing R code; `air.toml`
  sets the width, and `.git-blame-ignore-revs` lists formatting-only
  commits.

Two deliberate deviations from the shared CI rules:

- **No weekly `schedule:`.** It was removed on 2026-11-15, before the
  repository went private, where Actions minutes are metered. Run the full
  set on demand instead: `gh workflow run R-CMD-check.yaml --ref main` and
  `gh workflow run native-checks.yml --ref main`.
- **The quick profile runs UBSan on R-release and no container.** The
  engine Suggests (arrow, duckdb) have no R-devel binaries, and building
  them from source takes about half an hour. The full profile keeps CRAN's
  R-devel flavours, and pays that cost when the dependency cache is cold.

## Vendored native code

[`src/vendor/arrow/abi.h`](src/vendor/arrow/abi.h) is the Arrow C Data
Interface header from Apache Arrow 26.0.0 (Apache-2.0), byte for byte, with
its `LICENSE.txt` and `NOTICE.txt`. It declares structs only; only
`src/zu_arrow.c` includes it. [`src/vendor/PROVENANCE`](src/vendor/PROVENANCE)
records the tag, commit, URLs, checksums and update procedure, and
`tools/verify-vendor` re-downloads and compares them (`--canary` proves the
check can fail). CI runs it through `vendor.yml`, which also fails a pull
request that changes the vendor tree without changing `PROVENANCE`. There
are no local patches.
