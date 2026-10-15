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

## Architecture

To be written as stages land; see `.agents/design.md` (§10 for the
planned C layout). The scaffold set up a C layer with
`usethis::use_c()`:
[`src/zuint.c`](https://pedrobtz.github.io/zuint/src/zuint.c) is an
empty stub and
[`R/zuint-package.R`](https://pedrobtz.github.io/zuint/R/zuint-package.R)
holds `@useDynLib`.

## Invariants that are easy to break

None established by code yet. The design already fixes these:

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
  arithmetic on the bits. This is why `R (>= 4.3.0)`.
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
  corpus. Use it as an oracle rather than inventing cases by hand. The
  design plans `gmp::as.bigz` as the arithmetic, parsing and formatting
  oracle, and a DuckDB/Arrow/Parquet round-trip matrix as the acceptance
  test; neither exists yet.
- **Run the int64 tests with and without bit64 attached.** Any
  difference means a method is missing on `zu_int64` (see Invariants).
  The bit64-attached run also covers mixed `zu_int64` ⊕ `integer64`
  dispatch.
- **Helpers live in `tests/testthat/helper-*.R`.** None yet.
- **Keep the suite inside the CRAN time budget.** No real tests yet.

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

This package calls `r-cmd-check.yml@v1` (from `R-CMD-check.yaml`) and
`coverage.yml@v1` (from `coverage.yaml`). `pkgdown.yaml` is the r-lib
example workflow, not a shared one.

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

The design plans to vendor the Arrow C Data Interface header (`abi.h`)
for `zu_arrow.c`. Nothing is vendored yet; record its licence, pinned
version and provenance here when it is.

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
