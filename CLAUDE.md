# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## What this is

zuint gives R lossless wide integer vectors, `int64`, `uint64`, `int128`
and `uint128`, so that every integer type Arrow and DuckDB produce
survives the trip into R and back with its schema and values intact. All
four types share one C core and one promotion lattice. `int64` keeps the
bit64 `integer64` layout so existing consumers read it unchanged, and
within that layout it is a stricter second implementation: exact or
explicit, overflow as a policy, summaries in the right type (design
§0.1). Dependencies outside the zu-\* family are allowed only in
`Suggests` (design §2.1): zufast (\>= 0.1.1) is `LinkingTo` only, R (\>=
4.3.0) is required for
[`chooseOpsMethod()`](https://rdrr.io/r/base/chooseOpsMethod.html), and
bit64, nanoarrow, arrow, duckdb, vctrs, pillar and gmp are Suggests used
in tests and lazily registered methods. It does not fork bit64, do
arithmetic on small integer types, offer arbitrary precision, handle
decimals (the companion `decimal` package does, and depends on zuint,
never the reverse), or do matrix algebra.

The specification is
[`.agents/design.md`](https://pedrobtz.github.io/zuint/.agents/design.md),
adopted from [RFC
0009](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0009-zuint-wide-integers.md).
It outranks this file: `CLAUDE.md` orients, the design doc decides.

## Current state

Scaffolded 2026-10-15 with `create-pkg.sh`; no functionality yet. The
roadmap in `.agents/roadmap.md` takes it to v0.1.0. The design’s
milestones number versions differently (its first CRAN release is
“v0.3”); the roadmap maps them onto 0.1.0.

## Stage tracking

Progress toward the next version is tracked as GitHub sub-issues, so the
parent issue shows a progress bar such as “6 of 7”.

- **One parent issue per target version**, titled with the bare version,
  for example `v0.1.0`. `v0.1.0` issue: created by `pkg-roadmap`.
- **One sub-issue per roadmap stage**, titled as the roadmap titles it,
  for example `Stage 3 — R interface`, and linking to that section. The
  number of stages is whatever the roadmap has; there is no fixed scale.
- **Every tracking issue carries the `stage` label**, so it can be told
  apart from bug and feature issues and left out of open-issue counts.
- **Close a stage by merging its pull request.** Put `Closes #<n>` in
  the body of the stage’s pull request. Never close a stage whose exit
  criteria are not met; record a deviation in the roadmap first.
- **The roadmap stays authoritative.** The issues record which stages
  are done, not what a stage requires. Adding, removing or renaming a
  stage means editing the roadmap and the sub-issues in the same change.
- **Each stage has a CI tier, `quick` or `full`.** The roadmap sets it,
  and `quick` is the default. See Continuous integration for what each
  means. The second-to-last stage, `Full CI`, runs the full set and
  fixes what it finds before `v0.1.0 readiness`.
- Close the parent issue when CRAN accepts the version and it is tagged.
  Opening a parent issue implies at least one stage sub-issue; a parent
  with no sub-issues shows no progress on the board.

## Versioning

A new package develops at `0.0.0.9000` and targets `0.1.0` for its first
CRAN release. Set `Version: 0.1.0` and the matching `NEWS.md` heading
when the package enters `Pre-flight`. Bump to `0.1.0.9000` only after
CRAN accepts it, never before: a `.9000` version above an unreleased
`0.1.0` heading is wrong.

Until the first release the R API may change freely. Sibling packages
can still depend on this one before CRAN does, through `Remotes:` or
`LinkingTo:`. A package that others wait on should reach CRAN first.

zuint itself waits on zufast: the 128-bit primitives come from its
`wide.h` header, so zufast (\>= 0.1.1) must be on CRAN before zuint is
submitted. Until then development builds against zufast’s dev version:
`DESCRIPTION` has `LinkingTo: zufast (>= 0.1.0.9000)` and
`Remotes: pedrobtz/zufast`. When zufast 0.1.1 is released, raise the
constraint to `>= 0.1.1` and delete `Remotes:` in the same commit. CRAN
rejects a `Remotes:` field, so this is part of entering `Pre-flight`.

## Commands

Run from the package root.

``` sh
Rscript -e 'devtools::load_all()'                # compile src/ and load
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::test(filter = "<name>")'   # one test file
Rscript -e 'devtools::test(shuffle = TRUE)'      # order independence
Rscript -e 'devtools::check()'                   # R CMD check
air format .                                     # format R sources
```

The fallback for compilers without `__int128` is built by setting
`ZUINT_CPPFLAGS=-DZUF_NO_INT128` in the environment, which
[`src/Makevars`](https://pedrobtz.github.io/zuint/src/Makevars) passes
to the compiler. Clean the old objects first, and set
`ZUINT_EXPECT_INT128=false` so `test-storage.R` confirms the fallback
really was built:

``` sh
Rscript -e 'devtools::clean_dll()'
ZUINT_CPPFLAGS=-DZUF_NO_INT128 ZUINT_EXPECT_INT128=false \
  Rscript -e 'devtools::test()'
Rscript -e 'devtools::clean_dll()'               # back to the native build
```

CI runs this as the `no-int128` job of `R-CMD-check.yaml`, on every pull
request.

`tools/verify-vendor` checks the vendored Arrow header against upstream
(see Vendored native code); run it after touching `src/vendor/`.

## Architecture

Grows with the stages; `.agents/design.md` §10 has the planned C layout.

- [`src/zu_wide.h`](https://pedrobtz.github.io/zuint/src/zu_wide.h) is
  the type layer: the type codes, the NA sentinels, raw word access to
  the REALSXP and CPLXSXP payloads, and `zu_val`, a sign plus a 128-bit
  magnitude that slow paths use to move a value between types with one
  range check (`zu_val_fits()`).
- [`src/zu_cast.c`](https://pedrobtz.github.io/zuint/src/zu_cast.c)
  holds construction and conversion. Entry points that can lose a value
  return `list(result, n_lost)` and R raises the warning, so condition
  classes live only in R. Text goes through the one parser in
  [`src/zu_parse.c`](https://pedrobtz.github.io/zuint/src/zu_parse.c),
  and out through
  [`src/zu_format.c`](https://pedrobtz.github.io/zuint/src/zu_format.c).
- [`src/zu_bits.c`](https://pedrobtz.github.io/zuint/src/zu_bits.c) and
  [`R/bits.R`](https://pedrobtz.github.io/zuint/R/bits.R) are the bit
  operations; [`R/text.R`](https://pedrobtz.github.io/zuint/R/text.R) is
  [`format_hex()`](https://pedrobtz.github.io/zuint/reference/format_hex.md)
  and
  [`format_bin()`](https://pedrobtz.github.io/zuint/reference/format_hex.md).
- [`src/zu_arrow.c`](https://pedrobtz.github.io/zuint/src/zu_arrow.c) is
  the Arrow C Data Interface bridge, and
  [`R/arrow.R`](https://pedrobtz.github.io/zuint/R/arrow.R) its R
  surface.
  [`R/nanoarrow.R`](https://pedrobtz.github.io/zuint/R/nanoarrow.R)
  holds the nanoarrow methods, which
  [`R/zzz.R`](https://pedrobtz.github.io/zuint/R/zzz.R) registers when
  nanoarrow loads; nothing else touches a Suggests package.
- [`R/engines.R`](https://pedrobtz.github.io/zuint/R/engines.R) is the
  engine glue:
  [`as_integer64()`](https://pedrobtz.github.io/zuint/reference/as_integer64.md),
  [`zu_duckdb_query()`](https://pedrobtz.github.io/zuint/reference/zu_duckdb_query.md)
  and
  [`zu_duckdb_register()`](https://pedrobtz.github.io/zuint/reference/zu_duckdb_query.md),
  [`zu_arrow_table()`](https://pedrobtz.github.io/zuint/reference/zu_arrow_table.md)
  and
  [`zu_from_arrow_table()`](https://pedrobtz.github.io/zuint/reference/zu_arrow_table.md),
  and the arrow methods `R/zzz.R` registers when arrow loads. Each
  function checks for the Suggests packages it needs.
- [`R/types.R`](https://pedrobtz.github.io/zuint/R/types.R) has the
  constructors, the `NA_*_` constants and
  [`zu_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md);
  [`R/cast.R`](https://pedrobtz.github.io/zuint/R/cast.R) is the one
  conversion path every method uses;
  [`R/conditions.R`](https://pedrobtz.github.io/zuint/R/conditions.R)
  lists the condition classes.
- [`R/vector.R`](https://pedrobtz.github.io/zuint/R/vector.R) holds the
  base vector methods, written once and registered for all four classes
  from the `zu_methods` table through `@evalNamespace`. To add a method,
  add it to that table.
- [`R/promote.R`](https://pedrobtz.github.io/zuint/R/promote.R) is the
  promotion order (`zu_common2()`), and
  [`R/ops.R`](https://pedrobtz.github.io/zuint/R/ops.R) the `Ops` and
  `Math` group methods and the `checked_*` / `wrapping_*` functions. R
  picks the common type and converts zuint and double operands to it;
  integer operands go to C as they are.
- [`src/zu_ops.h`](https://pedrobtz.github.io/zuint/src/zu_ops.h) is the
  policy layer over zufast’s checked and wrapping primitives: each
  operation reports OK, NA or overflow, and the caller applies the
  policy.
  [`src/zu_arith.c`](https://pedrobtz.github.io/zuint/src/zu_arith.c)
  holds the vectorised loops, `^` by squaring, and exact comparison of
  any two operand kinds, doubles included.

## Invariants that are easy to break

- **`int64` keeps the bit64 layout**: a REALSXP whose bits are
  `int64_t`, class `c("zu_int64", "integer64")`. data.table, arrow,
  duckdb and others read `REAL(x)` as `int64_t*`; any other layout
  breaks them silently.

- **Never register methods on bare `integer64`**, only on `zu_*`
  classes. Otherwise zuint changes bit64’s behaviour for everyone who
  loads it.

- **Every method bit64 defines for `integer64`, zuint defines for
  `zu_int64`.** A missing one falls through to bit64’s method when bit64
  is loaded and to base R on the raw bits when it is not, so the answer
  would depend on what else is attached.

- **[`chooseOpsMethod()`](https://rdrr.io/r/base/chooseOpsMethod.html)
  must return TRUE for every `zu_*` class.** Without it,
  `zu_int64 + integer64` warns “incompatible methods” and R does double
  arithmetic on the bits. This is why `R (>= 4.3.0)`. bit64 4.8 defines
  `chooseOpsMethod.integer64()` returning TRUE as well, and R asks the
  left operand first, so `integer64 + zu_int64` runs bit64’s (exact)
  method and returns an `integer64`. Changing that would need a method
  on bare `integer64`, which the rule above forbids.

- **128-bit values cross the Arrow bridge as the `arrow.opaque`
  hugeint/uhugeint extension**, not as `decimal128(38, 0)`: DuckDB reads
  the decimal back as DECIMAL, and the decimal form reads UHUGEINT ≥
  2¹²⁷ as negative (design §9.1).

- **128-bit arithmetic comes from `zufast/wide.h`**, not from code
  written here. `zu_ops.h` holds only the NA and overflow-policy layer,
  so zuint and zutempo share one implementation. The portable fallback
  (`ZUF_NO_INT128`) must keep building.

- **Signed overflow must never reach C undefined behaviour.** Check
  before the operation, using the checked or wrapping primitives.

- **Mixed-type operations are lossless or an error**, following the
  promotion lattice in design §5. Never coerce through double.

- **Base R pads with its own NA, which is a valid value here.** `x[i]`
  past the end, `x[i] <- v` past the end and `length<-` fill with
  `NA_real_` or `NA_complex_`, whose bits are an ordinary int64 or
  int128. The methods in `R/vector.R` find the padded positions and
  write the type’s sentinel; any new method that can grow a vector must
  do the same.

- **Bits move between doubles and integers by `memcpy` only.** A cast
  through `double` would canonicalise the NaN payloads that negative
  int64 values and the unsigned NAs occupy.

- **The `NA_*_` constants are built in pure R at install time**, from
  bit patterns (`-0` is INT64_MIN), because the shared object is not
  loaded when the package’s R code is evaluated.

- **Integer operands reach the C arithmetic unconverted.** A negative
  integer meeting an unsigned type is part of the operation (an
  overflow, or under wrapping its value modulo 2^width). Converted to a
  payload first, -1 would wrap onto the unsigned NA pattern and read as
  NA.

- **A wrapped result on the NA pattern is NA, but an exact result on it
  is an overflow.** `zu_ops.h` reports both as overflow; only the
  wrapping policy stores the bits, which then read as NA (design §6).

- **Never write and read one variable in the arguments of a single
  call.** `f(g(&r), r)` reads `r` before or after `g()` writes it, as
  the compiler pleases: gcc at `-O0` read it first and stored garbage,
  which only the coverage build (gcc, `-O0`, Linux) showed. Compute into
  a local first.

- **Hex and binary text is sign and magnitude, never two’s complement.**
  `format_hex(int64(-1))` is `"-0x1"`, so every string the package
  writes reads back as the same value; `"0xffffffffffffffff"` is a
  uint64.

- **Shifts by the full width are undefined.** `x >> 64` on a `uint64_t`
  is UB, and UBSan caught one in Stage 1; shift 128-bit values with
  zufast’s `zuf_int_u128_shr()`/`shl()`, which take 0..127.

- **An exported Arrow struct must never call into R.** A consumer may
  call `release` from any thread, so `zu_to_arrow_c()` allocates the
  structs and buffers with `malloc`, and the release callbacks only
  `free`.

- **Import borrows; it never releases the caller’s structs.** The struct
  owner (nanoarrow, an engine) releases them. Our own exported structs
  are released by their external pointer’s finalizer unless a consumer
  moved them out, which sets `release` to NULL; `test-arrow.R` counts
  the calls.

- **A decimal128 imports as its bits, with no 38-digit range check.**
  DuckDB’s default export writes HUGEINT values beyond 38 digits that
  way.

- **arrow 24.0.0 aborts R on the `arrow.opaque` type as an R object.**
  [`arrow::as_arrow_array()`](https://arrow.apache.org/docs/r/reference/as_arrow_array.html),
  `infer_type()` and `as_data_type()` crash on it, with or without
  zuint. So the arrow methods exist for int64 and uint64 only (the
  128-bit ones raise `zuint_unsupported_error`), and tables go through
  nanoarrow
  ([`zu_arrow_table()`](https://pedrobtz.github.io/zuint/reference/zu_arrow_table.md)),
  which never makes that R object.

- **Register an Arrow Table with DuckDB, not a record batch reader.** A
  registered reader is consumed by the first query and is empty after.

- **Native routines are called through their registered symbols.**
  `init.c` calls `R_forceSymbols()`, so `.Call("name", ...)` with a
  string fails; use the symbol `useDynLib(.registration = TRUE)`
  defines.

Add each new one when a stage establishes it.

## Testing conventions

- **Self-sufficient.** Every test builds its own inputs inside the
  `test_that()` block. No file-scope objects.
- **Self-contained.** Global state goes through `withr::local_*()`,
  randomised input through
  [`withr::local_seed()`](https://withr.r-lib.org/reference/with_seed.html).
  Tests write only under
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).
- **Assert on condition classes, never message text.** Use
  `expect_error(..., class = "<pkg>_<kind>_error")`. Wording belongs in
  snapshot tests.
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of
  the definition of done.
- **Borrow a conformance suite before writing one.** Mainstream
  implementations in Python, Java, Go or Node usually ship a test
  corpus. Use it as an oracle rather than inventing cases by hand. `gmp`
  is the oracle for values (`helper-oracle.R`); the DuckDB/Arrow/Parquet
  round-trip matrix, the acceptance test, arrives in Stage 5.
- **Run the int64 tests with and without bit64 attached.** Any
  difference means a method is missing on `zu_int64` (see Invariants).
  The bit64-attached run also covers mixed `zu_int64` ⊕ `integer64`
  dispatch.
- **Helpers live in `tests/testthat/helper-*.R`.** `helper-oracle.R`
  gives each type’s range, edge values, out-of-range values and random
  fills, computed with gmp (and skips without it). `helper-bit64.R` runs
  a string of R code in two fresh Rscript processes, one with bit64
  attached and one where it never loaded, because S3 methods stay
  registered once a namespace has loaded; it skips on CRAN.
- **The round-trip matrix is `test-roundtrip.R`** (design §12): DuckDB,
  Arrow and Parquet paths for BIGINT, UBIGINT, HUGEINT and UHUGEINT,
  with the values of `matrix_values()` in `helper-arrow.R`. It skips
  without duckdb, DBI, arrow and nanoarrow; CI installs them.
- **Keep the suite inside the CRAN time budget.** About 10 seconds
  locally (2026-10-16), most of it the bit64 processes and DuckDB.

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors,
0 warnings and 0 notes. The one allowed note is “New submission” before
the first release. `devtools::test(shuffle = TRUE)` green. CI green at
the change’s tier: the quick profile for a `quick` roadmap stage or an
ordinary pull request, the full profile for a `full` stage, `Full CI`,
and every release. A user-facing change also needs a test, roxygen
documentation and a `NEWS.md` entry.

## Releasing to CRAN

- **CI is the pre-submission check.** The `pedrobtz/r-actions` R CMD
  check runs `--as-cran` on the CRAN-like runners and containers, and it
  replaces win-builder, the macOS builder and R-hub. None of them is a
  release step, and `cran-comments.md` lists the CI legs as its test
  environments.
- **Entering `Pre-flight`.** The roadmap’s feature stages are done, the
  version is set as in Versioning, `NEWS.md` and `cran-comments.md` are
  written, and CI is green. Only submission work remains.
- **Before submitting,** run the `cran-extrachecks` and
  `review-cran-submission` skills, and resolve every finding.
- **The pretest is automated and does not read `cran-comments.md`.** A
  NOTE that is explained but not fixed gets the upload archived. Fix the
  NOTE, as under Vendored native code, instead of justifying it.
- **After acceptance,** tag `v0.1.0`, publish the GitHub release, bump
  to `0.1.0.9000`, and close the version’s parent issue.

## Editing rules

- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by
  hand.
- Edit `README.Rmd`, not the generated `README.md`.
- Keep prose simple and short. One idea per sentence.
- Wrap roxygen text at 80 characters and run `air format .` on R
  sources.
- Use `lower_snake_case`, and prefix internal native symbols with
  `<pkg>_`.
- Keep hard runtime dependencies at zero unless a recorded design
  decision says otherwise.
- Export and document public functions. Do not create roxygen topics for
  internal ones.

## Continuous integration

Workflows come from `pedrobtz/r-actions`. Call those reusable workflows
instead of writing bespoke ones, and pin a released tag rather than
`main`. Pin a workflow that holds a write token, such as `coverage.yml`,
to a commit, with the tag in a comment. The `R-CMD-check` workflow must
call `r-cmd-check.yml`, because a hand-rolled one does not count as the
pre-submission check.

This package calls `r-cmd-check.yml@v1` with `nosuggests` and `nold` on
(from `R-CMD-check.yaml`); `valgrind.yml`, `lto.yml`, `gctorture.yml`,
`rchk.yml`, `analyzers.yml` and `cran-special.yml` (from
`native-checks.yml`); and `coverage.yml`, pinned to the v1 commit, with
its badge on `gh-pages` because `main` takes no direct pushes (from
`coverage.yaml`). `pkgdown.yaml` is the r-lib example workflow, not a
shared one; its deploy uses `force: false` so it cannot overwrite a
badge commit. Until zufast 0.1.1 is on CRAN, `rchk.yml` installs it
through `github-packages`.

The engine Suggests (arrow, duckdb) have no R-devel binaries, and
building them from source takes about half an hour. So the quick profile
runs UBSan on R-release and no container; the full profile keeps CRAN’s
R-devel flavours, and pays that cost when the dependency cache is cold.

Small edits get a small run. The shared workflows look at the files a
pull request changes, compared with its merge base:

- **Markdown only**, such as `README.md`, `NEWS.md` or
  `cran-comments.md`, skips every check. Only coverage and the pkgdown
  site run.
- **`DESCRIPTION` or `README.Rmd` as well**, and nothing else, adds one
  R CMD check on Ubuntu R-release.
- **Any other file** runs everything.

So put a README or `DESCRIPTION` touch-up in its own pull request. Once
a pull request changes code, every later push to it runs every workflow.

### Quick by default, full by exception

The full profile is slow. gctorture at step 20 alone has taken 36 to 107
minutes on sibling packages. Waiting on it between roadmap stages was
the main thing slowing roadmaps down, so:

- **Pull requests run the quick profile.** It should finish in under
  five minutes. If it doesn’t, raise gctorture’s `quick-step` or trim
  `quick-containers` in the caller workflows; never cut the full
  profile.
- **A `full` roadmap stage takes the `full-ci` label** and merges only
  on a green full run. The roadmap gives the reason in the stage’s
  `**CI.**` line, for example first compiled code, a `PROTECT` or
  finalizer change, a vendored library, or a Windows-only path.
- **Don’t wait on the full run a merge starts** on the default branch,
  and cancel older full runs it supersedes. A failure that only the full
  set shows goes on the `Full CI` stage issue as a comment with the run
  link, and is fixed there. A failure the quick profile also shows is
  fixed now.
- **`Full CI` and `v0.1.0 readiness` wait** for a green full run on
  their merge commit, and the release commit always needs one.
- Locally, run `gctorture(TRUE)` on the code a C change touches when it
  is cheap; the full run is the authority.

## Vendored native code

[`src/vendor/arrow/abi.h`](https://pedrobtz.github.io/zuint/src/vendor/arrow/abi.h)
is the Arrow C Data Interface header from Apache Arrow 26.0.0
(Apache-2.0), byte for byte, with its `LICENSE.txt` and `NOTICE.txt`. It
declares structs only; only `src/zu_arrow.c` includes it.
[`src/vendor/PROVENANCE`](https://pedrobtz.github.io/zuint/src/vendor/PROVENANCE)
records the tag, commit, URLs, checksums and update procedure, and
`tools/verify-vendor` re-downloads and compares them (`--canary` proves
the check can fail). CI runs it through `vendor.yml`, which also fails a
pull request that changes the vendor tree without changing `PROVENANCE`.
There are no local patches.

- Pin a stable upstream release, never `master` or a release candidate.
- Record the tag, the commit and the checksums, and write down the
  update procedure so the next bump is mechanical.
- Keep upstream `LICENSE` and `NOTICE` under `src/vendor/<lib>/`,
  declare the vendored code in `DESCRIPTION` and `inst/COPYRIGHTS`.
- Keep the vendor tree clearly separated from first-party source, and
  record every local patch and why it exists.
- **CRAN’s compiled-code check applies to vendored code too.** No
  `stdout` or `stderr`, no `printf`, `abort`, `exit` or system RNG may
  be linked, even behind a debug switch that never runs. Remove them
  with a patch in `tools/patches/`, list it in `src/vendor/PROVENANCE`,
  and make the vendor-verify script check “upstream plus exactly these
  patches”. Avoid diagnostic-suppressing pragmas too, because they draw
  their own NOTE. zuhtml is the reference:
  `tools/patches/0002-no-stdio.patch` and `tools/verify-vendor`. zuxml’s
  first upload was archived because it justified such a symbol instead
  of patching it.
- Guard against regressions in CI: run `nm -u` on the built objects and
  fail on any of those symbols, so an upstream bump cannot bring them
  back.

## Commits and pull requests

Short, imperative, sentence-case commit subjects, optionally scoped.
Keep each commit focused and do not sweep in unrelated files. A pull
request explains the user-visible outcome and the rationale, links
related issues, lists the checks that were run and the tests that were
skipped, and flags platform-sensitive or vendored changes. Performance
claims need evidence.

Never commit or push to the default branch. Work on a branch, open a
pull request, and leave it for review. Do not merge a pull request
unless you are told to.

When you find a defect, in this package or in an upstream tool, open an
issue for it rather than only working around it.
