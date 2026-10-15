# zuint: roadmap

Status: draft 2026-10-15. Implements [design.md](design.md).
Target: v0.1.0, the first CRAN release.
Tracking: [v0.1.0 (#1)](https://github.com/pedrobtz/zuint/issues/1), with one
sub-issue per stage;
[CRAN-submission (#12)](https://github.com/pedrobtz/zuint/issues/12).

The design numbers its milestones v0.1 (core semantics), v0.2 (interop) and
v0.3 (vector toolkit, first CRAN release). This roadmap takes all three to
0.1.0: Stages 1 to 3 are the design's v0.1, Stages 4 and 5 its v0.2, and
Stages 6 and 7 its v0.3. The design's v0.4 (ALTREP views) and "later" items
wait under [After 0.1.0](#after-010).

Starting point: a `create-pkg.sh` scaffold. `DESCRIPTION` has placeholder
fields and `LinkingTo: zufast (>= 0.1.0.9000)` with `Remotes:
pedrobtz/zufast`; `src/zuint.c` is an empty stub; `R/zuint-package.R` holds
`@useDynLib`; the `R-CMD-check`, `coverage` and `pkgdown` workflows exist;
`CLAUDE.md` is written. No functionality yet.

## Stages

| Stage | Title | CI | Issue | Pull request | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | [Package identity](#stage-0--package-identity) | quick | [#2](https://github.com/pedrobtz/zuint/issues/2) | [#15](https://github.com/pedrobtz/zuint/pull/15) | 2026-10-16 |
| 1 | [Storage and construction](#stage-1--storage-and-construction) | full — first compiled code | [#3](https://github.com/pedrobtz/zuint/issues/3) | [#16](https://github.com/pedrobtz/zuint/pull/16) | 2026-10-16 |
| 2 | [Arithmetic and the promotion order](#stage-2--arithmetic-and-the-promotion-order) | quick | [#4](https://github.com/pedrobtz/zuint/issues/4) | | |
| 3 | [Parsing, formatting and bit operations](#stage-3--parsing-formatting-and-bit-operations) | quick | [#5](https://github.com/pedrobtz/zuint/issues/5) | | |
| 4 | [Arrow C Data Interface bridge](#stage-4--arrow-c-data-interface-bridge) | full — vendored header, external pointers and release callbacks | [#6](https://github.com/pedrobtz/zuint/issues/6) | | |
| 5 | [Engine bridges and the round-trip matrix](#stage-5--engine-bridges-and-the-round-trip-matrix) | quick | [#7](https://github.com/pedrobtz/zuint/issues/7) | | |
| 6 | [Sorting, hashing and reductions](#stage-6--sorting-hashing-and-reductions) | quick | [#8](https://github.com/pedrobtz/zuint/issues/8) | | |
| 7 | [vctrs, pillar and benchmarks](#stage-7--vctrs-pillar-and-benchmarks) | quick | [#9](https://github.com/pedrobtz/zuint/issues/9) | | |
| 8 | [Full CI](#stage-8--full-ci) | full | [#10](https://github.com/pedrobtz/zuint/issues/10) | | |
| 9 | [v0.1.0 readiness](#stage-9--v010-readiness) | full | [#11](https://github.com/pedrobtz/zuint/issues/11) | | |

## Stage 0 — Package identity

**Issue.** [#2](https://github.com/pedrobtz/zuint/issues/2), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `quick`. See the CI policy in `CLAUDE.md`.

**Goal.** The package has a real identity and the complete CI the later
stages rely on, and a pull request finishes its checks in under five minutes.

**Work.**
- `DESCRIPTION`: Title, Description, `Authors@R` (`cre`, `aut`, `cph`),
  `Depends: R (>= 4.3.0)` (design §4.1), `Version: 0.0.0.9000`, `URL` and
  `BugReports`, the `LinkingTo: zufast (>= 0.1.0.9000)` and `Remotes:` lines
  kept (design §2.1), `Suggests` limited to testthat and withr for now.
- `LICENSE` and `LICENSE.md` for MIT with the right copyright holder.
- Workflows from `pedrobtz/r-actions`, each pinned to a released tag:
  `gctorture.yml`, `valgrind.yml`, `cran-special.yml`, and `asan: true` on the
  `r-cmd-check.yml` call. `coverage.yml` pinned to a commit with the tag in a
  comment. All profile-switched like `R-CMD-check.yaml` already is.
- `tests/testthat/test-zuint.R` replaced by a smoke test that loads the
  namespace, so every workflow has something to run.
- Tune `quick-step` or `quick-containers` if the quick profile is over five
  minutes, and record what was tuned here.

**Exit criteria.**
- `R CMD check` passes on the quick r-actions profile with 0 errors, 0
  warnings, 0 notes.
- Every workflow in `.github/workflows/` runs on the pull request and is
  green; the slowest finishes in under five minutes.
- `DESCRIPTION` has no placeholder text and `usethis::use_build_ignore()`
  needs nothing further.

**Design.** §2.1, §4.1 of design.md.

**Deviations (2026-10-16).**
- `r-cmd-check.yml` has no `asan` input; ASan is the `asan: true` job of
  `sanitizers.yml`. That workflow moves to Stage 1: it fails when the
  installed object has no `__ubsan` symbols, and Stage 0's `init.c` has no
  code UBSan instruments, so it would fail without checking anything.
- `native-checks.yml` takes the whole r-actions example for packages with
  C: `lto.yml`, `rchk.yml` and `analyzers.yml` join the three the work list
  names, and `R-CMD-check.yaml` turns on `nosuggests` and `nold`, which
  Stage 8 needs. All of these add nothing to the quick profile but `lto`,
  `rchk` and `analyzers`, which run in minutes.
- `coverage.yml` sends its badge to `gh-pages` (`badge-branch`), because
  the `main` ruleset rejected the badge commit on every push.
- `src/init.c` with empty routine registration lands here rather than in
  Stage 1: without it R CMD check gives a "no registration" note.

## Stage 1 — Storage and construction

**Issue.** [#3](https://github.com/pedrobtz/zuint/issues/3), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `full — first compiled code: allocation, PROTECT and the
NaN-payload storage need gctorture at the sensitive step, valgrind and ASan
before every later stage builds on them`.

**Goal.** All four types exist on plain storage with the bit64-compatible
`int64`, can be built from R values and printed exactly, and behave as
vectors in base R. No arithmetic yet.

**Work.**
- `src/zu_wide.h`: the type traits `ZU_INT64`, `ZU_UINT64`, `ZU_INT128`,
  `ZU_UINT128` over `zufast/wide.h`; NA sentinels; the REALSXP and CPLXSXP
  storage accessors. `src/init.c` with registration.
- `sanitizers.yml` with `asan: true` in `native-checks.yml`, moved here
  from Stage 0 (see its deviations).
- A CI leg that compiles with `ZUF_NO_INT128` defined, so the portable
  fallback never rots (mechanism chosen here and recorded in `CLAUDE.md`).
- R side: classes `c("zu_int64", "integer64")`, `zu_uint64`, `zu_int128`,
  `zu_uint128`; constructors `int64()`, `uint64()`, `int128()`, `uint128()`
  from logical, integer, double (integral and in range, else NA plus a
  warning), decimal character (through `zuf_parse_*`), `integer64` (class
  swap only) and each other (lossless or NA plus a warning); `NA_int64_` and
  friends.
- Base vector protocol: `length`, `[`, `[[`, `[<-`, `[[<-`, `c`, `rep`,
  `rev`, `is.na`, `is.na<-`, `anyNA`, `as.character`, `format`, `print`,
  `as.double` (warning beyond 2⁵³), `as.integer` (NA plus a warning outside
  ±(2³¹ − 1)), `as.list`, `as.data.frame`, `str`, `summary`.
- `chooseOpsMethod()` methods returning TRUE for every `zu_*` class (design
  §4.1).
- `zu_storage()` and `zu_from_storage()` (design §4.3).
- Test helpers: `helper-oracle.R` (gmp, skipped when absent) and
  `helper-bit64.R` that runs the int64 tests with bit64 attached and
  detached (design §12, "bit64 parity").
- A `nm -u` guard in CI that fails on `printf`, `abort`, `exit` and system
  RNG symbols in the built objects (`CLAUDE.md`, Vendored native code).

**Exit criteria.**
- Every constructor round-trips through `as.character()` exactly for 0, ±1,
  2⁵³ ± 1, MIN + 1, MAX − 1 and MAX of each type, against the gmp oracle.
- `inherits(int64(1), "integer64")` is TRUE and `bit64::as.integer64()` of
  it is bit-identical; the bit64-attached and bit64-detached runs agree.
- The suite is green under `devtools::test(shuffle = TRUE)` and under the
  full r-actions profile, including gctorture at the sensitive step,
  valgrind, ASan and the `ZUF_NO_INT128` leg.
- `R CMD check` passes with 0 errors, 0 warnings, 0 notes.

**Design.** §4, §4.1, §4.3, §8 (decimal only), §10 of design.md.

**Deviations (2026-10-16).**
- `summary()` reports Min., Max. and the NA count; quartiles need sorting
  and come with Stage 6.
- `length<-` and `as.logical()` join the vector protocol: bit64 defines
  both for `integer64`, so without them `zu_int64` would fall through to
  bit64 when it is loaded.
- `as.double()` warns when a value rounds, not whenever it exceeds 2⁵³:
  2⁶⁰ converts exactly and silently.
- `c()` converts every argument to the type of the first. Stage 2 moves it
  to the common type of the promotion order.
- The `nm -u` guard is a test (`test-symbols.R`) rather than a workflow
  step, so every CI leg but Windows runs it on the object it built.
- The edge values are each type's true minimum (one above the NA
  sentinel) and the one above that, as well as MAX − 1 and MAX.

## Stage 2 — Arithmetic and the promotion order

**Issue.** [#4](https://github.com/pedrobtz/zuint/issues/4), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `quick`.

**Goal.** Exact arithmetic and comparison across the four types, with the
promotion order and the overflow policies the design specifies, and no
signed overflow reaching C.

**Work.**
- `src/zu_ops.h`: the NA and overflow-policy layer over zufast's checked and
  wrapping primitives (design §10). `src/zu_arith.c`: vectorised `Ops` with
  recycling, for each policy.
- Operators `+ - * %/% %% ^ abs sign` and unary minus under the R-like
  default (NA plus one warning per call); `checked_add()`, `checked_sub()`,
  `checked_mul()`, `checked_pow()`, `checked_neg()` (error); `wrapping_*`
  (modular). Division by zero per design §6. `/` returns double.
- Comparison `== != < <= > >=` exact across the promotion order, including
  against doubles (never errors).
- The promotion order and `zu_common_type()`; the `zuint.double` option;
  `c()` across types follows the same table.
- The decisions of 2026-10-15 (design §15): `integer ⊕ uint64 → uint64`,
  `integer ⊕ uint128 → uint128` with a negative integer handled by the
  policy, and the NA sentinel staying NA under `wrapping_`.
- Policy tests: each operation × each policy × each type pair, against the
  gmp oracle, with edge values and the NaN-pattern ranges.

**Exit criteria.**
- The policy matrix passes against gmp; every mixed-type case in design §5
  gives the listed type or the listed error class.
- `zu_int64 + integer64` and `integer64 + zu_int64` give exact results with
  no "incompatible methods" warning, with bit64 attached.
- UBSan (in the quick profile's clang container) reports nothing.
- `R CMD check` passes with 0 errors, 0 warnings, 0 notes.

**Design.** §5, §6, §10 of design.md.

## Stage 3 — Parsing, formatting and bit operations

**Issue.** [#5](https://github.com/pedrobtz/zuint/issues/5), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `quick`.

**Goal.** Character input and output are complete and exact, and the bit
operations exist for every type.

**Work.**
- `src/zu_parse.c`: decimal with sign, `0x` hex and `0b` binary prefixes,
  `_` digit separators, surrounding whitespace, `NA` and `""` as NA, overflow
  detection; one implementation for all widths. Document that exponents are
  not accepted.
- `src/zu_format.c`: exact decimal (128-bit via `zuf_write_*`),
  `format_hex()`, `format_bin()`; `format()` arguments `width` and
  `big.mark`; `print()` for long vectors.
- Bit operations `bit_and()`, `bit_or()`, `bit_xor()`, `bit_not()`,
  `shift_left()`, `shift_right()`, `popcount()`, `clz()`, `ctz()`; shifts
  beyond the width give NA.
- Snapshot tests for printed output; parsing and formatting property tests
  against gmp.

**Exit criteria.**
- `x == int64(format(x))` for random fills of every type, including hex and
  binary round trips, against gmp.
- Every malformed input in the test corpus gives NA plus a warning, never a
  wrong value.
- `R CMD check` passes with 0 errors, 0 warnings, 0 notes.

**Design.** §6 (bit operations), §8 of design.md.

## Stage 4 — Arrow C Data Interface bridge

**Issue.** [#6](https://github.com/pedrobtz/zuint/issues/6), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `full — a vendored header (`abi.h`), external pointers that own
engine buffers, and Arrow release callbacks: sanitizers, valgrind and
gctorture at the sensitive step, before Stage 5 builds the engine bridges on
it`.

**Goal.** zuint reads and writes `ArrowArray` and `ArrowSchema` structs for
every type in design §0 without any R package in between.

**Work.**
- Vendor `abi.h` from a stable Arrow release under `src/vendor/arrow/` with
  `LICENSE`, `NOTICE`, `PROVENANCE` (tag, commit, checksum, update
  procedure), `inst/COPYRIGHTS`, the `DESCRIPTION` declaration and the
  vendor-verify script, as `CLAUDE.md` requires.
- `src/zu_arrow.c`: import of `l`, `L`, `d:38,0` (bits as-is) and the
  `arrow.opaque` hugeint/uhugeint extension; export of `l`, `L` and the
  extension by default, `decimal = TRUE` for `d:38,0` with a digit check;
  validity bitmap to and from NA sentinels; sentinel values imported as NA
  with a warning; copies every buffer (zero-copy waits for ALTREP).
- R surface: `zu_from_arrow(array, schema)`, `zu_to_arrow(x)` on external
  pointers, `zu_sentinel_check()`.
- nanoarrow methods registered lazily on `packageEvent("nanoarrow",
  "onLoad")`: `convert_array()` targets `int64()`, `uint64()`, `int128()`,
  `uint128()` and `as_nanoarrow_array()` for zuint vectors. nanoarrow joins
  `Suggests`.
- The CI `nm -u` guard extended to the vendored object.

**Exit criteria.**
- For every type, `zu_from_arrow(zu_to_arrow(x))` is identical to `x`, with
  nulls, for the design §12 value set.
- Importing DuckDB's default `decimal128(38,0)` HUGEINT export of
  HUGEINT max gives int128 max; importing the `arrow.opaque` export of
  UHUGEINT max gives uint128 max.
- The release callback runs exactly once per imported array under
  gctorture; valgrind and ASan are clean.
- `tools/verify-vendor` passes; `R CMD check` passes with 0 errors, 0
  warnings, 0 notes, including the `nosuggests` leg of the full profile.

**Design.** §9.1, §10 of design.md; `CLAUDE.md`, Vendored native code.

## Stage 5 — Engine bridges and the round-trip matrix

**Issue.** [#7](https://github.com/pedrobtz/zuint/issues/7), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `quick`.

**Goal.** The headline feature is demonstrable: DuckDB, Arrow and Parquet
round trips preserve schema and values for every type, in CI and in the
README.

**Work.**
- bit64 bridge: `as_integer64()` and `int64()` on an `integer64` swap only
  the class.
- DuckDB: `zu_duckdb_query(con, sql)` sets `arrow_lossless_conversion` on
  the connection, fetches through DuckDB's Arrow export and returns a data
  frame with zuint columns; write-back through `duckdb_register_arrow()`.
- arrow: `as_arrow_array()` and `infer_type()` methods, registered lazily;
  Parquet read and write through arrow.
- The round-trip matrix test (design §12): each engine type × each path,
  schema identical and every value identical, for 0, ±1, 2⁵³ ± 1, MIN, MAX,
  MIN + 1, MAX − 1, nulls and random fills. Skipped when duckdb or arrow is
  absent; always run in CI. bit64, arrow and duckdb join `Suggests`.
- README: the before/after table from design §0 and a worked round trip
  (`pkg-readme` skill).

**Exit criteria.**
- The round-trip matrix passes for every row of the design §0 table that
  0.1.0 covers, on CI's current duckdb and arrow.
- A UBIGINT column of 2⁶⁴ − 2 reads as that value, and a UHUGEINT column of
  2¹²⁸ − 2 reads as that value, through `zu_duckdb_query()`.
- `R CMD check` passes with 0 errors, 0 warnings, 0 notes.

**Design.** §0, §9.2, §12 of design.md.

## Stage 6 — Sorting, hashing and reductions

**Issue.** [#8](https://github.com/pedrobtz/zuint/issues/8), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `quick`.

**Goal.** The vector toolkit is complete: ordering, set operations and
summaries are exact and type-correct for every type.

**Work.**
- `src/zu_sort.c`: stable LSD radix sort on the unsigned-key transform, with
  constant-byte passes skipped; `sort`, `order`, `rank`, `xtfrm` (integer
  ranks).
- `src/zu_hash.c`: open-addressing hash on the exact bits; `unique`,
  `duplicated`, `match`, `%in%`, `table`.
- `src/zu_reduce.c`: `sum` (type stable, 128-bit accumulator, NA plus a
  warning on overflow; design §7), `cumsum`, `cumprod`, `mean` and `median`
  as doubles, `min`, `max`, `range` with `na.rm`, `diff`, `seq_zu()`.
- Property tests against gmp and against base R on values below 2⁵³.

**Exit criteria.**
- `order()` on a data frame with an int64 key and a second key is exact
  beyond 2⁵³; `sort()` is stable and NA placement follows `na.last`.
- `match()` and `unique()` agree with gmp-based references on random fills
  with collisions in the low and high words.
- `sum(int64(c(2^62, 2^62)))` is NA with a warning,
  `sum(int128(c(2^62, 2^62)))` is 2⁶³, and `mean(int64(1:2))` is `1.5`.
- `R CMD check` passes with 0 errors, 0 warnings, 0 notes.

**Design.** §7, §10 of design.md.

## Stage 7 — vctrs, pillar and benchmarks

**Issue.** [#9](https://github.com/pedrobtz/zuint/issues/9), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `quick`.

**Goal.** zuint vectors work in tibbles, dplyr and data.table, and the
performance claim against bit64 has evidence.

**Work.**
- vctrs: `vec_ptype2`, `vec_cast` from the design §5 table, `vec_proxy`
  returning the payload, registered lazily; pillar `pillar_shaft` and
  `type_sum`. vctrs and pillar join `Suggests`.
- data.table: tests that int64 works natively and that the other types are
  documented as needing `as.character()` or `as_integer64()` for keyed joins.
- `zu_ifelse()` and `zu_vapply()` helpers for the class-stripping traps.
- Benchmarks against bit64 for `+`, `sum`, `sort`, `match` and `unique` at
  10⁶ to 10⁸ elements, as a script under `inst/bench/` with results in
  the README.
- `vignettes/zuint.Rmd`: the type table, the promotion order, the policies
  and the engine round trip.

**Exit criteria.**
- `dplyr::arrange()`, `group_by() |> summarise(sum())`, `bind_rows()` and
  `tibble` printing work for every type, with tests that skip when the
  packages are absent.
- The benchmark script runs and the README reports int64 no slower than
  bit64 on each of the five operations.
- `R CMD check` passes with 0 errors, 0 warnings, 0 notes.

**Design.** §4.1 (helpers), §9.2 (vctrs, data.table), §12 (benchmarks) of
design.md.

## Stage 8 — Full CI

**Issue.** [#10](https://github.com/pedrobtz/zuint/issues/10), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `full`.

**Goal.** No new features. The full r-actions profile is green on the
default branch's code.

**Work.**
- Run the full profile with the `full-ci` label: gctorture at the sensitive
  step, valgrind, ASan on both containers, every platform leg, `nosuggests`,
  `nold`, cran-special (`rcnst`, `rlibro`, `vnu`), and the `ZUF_NO_INT128`
  leg.
- Fix everything it finds, including failures recorded as comments on this
  stage's issue by the merges of Stages 2 to 7.

**Exit criteria.**
- A full-profile run is green on the pull request and on its merge commit.

**Design.** §12 of design.md.

## Stage 9 — v0.1.0 readiness

**Issue.** [#11](https://github.com/pedrobtz/zuint/issues/11), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zuint/issues/1).

**CI.** `full`.

**Goal.** Only the submission itself is left.

**Work.**
- zufast 0.1.1 on CRAN: raise `LinkingTo` to `zufast (>= 0.1.1)` and delete
  `Remotes:` in the same commit (design §2.1).
- `Version: 0.1.0` and the matching `NEWS.md` heading.
- `cran-comments.md` listing the r-actions CI legs as test environments.
- The `pkg-cran-review` skill run, every finding resolved;
  `urlchecker::url_check()` and `spelling::spell_check_package()` clean.
- `CLAUDE.md` Architecture and Invariants sections brought up to date with
  what the stages established.

**Exit criteria.**
- A full-profile r-actions run is green on the release commit.
- `R CMD check --as-cran` shows only the "New submission" note.
- `DESCRIPTION` has no `Remotes:` field and depends on a released zufast.

**Design.** §2.1, §13 of design.md; `CLAUDE.md`, Releasing to CRAN.

## After 0.1.0

- **ALTREP views** for uint64, int128 and uint128 (design §4.2, §13 v0.4):
  graceful degradation of class-stripped values, zero-copy wrapping of
  null-free Arrow buffers including the int64 bits-view wrapper, exact
  `Extract_subset`, `Is_sorted` and `No_NA` flags, and the
  `zuint.serialize` modes. Deferred because the semantics must be right
  first and the plain storage already round-trips exactly.
- **Upstream adoption** (design §9.3): approach the duckdb and
  nanoarrow/arrow maintainers once the round-trip matrix and benchmarks are
  public.
- **Schema-fidelity classes** for uint32 and the small integer types (design
  §0, §3), pending the open question on where they live.
- **The `decimal` bridge** for scale > 0 decimals, implemented in `decimal`.
- **`saturating_*` operations, `mean_exact()` and `quantile()`** (design §6,
  §7, §13): cheap, but not needed for the engine round trip.
- A blog post with the before/after table and benchmarks, at release.

## Open questions

- **zufast 0.1.1 on CRAN**: required before Stage 9 can close.

Resolved 2026-10-15, recorded in design §15: the `integer ⊕ unsigned`
promotion rule and the wrapping NA rule (Stage 2), and the type-stable
`sum()` (Stage 6).
