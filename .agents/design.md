# RFC 0009: `zuint`, lossless Arrow and DuckDB integers in R

Adopted from [RFC 0009](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0009-zuint-wide-integers.md)
on 2026-10-15. From here on this file is authoritative; the RFC is history.

Wide integer vectors for R (`int64`, `uint64`, `int128`, `uint128`) matching the
integer types of Arrow and DuckDB. They share one C core and one promotion
lattice, and convert exactly to and from `integer64`, Arrow and DuckDB.
And fixed-point `DECIMAL(p, s)` values on the same 128-bit core (§2.2).

- **Status:** Adopted 2026-10-15. Revised on 2026-10-14 alongside RFC 0035
  (`zutempo`): the 128-bit type, its checked and wrapping arithmetic, floor
  division and portable fallback come from `zufast`'s `wide.h` header
  (zufast 0.1.1, merged in `pedrobtz/zufast#40`) instead of being written
  here, so that zuint and `zutempo` share one implementation (§10).
  Reviewed on 2026-10-15: §0.1 (relation to bit64) added, the promotion
  table and the ALTREP slot layout corrected, and every engine behaviour
  previously marked *(verify)* checked against duckdb 1.5.4.1, arrow 24.0.0,
  nanoarrow 0.9.0 and bit64 4.8.2 on R 4.6.1 (§9, §15).
- **Scope change, 2026-11-20** ([#88](https://github.com/pedrobtz/zuint/issues/88)):
  zuint takes on fixed-point decimals and an R-free C table (§2.2). Until
  then decimals were a non-goal and the `decimal` package was to depend on
  zuint; both are reversed. On 2026-11-25 the maintainer moved the work
  into 0.1.0, as Stages 9.1 and 9.2 of the roadmap.
- **Date:** 2026-10-09; revised 2026-10-14; reviewed 2026-10-15; scope
  changed 2026-11-20.
- **Packages:** `zuint` (not yet created; name availability unchecked);
  `LinkingTo: zufast (>= 0.1.1)`, build time only;
  optional bridges to `bit64`, `nanoarrow`, `arrow`, `duckdb` and `vctrs`
  through Suggests.
- **Source:** design discussion of 2026-10-09; the duckdb R reference
  manual (`bigint = "numeric" | "integer64"`, default `"numeric"`); Dirk
  Eddelbuettel on r-devel, January 2025, on native 64-bit integers; the
  bit64 `integer64` representation; the probes of 2026-10-15 recorded in
  §0.1 and §9.

## 0. Positioning

zuint exists so that **every integer type Arrow and DuckDB produce survives the
trip into R and back, exactly**. The type list comes from those engines' type
systems, not from a wish list:

| Engine type | Arrow | DuckDB | What R gets today | zuint |
| --- | --- | --- | --- | --- |
| signed 64 | `int64` | `BIGINT` | duckdb: double by default (`bigint = "numeric"`), `integer64` opt-in. arrow: integer when every value fits, else `integer64` | `int64` (integer64-compatible) |
| unsigned 64 | `uint64` | `UBIGINT` | double (rounded beyond 2⁵³). duckdb with `bigint = "integer64"`: `integer64` with the bits reinterpreted, so 2⁶⁴ − 1 reads as −1. nanoarrow to `integer64`: clamped to 2⁶³ − 1 | `uint64` |
| signed 128 | — (DuckDB exports it as `decimal128(38, 0)` by default, or as the `arrow.opaque` extension over `fixed_size_binary(16)` with `arrow_lossless_conversion`) | `HUGEINT` | double | `int128` |
| unsigned 128 | — (as above; the `decimal128` export reads values ≥ 2¹²⁷ as negative) | `UHUGEINT` | double | `uint128` |
| unsigned 32 | `uint32` | `UINTEGER` | double (exact, but the type is lost on write-back) | later: schema-fidelity class |
| small ints | `int8/16`, `uint8/16` | `TINYINT`… | integer (type lost on write-back) | later: schema-fidelity classes |
| decimals | `decimal32/64/128/256` | `DECIMAL(p, s)` | double | `decimal128`, fixed-point on `int128`, p ≤ 38 (§2.2); `decimal256` stays out |

The pitch: **zuint covers every integer Arrow/DuckDB type R can't
represent, and DuckDB's fixed-point `DECIMAL` too.** Changed
2026-11-20 (#88): the pitch was "zuint + decimal", with the decimals in
the companion package.

Success criteria:

1. A DuckDB/Arrow → R → DuckDB/Arrow round trip preserves both the schema and
   every value, for every type in the table. The one documented exception is
   a value equal to the type's NA sentinel (§4, §9.1).
2. One-line adoption: `zuarrow::arrow_to_r()` and `zuarrow::arrow_read()`
   return zuint columns once zuint is loaded, and so does a DuckDB result
   through `zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))` with
   `arrow_lossless_conversion` on. Changed 2026-11-25 (Stage 9): the Arrow
   surface is zuarrow's, and zuint registers with it (review X1, X2);
   zuarrow's `arrow_duckdb()` was dropped on 2026-11-04, so the DuckDB line
   is two calls.
3. Not slower than bit64 on int64 operations.
4. Code written for `integer64` runs unchanged on `int64`, with the same
   answers wherever bit64's answer is exact (§0.1).

### 0.1 Relation to bit64

bit64 gave R its 64-bit integers and defined the `integer64` layout that
data.table, arrow, duckdb and the database drivers all read. zuint builds on
that work rather than replacing it: `int64` keeps bit64's layout and class, so
every existing consumer keeps working, both packages can be loaded together,
and zuint never changes what bit64 does with its own objects (§4.1).

Within that layout, zuint's `int64` is a second implementation with stricter
semantics and more choice. The rules are:

- **Exact or explicit.** A result is either exact or the operation says so,
  with an NA and a warning, or an error. No operation silently truncates,
  rounds or clamps.
- **Overflow is a policy, not a fixed behaviour.** The default is R's (NA plus
  a warning); `checked_*`, `wrapping_*` and `saturating_*` variants are
  explicit (§6).
- **Doubles never enter arithmetic unnoticed.** An integral double in range is
  converted exactly; anything else is an error by default (§5).
- **Summaries return the mathematically right type.** `mean` and `median` are
  doubles, as they are for R integers; exact sums have `int128` to grow into.
- **Two wider types** for what int64 cannot hold, and schema-exact engine
  bridges (§9), so the same semantics cover `uint64`, `int128` and `uint128`.

The differences, as measured on bit64 4.8.2 (R 4.6.1, 2026-10-15). They are
design choices in bit64, not bugs to report; zuint simply chooses
differently:

| Expression | bit64 4.8.2 | zuint `int64` |
| --- | --- | --- |
| `as.integer64(1.5)` / `int64(1.5)` | 1, silently | NA with a warning |
| `x + 0.5`, `x * 1.5` for `x = 3` | 3 and 5 (the double is converted before the operation) | error; `zuint.double = "allow"` gives a double with a warning |
| `x == 1.5` for `x = 1` | TRUE | FALSE: comparison with a double is exact and never errors |
| `as.integer64(3)^40L` | 9223372036854775807, no warning (clamped) | NA with a warning; `checked_pow()` errors, `wrapping_pow()` wraps |
| `mean(c(1, 2))` | 1, of class `integer64` (truncated) | 1.5, double |
| `median(c(1, 2))` | 2, of class `integer64` | 1.5, double |
| `xtfrm(x)` | the raw bits read as doubles, so `order()` on several keys collapses ties beyond 2⁵³ | ranks, exact |
| `min(integer64())` | 2⁶³ − 1 with a warning | `Inf` with a warning, as base R |
| `as.integer64("1e3")` | NA with a warning | NA with a warning (same); hex, binary and `_` separators parse (§8) |

Shared costs of the layout, the same in both packages and documented for
both: class-stripping code such as `c(1, x)`, `ifelse()` and `unclass()`
reads the bits as doubles, and `serialize(ascii = TRUE)` corrupts values
because NaN payloads do not survive text (§4.1).

## 1. Problem

R has 32-bit integers and IEEE doubles. Doubles are exact only up to 2⁵³,
about 0.1% of the int64 range (2⁵⁴ of 2⁶⁴ values). The de facto 64-bit type,
`bit64::integer64`, works but leaves gaps:

- No **unsigned 64-bit**. Hashes, IDs, Arrow/Parquet `UINT64` and DuckDB
  `UBIGINT` arrive as doubles (lossy) or as `integer64` (bits reinterpreted,
  so 2⁶⁴ − 1 reads as −1).
- No **128-bit** type. DuckDB `HUGEINT` becomes a double; exact sums of int64
  columns can't be represented.
- **Overflow** gives NA plus a warning only; there is no wrapping (hash/checksum
  arithmetic) or erroring mode, and `^` clamps to the maximum.
- **Mixing with doubles** converts the double first, so `x + 0.5` is `x` and
  `x == 1.5` can be TRUE.
- **Summaries keep the integer type**: `mean` truncates, `median` picks an
  element.
- **Class-unaware code** (`unclass`, `ifelse`, `vapply`, naive C) reads the raw
  bits as doubles: `-1` is a NaN, `NA` is `-0.0`, large IDs become `4e-308`.

R Core is unlikely to add a native 64-bit type soon: SEXPTYPE header bits are
scarce, and the linear coercion hierarchy doesn't accommodate int64
(Eddelbuettel, r-devel, Jan 2025). A package is the realistic path.

## 2. Goals

0. **Schema-exact round trips** with Arrow and DuckDB for every integer type in
   §0 (values and types survive read → compute → write), through one Arrow C
   Data Interface bridge.
1. Four types — `int64`, `uint64`, `int128`, `uint128` — with identical
   semantics and API.
2. Exact arithmetic, comparison, reductions, sorting, hashing, parsing and
   formatting in C.
3. A single, lossless promotion lattice across the four types and R's
   `logical`/`integer`.
4. Explicit overflow policy: R-like default plus `checked_*` and `wrapping_*`
   variants.
5. Zero-copy interop with `integer64` (bit64 layout), and exact bridges to
   DuckDB and Arrow.
6. Graceful degradation: misused uint64/int128 values look like approximate
   numbers, never garbage.
7. No dependencies outside the zu-* family (§2.1). vctrs/pillar integration
   is registered lazily.
8. Fixed-point decimals on `int128` and an R-free C table (§2.2).

### 2.1 Dependency policy

Decided 2026-10-15: nothing outside the zu-* family is required to install,
load or use zuint.

- **`Depends`, `Imports`, `LinkingTo`: zu-* packages only.** Today that is
  `LinkingTo: zufast`, build time only. R itself is the only other entry
  (`R (>= 4.3.0)`, §4.1).
- **Development tracks zufast's dev version** (decided 2026-10-15): until
  zufast 0.1.1 is on CRAN, `DESCRIPTION` says `LinkingTo: zufast
  (>= 0.1.0.9000)` with `Remotes: pedrobtz/zufast`, so CI and contributors
  build against GitHub main. When zufast 0.1.1 is released, raise the
  constraint to `>= 0.1.1` and delete `Remotes:` in the same commit; CRAN
  rejects a `Remotes:` field, so this is a `Pre-flight` entry criterion.
- **`Suggests` is the only place another package may appear.** Tests may use
  anything there (testthat, withr, gmp as the oracle), skipped when absent.
  Outside the tests, a Suggests
  package appears only in lazily registered methods on its own generics
  (bit64, vctrs, pillar) and in the zuarrow registrations (§9), and the core
  never calls into one.
- **The Arrow bridge is zuarrow's** (2026-11-25, Stage 9; review X1, X2(b)).
  zuarrow is a Suggests. When it loads, zuint registers `to` and `from`
  handlers with `zuarrow::arrow_register()`. The handlers are zuint's C
  kernels over the vendored `abi.h` structs (§9.1); every R-level Arrow and
  engine function is zuarrow's.
- **The engines are recorded oracles, not Suggests** (decided 2026-11-27).
  DuckDB, DBI, arrow and nanoarrow answered the decimal types and the
  round-trip matrix live; dplyr, tibble and data.table carried interop
  tests. All seven were Suggests, so every check, CRAN's included,
  installed them, and duckdb and arrow take half an hour to build from
  source. The tests now replay the engines' answers from a committed
  fixture, keyed by what each answer depends on, including the
  fingerprint of what zuint writes; `tools/oracle/` records it and CI's
  oracle job records it afresh and compares (§12). The dplyr tests became
  the vctrs calls dplyr makes, and dplyr and data.table themselves run
  only in that job.
- **The family no longer relies on `decimal`** (2026-11-20, #88). It was
  to depend on zuint and hold the decimal bridge. `decimal` imports
  rlang, vctrs and withr and has no R-free C table, so zuint takes the
  fixed-point decimals itself (§2.2). `decimal` stays as it is for its own
  users; neither package depends on the other.

### 2.2 Fixed-point decimals and the C table

Decided 2026-11-20 by the maintainer
([#88](https://github.com/pedrobtz/zuint/issues/88)). zugodb's engine
(libzugodb) refuses `DECIMAL(p, s)` (libzugodb#26), its largest block of
refused cases in DuckDB's tests: 2,183 cases in `test/sql/types/decimal`,
181 passing. No family package fits. `decimal` has no R-free C table, and
the small C decimal libraries (mpdecimal, decNumber, Intel BID) are decimal
*floating* point. DuckDB's `DECIMAL` is fixed-point: an integer of at most
128 bits scaled by 10^s, with p ≤ 38. zuint already has that integer, its
checked arithmetic (`zufast/wide.h`), parsing and formatting, so
fixed-point is a small layer on top.

- **The core, in C, R-free.** A value is an `int128` coefficient with a
  precision p (1 to 38) and a scale s (0 to p), as DuckDB stores it:
  - rescale up by 10^k with an overflow check, and down by 10^k rounding
    half away from zero (DuckDB's rule for casts, `ROUND` and narrowing);
  - a check that a coefficient fits p digits;
  - strict parsing and formatting with a decimal point: what DuckDB v2.0.0
    refuses is a status, never a guess;
  - conversion to and from double with DuckDB's rounding;
  - checked add, subtract, multiply and compare, exact before any rescale.

  Overflow, invalid input and a result that does not fit are each a
  status. No function calls R.

  DuckDB's behaviour, settled 2026-11-25 (Stage 9.1) from its source at
  commit d54cbbe3df (2.0.0) and checked against its casts:
  - **Text.** Surrounding whitespace (space, `\t`, `\n`, `\v`, `\f`,
    `\r`), a `+` or `-`, `_` between two digits, `1.` and `.5`, and an
    exponent (`e` or `E`, a sign, an `int16`, and a point DuckDB lets end
    it: `1e2.`). No hex, binary, `NaN` or `inf`. Digits past the scale
    round half away from zero, and `-0.001` at scale 2 is `0.00`. Which
    texts are accepted is decided by a port of DuckDB's own state machine
    (`inst/COPYRIGHTS`), because its exponent handling refuses values
    that fit: `12345e-2` as DECIMAL(5,2) is refused, as DuckDB does
    ([duckdb#29189](https://github.com/duckdb/duckdb/issues/29189)). The
    value is then computed exactly. zuint differs from DuckDB 2.0.0 in
    two places, both DuckDB bugs:
    - it reads `1.234e4` as DECIMAL(4,0) 12340, a value wider than its
      type; zuint refuses it. Fixed on DuckDB's main by
      [duckdb#26961](https://github.com/duckdb/duckdb/pull/26961), not
      yet released;
    - with an exponent it keeps only 4, 9, 18 or 38 digits, by precision,
      leading zeros after the point included, so `0.0000000001234e10` as
      DECIMAL(5,2) is 0.00, where zuint gives 1.23
      ([duckdb#29395](https://github.com/duckdb/duckdb/issues/29395)).
      At precision 19 and over the same cut at 38 digits rounds the last
      one wrong: `-334546177624847.3059360487613332279271164e16` as
      DECIMAL(38,7) ends `.2792711`, where the exact value ends
      `.27927116` and zuint gives `.2792712` (2026-11-26, #140).

    A refused text is `ZUINT_ERR_INVALID` when it is outside the grammar
    and `ZUINT_ERR_OVERFLOW` when it is inside it.
  - **Text out.** `1.50`, `-0.05`, and no integer part when p == s:
    `.50`, `-.05`.
  - **To double.** c / 10^s correctly rounded, ties to even, at every
    precision and scale. DuckDB 2.0.0 added the two 64-bit words as
    doubles at scale 0 with p > 18, one unit in the last place off for
    some values; 2.0.1 rounds correctly, and zuint follows 2.0.1
    (2026-11-26: CI's 2.0.1 disagreed with the 2.0.0 formula). The
    function keeps the precision argument, which it validates.
  - **From double.** `round(x * 1e<s>)` in double arithmetic, half away
    from zero, refused at or beyond the double `1e<p>`; so 2.675 is 2.68
    and 1.005 is 1.00 at scale 2. NaN and infinity are invalid.
  - **Rescale.** Half away from zero, then the new precision is checked.
  - **Compare** is exact across scales. DuckDB casts both sides to a
    common type first and can fail with a conversion error
    ([duckdb#29396](https://github.com/duckdb/duckdb/issues/29396)), so
    it is not the oracle there.
- **An R-free C table, `zuint_api_v1`,** in a header that includes no R
  header, with the operations above and the integer ones the engine may
  use. The `R_GetCCallable` resolver lives in a second header, as
  zukomp#132 settled. The header states the thread contract (no R API; a
  status, never an unwind; distinct states on distinct threads) and the
  append rule (the struct size grows, the version does not).
  Settled 2026-11-25, following zukomp's pair:
  - `inst/include/zuint.h` is C99 and includes only `<stddef.h>` and
    `<stdint.h>`, not zufast: a consumer that is handed the pointer
    (libzugodb, built without R) needs this header alone. A 128-bit value
    crosses it as `zuint_i128`, two `uint64_t` words, low word first,
    two's complement, the layout of DuckDB's `hugeint_t`.
  - `inst/include/zuint-r.h` includes it and R's headers, and defines
    `zuint_api()`, which resolves the registered callable
    `zuint_get_api(uint32_t version)` on R's main thread, caches it, and
    returns NULL for another ABI version or a smaller table.
  - Every member returns an `int` status: `ZUINT_OK`, or a negative
    `ZUINT_ERR_*` (overflow, invalid text, a precision or scale out of
    range, a buffer too small). Results go through out-pointers, which are
    left alone on an error. `strerror()` names each status.
  - A consumer takes `LinkingTo: zuint` for the headers and `Imports:
    zuint` with an `importFrom()` to load the DLL, as zukomp documents.
- **An R vector class, `decimal128`,** on the same core, so zugodb returns
  and writes a `DECIMAL(p, s)` column without losing a digit. Settled
  2026-11-25 by the maintainer, after DuckDB, since a DuckDB column is
  what it carries:
  - one precision and one scale per vector, like a column. The payload is
    `int128`'s (a CPLXSXP whose bits are the coefficient, §4), with
    integer attributes `precision` and `scale`, class
    `c("zu_decimal128", "zu_decimal")`. `NA` is `int128`'s sentinel, which
    no coefficient of 38 digits or fewer can equal;
  - `decimal128(x, precision = 38L, scale = 0L)` builds it from text (the
    core's parser), the integer types and zuint vectors (exact, or `NA`
    with a `zuint_cast_warning` when a value does not fit p digits) and
    doubles (the core's DuckDB rounding: the constructor is the explicit
    request §5 asks for). With a `decimal128` and only one of
    `precision` and `scale`, the other stays x's (2026-11-26, #124);
  - `+`, `-` and `*` give DuckDB 2.0.1's result types, checked against
    its `typeof()` in the tests (probed 2026-11-26): `+` and `-` take
    the larger scale s and the precision max(p1 - s1, p2 - s2) + s + 1;
    `*` takes p1 + p2 and s1 + s2, except that two operands of at most
    18 digits multiply in 64 bits and stop at 18 when the scale is under
    18; every precision stops at 38, and a product needing a scale over
    38 is a `zuint_incompatible_error`, where DuckDB refuses to bind. A
    result that does not fit is `NA` with a `zuint_overflow_warning`
    (§6), where DuckDB raises. Comparison is exact across scales, and
    with every operand as §5 has it for the integer types: a double of
    any value (whole parts first, then the fraction from the double's
    exact decimal expansion), and an integer beyond 38 digits by its
    sign (2026-11-26, #113; it had sent fractions to `zuint.double`).
    `/`, `%%`, `%/%`, `^`, `prod()`, `cumprod()`, `mean()`, `median()`,
    `signif()` and the other `Math` functions return doubles; DuckDB's
    `%` stays a decimal, but R's `%%` and DuckDB's disagree on signs, so
    zuint does not pretend to be either. `abs()`, unary `-`, `cummax()`
    and `cummin()` keep the type.
  - The rounding functions keep a decimal type, DuckDB 2.0.1's, probed
    (2026-11-26, #127; they had returned doubles): `round(x, d)` is
    `DECIMAL(p, d)` for 0 <= d < s, half away from zero, and x itself
    for d >= s; a negative d gives `DECIMAL(p, 0)`, or at scale 0
    `DECIMAL(p + 1, 0)` (at most 38) while -d <= p, since `round(99,
    -2)` is 100. `floor()`, `ceiling()` and `trunc()` are
    `DECIMAL(p, 0)`, and `cumsum()` is `DECIMAL(38, s)`, DuckDB's
    running `sum()`; a running sum past 38 digits is `NA` from there on,
    with a `zuint_overflow_warning`, as base `cumsum()` does after an
    overflow.
  - Integer operands take DuckDB's implicit casts: `integer` and
    `logical` as `DECIMAL(10, 0)`, `int64` as `DECIMAL(19, 0)`, `uint64`
    as `DECIMAL(20, 0)`, and `int128` and `uint128` as
    `DECIMAL(38, 0)`, a value past 38 digits being `NA` with a
    `zuint_cast_warning`. (DuckDB has the `UHUGEINT` cast this section
    first said it lacked.) A whole double is an integer operand, typed
    as DuckDB types an integer literal: `DECIMAL(10, 0)` when every value
    fits an R integer, `DECIMAL(19, 0)` when every value fits BIGINT, else
    `DECIMAL(38, 0)` (2026-11-26, #113); any other double follows
    `zuint.double`, as elsewhere. With bit64 attached, an `integer64` on
    the left would run bit64's method, which converts the decimal with
    `as.integer64()`; that method is a `zuint_incompatible_error` for a
    decimal, so the answer is never a silent `NA` (2026-11-26, #115).
  - `c()` and vctrs combine in DuckDB's common type: the most integer
    digits e and the largest scale s, with the scale cut to 38 - e when
    e + s passes 38; with an integer type the decimal's scale stays and
    the precision stops at 38. Where DuckDB rounds a value into a cut
    scale, zuint gives `NA` with a `zuint_cast_warning`: `c()` is not a
    request to round. `x[i] <- value` and `x[[i]] <- value` cast the
    value to x's type by the same rule, and a double that is not whole
    follows `zuint.double` (2026-11-26, #109; they had rounded). Text is
    read as `decimal128()` reads it, rounding, in all three. vctrs types
    prototypes, not values, so it counts a double as `DECIMAL(10, 0)`,
    as `c()` counts one of int32 values; a larger double is then a lossy
    cast, not a wider type (2026-11-26, #129). `decimal128(x, p, s)` is
    the request to round, and rescales half away from zero as DuckDB's
    `CAST` does. Conversion to the integer types is exact or `NA` with a
    warning, where DuckDB's `CAST` rounds.
  - `print()` and `format()` show every digit of the scale, under a
    `<decimal128(p, s)[n]>` header; `as.double()` is DuckDB's cast and
    does not warn, since almost every fraction rounds. Sorting, hashing,
    `sum()` (as `DECIMAL(38, s)`), `min()`, `max()` and `range()` reuse
    the `int128` code on the coefficients, which share one scale within
    a vector; `mean()` is within an ulp or two of DuckDB's `avg()`,
    whose last bit depends on the platform's `long double`: it is the
    exact sum ÷ (n · 10^s), rounded once (2026-11-27, #148). The
    accessors are `decimal_precision()` and `decimal_scale()`, since
    base `scale()` is already a generic. `match()`, `%in%` and `table()`
    compare values, not text at the vector's scale: `mtfrm()` writes a
    decimal without trailing fractional zeros, so 1.0, 1.00 and the
    integer 1 meet (2026-11-26, #108); `zu_match()`, `zu_ifelse()` and
    `zu_vapply()` take decimals (#126).
  - The Arrow mapping waits (§15): review X5 registered no `d:*` key in
    zuarrow, and that decision is zuarrow's as much as zuint's.
- **Tests:** the General Decimal Arithmetic suite (Cowlishaw's `.decTest`
  files from CPython's `Lib/test/decimaltestdata/`, at a pinned tag) for
  the fixed-point cases, run by a C test binary with no R; random
  differential tests against Python's `decimal` at 100 digits, weighted to
  `10^p - 1`, `10^p`, `±(2^127 - 1)` and every halfway point; precision 37,
  38 and 39 and scale p - 1, p and p + 1; several threads through the table
  against a single-threaded run; and the `ZUF_NO_INT128` build.
- **Order:** in 0.1.0, as roadmap Stages 9.1 (the C core and table) and
  9.2 (the R class). #88 first placed it after zuint's first CRAN release;
  the maintainer moved it on 2026-11-25, because Stage 10 waits on
  zufast's release anyway and the first release then fixes the table's
  layout. zugodb 0.1.0 still does not need it. Its consumers are
  libzugodb#55 (the engine) and zugodb#72 (the R mapping).
- Arbitrary precision stays a non-goal (§3).

## 3. Non-goals

- Forking bit64 or changing its behaviour. `int64` is a second implementation
  of the same layout (§0.1): code written for `integer64` keeps working, both
  packages load together, and zuint registers nothing on bare `integer64`.
- Arithmetic on small types (`int8`/`int16`/`uint8`/`uint16`/`uint32`). Values
  fit in R integers or doubles exactly. Thin "schema-fidelity" classes that only
  remember the engine type for write-back are a later, optional milestone.
- Arbitrary precision (`gmp`, `Rmpfr`), and decimals beyond 38 digits
  (`decimal256`). Fixed-point decimals up to 38 digits were a non-goal
  until 2026-11-20 and are now in scope (§2.2, #88).
- Matrix algebra on wide integers. The functions that dispatch refuse a
  zuint vector with a `zuint_unsupported_error` (`%*%`, `crossprod()`,
  `tcrossprod()`, `cbind()`, `rbind()`, `as.matrix()`, `aperm()`,
  `scale()`), and so does the `Complex` group (`Conj()`, `Re()`, `Im()`,
  `Mod()`, `Arg()`; #152). `matrix()`, `array()`, `outer()` and `diag()`
  do not dispatch and cannot be intercepted; they return the raw bits, as
  `ifelse()` does, and `?zu_ifelse` says so (2026-11-28, #160).

## 4. Types and representation

| Type | R storage | Class | NA sentinel | Representable range |
| --- | --- | --- | --- | --- |
| `int64` | REALSXP, bits reinterpreted (bit64 layout) | `c("zu_int64", "integer64")` | INT64_MIN | ±(2⁶³ − 1) |
| `uint64` | ALTREP REALSXP over a REALSXP payload | `zu_uint64` | UINT64_MAX | [0, 2⁶⁴ − 2] |
| `int128` | ALTREP REALSXP over a CPLXSXP payload (re = low, im = high word) | `zu_int128` | INT128_MIN | ±(2¹²⁷ − 1) |
| `uint128` | ALTREP REALSXP over a CPLXSXP payload | `zu_uint128` | UINT128_MAX | [0, 2¹²⁸ − 2] |

### 4.1 Why int64 keeps the bit64 layout

data.table, arrow, duckdb, RPostgres, bigrquery and nanotime test `inherits(x,
"integer64")` and read `REAL(x)` as `int64_t*`. Subclassing `integer64` gives
automatic interop. zuint's methods dispatch first through the `zu_int64` class,
and plain `integer64` from other packages is accepted everywhere and wrapped for
free (only the class attribute changes). zuint never registers methods on bare
`integer64`, so it doesn't conflict with bit64.

The known cost: class-unaware code sees raw bits as doubles. This is documented,
and helpers cover the common traps (`zu_ifelse()`, `zu_vapply()` or vctrs
equivalents). `serialize(ascii = TRUE)` and `dput()` corrupt the NaN payloads
that negative values and NA occupy; binary serialization (the default) is
exact. Same as bit64; documented.

Subclassing `integer64` has two consequences the implementation must handle:

- **Every method bit64 defines for `integer64`, zuint defines for
  `zu_int64`.** Otherwise the answer depends on whether bit64 is loaded: with
  it, S3 falls through to bit64's method (for example its truncating `mean`);
  without it, to base R on the raw bits. The suite runs twice, with bit64
  attached and with it absent, and compares results.
- **Mixed `zu_int64` ⊕ `integer64` calls need `chooseOpsMethod()`.** When the
  two operands of an `Ops` call have different methods, R warns "incompatible
  methods" and falls back to the internal double arithmetic on the raw bits.
  Since R 4.3.0, `chooseOpsMethod(x, y, mx, my, cl, reverse)` lets a class
  claim precedence; zuint's method returns TRUE for every `zu_*` class, so
  `zu_int64 + integer64` runs zuint's exact arithmetic. This sets the minimum
  R version: `Depends: R (>= 4.3.0)`.
- **A plain `integer64` argument never reaches a base generic.** Decided
  2026-11-28 (#150): wherever zuint's code calls `is.na()`, `as.logical()`
  or `==` on an argument that may be a plain `integer64` (the other operand
  of `&`, a `zu_match()` table, a vctrs cast's `x`, `zu_ifelse()`'s `test`,
  a decimal comparison), it first swaps the class to `zu_int64`
  (`zu_from_bit64()`). Without bit64 loaded those generics would read the
  bits. Converting once at the entry, rather than testing NA by the
  sentinel at each use, keeps every later call on zuint's methods.
- **A count is a number, like an index.** Decided 2026-11-28 (#153): a
  zuint or `integer64` value given as `rep()`'s `times`, `diff()`'s `lag`,
  `head()`'s `n`, `length<-`, a width and the like is converted exactly to
  an integer (`zu_index()`), or `NA` with a `zuint_cast_warning` beyond
  its range, before base sees it. zuint registers `head()` and `tail()`
  methods for this alone.
- **bit64's own generics and S4 casts must see the zuint types by value.**
  Decided 2026-11-28. bit64's `*`, `/`, `^`, `[<-` and `[[<-` ask its
  `is.double()` generic and use a `TRUE` operand's bits as a double, so
  zuint registers `is.double()` for `zu_uint64` (returning `FALSE`) in
  bit64's namespace when bit64 loads (#151); the 128-bit types are
  complex and `zu_int64` inherits `is.double.integer64()`. bit64's masked
  `setdiff()`, `union()`, `intersect()`, `is.element()` and `setequal()`
  call `methods::as(x, "integer64")`, so zuint declares
  `setOldClass(c("zu_int64", "integer64"))` (#161), which imports
  `methods`. That defines an `integer64` S4 class in zuint too when bit64
  is not loaded; with both loaded bit64's coercions and `is()` answer as
  before, whichever loaded first. A plain `integer64` with an int128 value
  assigned into it still fails in bit64's `[<-`, which asks `is.complex()`
  and converts the target with `as()`; that is bit64's object and zuint
  leaves it.
- **`%*%` is a bit64 method, not a mask.** Decided 2026-11-28 (#160):
  bit64 defines `%*%.integer64` through R's `matrixOps` group, so zuint
  defines `%*%` (and `crossprod()`, `tcrossprod()`, members from R 4.4.0)
  for every zuint class as the matrix refusal (§3). The parity test's
  allowlist no longer lists it.

- **Base functions that cannot dispatch.** Decided 2026-11-28 (#165, #149,
  #162). Class-unaware code reads the payload, and no method can stop it.
  `?zu_ifelse` lists them, each with the zuint route; the list, checked on
  the code of 2026-11-28:
  - `c()` and `rbind()` of data frames whose first argument or first column
    is not zuint (put the zuint first, or vctrs and dplyr);
  - the `Summary` group's first-argument rule (#125);
  - `is.unsorted()` (use `xtfrm()`), `complete.cases()` (use `!is.na()`),
    `aggregate()` and `rowsum()` (group by `as.character()`), `var()` and
    `cor()` (use `as.double()`), `unlist()`, `sapply()` and `vapply()` (use
    `do.call(c, )` and `zu_vapply()`), `ifelse()` (`zu_ifelse()`),
    `formatC()` and `sprintf("%f")` (use `format()` and `as.character()`);
  - a zuint vector as the index or the count of a base function that does
    not dispatch on it: `letters[int64(2)]`, `rep(1, int64(3))`,
    `rep_len()`, `seq_len()`, `numeric()`, `vector()` (use `as.integer()`); #153 converts a count only where the function
    dispatches on the zuint argument (`rep(x, times)`);
  - `matrix()`, `array()`, `outer()` and `diag()`;
  - `match()`, `%in%`, `table()`, `merge()` and the set functions of a zuint
    vector against a bare double or logical (§7);
  - row growth of data frames and data.table's fills (§9).
  `cut()` has a method (§7).
- **A bare number meets a zuint vector as text in base `match()`.**
  Decided 2026-11-28 (#149): base `match()` applies `mtfrm()` to the
  classed side only, and the unclassed double becomes text by R's own rules
  (`1e5` is `"1e+05"`), so the answer depends on `scipen` and `OutDec`. No
  method can reach the bare side, and `intersect()` and its kin are not
  generic, so zuint defines no method for them and does not refuse a bare
  double. `zu_match()` and `%zin%` are the exact route.
- **Padded rows read as a value.** Decided 2026-11-28 (#162): base R pads
  with `NA_real_` and `NA_complex_`, which are valid payloads (§4.3). Row
  growth of a data frame (`d[n + k, col] <- v`, `xpdrows.data.frame()`) and
  data.table's `rbindlist(fill = TRUE)`, `d[c(1, NA)]`, `shift()` and
  `:= NA` pad zuint columns with them without reaching a method, and a
  data.table `by` groups a `uint64` NA with its neighbour. `rbind()`,
  `merge()`, vctrs and dplyr pad correctly. Documented, not fixable here.

### 4.2 Why the other types use ALTREP

These are new types with no ecosystem expecting their bits, so they can degrade
gracefully:

- The exact payload lives in the ALTREP object's `data1`.
- `Elt`, `Get_region` and `Dataptr` present the **numeric value as a double**:
  exact up to 2⁵³, rounded beyond. So `unclass()`, base `plot()`, `mean()` and
  naive C code see sensible numbers.
- zuint's C code checks the ALTREP class and reads `data1` directly, so
  precision is never lost internally.

Slot layout, fixed so the Arrow bridge (§9.1) and the double view do not
compete for the same slot:

- `data1`: the exact payload. Either an R-owned REALSXP/CPLXSXP (the v0.1
  plain storage, so `zu_storage()` is a no-op on it), or an EXTPTRSXP to a
  foreign buffer whose `prot` field holds the Arrow release callback. The
  class is the same; the payload kind is a tag read from the pointer type.
- `data2`: the cached double view (REALSXP), or `R_NilValue` while none has
  been materialised. Nothing else lives here.

ALTREP details:

| Method | Behaviour |
| --- | --- |
| `Length` | payload length |
| `Elt` / `Get_region` | convert on the fly, no materialisation |
| `Dataptr(x, writeable = FALSE)` | materialise the double view once into `data2`, cache it |
| `Dataptr(x, writeable = TRUE)` | a foreign payload is first copied into an R-owned one (engine memory is never written). Then materialise and mark `data2` as authoritative. The next exact access rebuilds the payload from the doubles, with a warning if any value exceeds 2⁵³. Only class-unaware code reaches this path; zuint's own `[<-` and `[[<-` write the payload |
| `Dataptr_or_null` | NULL unless materialised (lets R take the `Elt` path) |
| `Duplicate` | copy the payload, drop any materialised view |
| `Extract_subset` | subset the payload directly (stays exact) |
| `Serialized_state` / `Unserialize` | payload plus class; needs zuint installed to load |
| `Is_sorted`, `No_NA` | cached flags, set by constructors and sort routines |
| `Sum`, `Min`, `Max` | exact in C; the result is converted to double for base's generic path |

Option `zuint.serialize = "exact"` (default) or `"double"`. The latter writes
the materialised doubles, so files load without zuint (lossy beyond 2⁵³).

### 4.3 The representation contract

Decided 2026-11-25 (Stage 9; review X3): `zu_storage(x)` and
`zu_from_storage(payload, type)` are the public representation contract,
not an escape hatch. A package that builds zuint vectors in C (zuarrow
under X3(b), later a zero-copy reader over `zubin`) relies on them, and
`?zu_storage` states the contract:

- the payload is a REALSXP of 64-bit integer bits for `int64` and
  `uint64`, and a CPLXSXP for `int128` and `uint128` whose real part is the
  low word and imaginary part the high word, in machine byte order;
- the NA bit patterns are `INT64_MIN`, `UINT64_MAX`, `INT128_MIN` and
  `UINT128_MAX`, so the engine value at that pattern has no zuint form;
- names are kept, no other attribute is;
- the shapes and patterns change only under the rule the R API follows,
  with a deprecation announced in `NEWS.md`.

A future native R int64 type, or the ALTREP payloads of §4.2, would change
what these accessors do inside, not the shapes they promise.

## 5. Promotion lattice

Every mixed operation is lossless or an error. The promotion order (it is not
a lattice: `int128` and `uint128` have no common type):

```text
logical ─► integer ─► int64 ──► int128
                   └► uint64 ─┤
                       └─────────► uint128
```

Why no common type for int128 ⊕ uint128 (and int64 ⊕ uint128): no wider fixed type holds both ranges, picking a side would overflow the other, picking by the data makes the type depend on values, and double is lossy; so the explicit cast is the user's choice of range (#51). Comparison is exempt.

| x ⊕ y | result |
| --- | --- |
| logical ⊕ integer | integer, as base R |
| integer ⊕ int64 | int64 |
| integer ⊕ uint64 | uint64. The integer is cast first; a negative value is out of range and goes through the overflow policy (§6). Decided 2026-10-15 |
| int64 ⊕ uint64 | int128 |
| uint64 ⊕ uint64 | uint64 |
| integer, int64 or uint64 ⊕ int128 | int128 |
| integer ⊕ uint128, uint64 ⊕ uint128 | uint128 (a negative integer as above) |
| int128 ⊕ uint128, int64 ⊕ uint128 | error: no lossless common type, cast explicitly |
| any ⊕ double | error if any double is non-integral or out of range; otherwise the wide type. Option `zuint.double = "allow"` falls back to double with a warning |

Comparison is the exception to the double rule: `x == 1.5` and `x < 1e300` are
exact and never error. A double is compared as the pair (floor, ceiling) in
the wide type, or by sign when it is out of range.

The same table backs `vec_ptype2`/`vec_cast` when vctrs is installed, and
`c()`/`Ops` group generics otherwise.

## 6. Arithmetic semantics

- **Operators** `+ - * %/% %% abs sign`: R-like default. Overflow gives NA plus
  one warning per call.
- **`checked_add()` etc.**: error on overflow.
- **`wrapping_add()` etc.**: modular arithmetic (2⁶⁴ or 2¹²⁸); for hashing and
  checksums.
- **`saturating_add()` etc.**: clamp to range (optional, cheap to add).
- **Division** follows R: `%/%` is floor division and `%%` takes the sign of the
  divisor (not C's truncation). `/` returns double, as R's integer `/` does.
  Division by zero gives NA under every policy except `checked_`, which
  errors. `MIN %/% -1` cannot overflow because MIN is the NA sentinel.
- **`^`** with a non-negative integer exponent stays exact; anything else gives
  double. `checked_pow()` and `wrapping_pow()` have no double result: a
  negative or fractional exponent is a `zuint_type_error`, so an explicit
  policy never returns a rounded value (decided 2026-11-28, #67).
- **`^` with an exponent at or past the type's width, and with NA**
  (decided 2026-11-28, #158): an integral double exponent of any size,
  `Inf` included, never leaves the type. Every base but 0, 1 and -1 overflows
  (the policy applies), and those three have their exact answers; the
  exponent is cut to 2¹²⁷, which every double of that size is even
  alongside. `NA ^ 0` is 1 and `1 ^ NA` is 1, as in base R and bit64, under
  every policy: an NA that cannot change the result does not make it NA.
  `(-1) ^ NA`, `2 ^ NA` and `NA ^ 2` stay NA.
- **Unsigned negation** is an error (`checked_`) or wraps (`wrapping_`); the
  default gives NA plus a warning. A negative integer operand to an unsigned
  type (§5) is the same case: out of range, handled by the policy.
- **The NA sentinel under `wrapping_`** (decided 2026-10-15): NA in, NA out,
  and a wrapped result that lands on the sentinel becomes NA. NA-ness never
  depends on which policy produced the bits. The chance is 2⁻⁶⁴ per
  operation on uint64 and documented; code that needs the full modular range
  uses `uint128`.
- **Bit operations** (`bit_and/or/xor/not`, shifts, `popcount`, `clz`, `ctz`)
  are defined for all types; shifts beyond the width give NA.
- **Comparison** (`== != < <= > >=`) is exact across types via the lattice,
  never via double.

## 7. Reductions and vector operations

| Function | Behaviour |
| --- | --- |
| `sum` | type stable (decided 2026-10-15): the result has the input's type, and overflow gives NA plus a warning, as base R's `sum()` on integers does. int64 and uint64 accumulate in 128 bits so the overflow check is exact; `sum(int128(x))` is the wide sum |
| `cumsum`, `cumprod` | same type as input; overflow gives NA from that point on |
| `mean` | exact sum ÷ n, returned as double, with no warning when it rounds (decided 2026-11-28, #71). `mean_exact()` is not exported (it is on the later list); the exact route is `sum()` and integer division, `sum(x) %/% length(x)` with `sum(x) %% length(x)`. The double is the exact quotient rounded once, to nearest with ties to even (decided 2026-11-27, #148): the 128-bit (or wider) sum is divided in integers and its quotient and remainder rounded together, never a double sum divided by n. `median()` is the mean of the middle pair, the same way |
| `min`, `max`, `range` | exact; `na.rm` supported |
| `sort`, `order`, `rank`, `xtfrm` | LSD radix sort on the unsigned-key transform (sign bit flipped for signed types); stable. `xtfrm` returns integer ranks (ties `"min"`, NA kept), never a double proxy, so base `order()` on several keys stays exact |
| `unique`, `duplicated`, `match`, `%in%`, `table` | open-addressing hash on the exact bits, never through double |
| `diff`, `rev`, `rep`, `seq_zu()` | exact |
| `quantile` | exact order statistics; type-7 interpolation returns double |
| `cut` | decided 2026-11-28 (#165): compares each value with the breaks exactly (`x > b`, never through double), so values beyond 2^53 land in their interval; breaks are zuint or numbers in any order; the labels write the breaks in full, so `dig.lab` is accepted and unused. A single number of intervals (a fractional step) is a `zuint_unsupported_error`; `NA` or repeated breaks, or the wrong number of labels, a `zuint_type_error` |

Decisions of 2026-11-28 (#159, #163):

- `seq_zu(from, to, length.out = n)` computes the step `(to - from) / (n - 1)`
  when it is whole and is a `zuint_type_error` when it is not (a vector of
  integers has no fractions). `by` defaults to -1
  when `to` is below `from`, `seq(n)` is `1:n` as in base, a fractional
  `length.out` rounds up as base does, and `to` with `by` and `length.out`
  is an error, as in base.
- Arguments base takes and zuint cannot honour are refused with
  `zuint_unsupported_error` (`sort(partial =)`, a `zero.print` that is not a
  string) or `zuint_type_error` (an NA, negative or non-numeric `max`, `lag`
  or `differences` below 1 or fractional, which base answers with garbage and
  a warning, a `nomatch` of length other than one), never ignored.
  `na.rm` is read as a logical, so 1 is TRUE; base's `mean()` tests
  `isTRUE(na.rm)` and gives NA for 1, which is not copied.

## 8. Construction, parsing, formatting

- `int64(x)`, `uint64(x)`, `int128(x)`, `uint128(x)`: casts from
  logical/integer/double/character/other zuint types/`integer64`. Doubles must
  be integral and in range, otherwise NA plus a warning.
- **Character parsing in C:** decimal with an optional sign, `0x` hex and `0b`
  binary prefixes, `_` digit separators; exact, with overflow detection.
- **Formatting:** exact decimal (128-bit via repeated division by 10¹⁹), plus
  `format_hex()` and `format_bin()`. `print`/`format`/`as.character` methods;
  pillar methods registered lazily.
- `as.double()` warns only when a value exceeds 2⁵³ in magnitude.
- `as.integer()` gives NA plus a warning outside ±(2³¹ − 1).

## 9. Interop (the headline feature)

### 9.1 One bridge: the Arrow C Data Interface, through zuarrow

All engine interop goes through the **Arrow C Data Interface** (`ArrowSchema` /
`ArrowArray` structs). Since Stage 9 (2026-11-25) the R surface for it is
zuarrow's: zuint registers its C conversion with zuarrow's registry and has
no Arrow functions of its own (§9.4). One C code path then serves arrow,
duckdb (which imports and exports Arrow streams), ADBC drivers and polars.

- **Import** (`ArrowArray` → zuint): read the format string and the validity
  bitmap. Verified on duckdb 1.5.4.1 and arrow 24.0.0 (2026-10-15):
  - `l` → int64, `L` → uint64.
  - `d:38,0` (decimal128, scale 0) → int128, read as the raw little-endian
    two's-complement 16 bytes. DuckDB's default Arrow export writes HUGEINT
    and UHUGEINT this way, including values beyond the 38-digit decimal128
    range (HUGEINT max exports as bits `0x7fff…ff`), so the import must not
    range-check against 10³⁸. A UHUGEINT ≥ 2¹²⁷ is indistinguishable from a
    negative value in this form; see the extension below.
  - `w:16` with `ARROW:extension:name = "arrow.opaque"` and metadata
    `{"type_name":"hugeint","vendor_name":"DuckDB"}` → int128, and
    `"uhugeint"` → uint128. DuckDB produces this with
    `SET arrow_lossless_conversion = true`, and re-imports it as HUGEINT /
    UHUGEINT. It is the only schema-exact form for 128-bit values.
  - How the extension is recognised (decided 2026-11-27, #154): the
    metadata must be one valid JSON object (RFC 8259, UTF-8, nesting at
    most 1024 deep) whose own top-level `vendor_name` is the string
    `"DuckDB"` and whose own `type_name` is `"hugeint"` or `"uhugeint"`,
    values with their escapes decoded, keys as written, the first of a
    repeated key counting; this is how DuckDB reads the stream through
    arrow, recorded for 26 pairs of metadata string and storage. Arrow's
    simdjson parser looks only at the keys it wants and so reads some
    invalid documents (a bad escape or number elsewhere, a trailing
    comma); zuint reads none of them, so such a column is zuarrow's to
    convert. The extension is
    checked before the format: on decimal128 storage DuckDB reads the two
    types as their bits too, and so does zuint, but any other
    `arrow.opaque` type on a decimal is not an integer and never imports
    as int128, `to = int128()` or not. More than 4096 metadata entries
    (`ZU_METADATA_MAX_ENTRIES`) is a `zuint_arrow_error` (#166): the
    extension cannot be read, and reading the storage instead would change
    the column's type.
  - The decimal format is read by hand in the C Data Interface's form only
    (2026-11-27, #156): `d:`, digits, a comma, digits, and an optional
    comma and digits for the bit width, which must be 128. A sign, a space
    or a missing part is not that form, and a number cannot wrap.
  - Nulls become the NA sentinel; that always needs a pass over the buffer.
- **Zero-copy** is a v0.4 feature (§13). A plain REALSXP owns its memory, so
  v0.2 copies every buffer. From v0.4, an ALTREP payload wraps the engine
  buffer when the array has no nulls: `data1` is an external pointer whose
  `prot` field holds the release callback (§4.2). For int64 the wrapper's
  `Dataptr` returns the int64 bits themselves, which is the bit64 layout, so
  zero-copy int64 keeps `integer64` interop intact.
- **Export** (zuint → `ArrowArray`): produce a buffer plus a validity bitmap
  from NA sentinels, with the correct format string, so write-back keeps the
  type. int64 and uint64 export as `l` and `L`. int128 and uint128 export as
  the `arrow.opaque` extension above, because DuckDB turns a
  `decimal128(38, 0)` column into `DECIMAL(38,0)`, not HUGEINT. The export
  is an array handle in nanoarrow's `r.h` layout (the array's external
  pointer, classed `nanoarrow_array`, with the schema's in its tag), the
  form a zuarrow `from` handler returns.
- **No `decimal128(38, 0)` export** (decided 2026-11-25, Stage 9; review
  X5). The former `decimal = TRUE` form of `zu_to_arrow()` is gone with that
  function. A zuarrow `from` handler has one form per class, DuckDB reads
  the extension back as HUGEINT, and a consumer that wants a decimal can
  cast in its own engine. Reopen when a consumer is found that needs it.
- **NA ↔ null:** sentinel values map to null bits both ways. A real value
  equal to a sentinel (e.g. UINT64_MAX in an engine column) cannot be held,
  and zuarrow's `lossy` policy decides (2026-11-25; review X4): an error
  under `"error"`, NA with a warning under `"warn"`, NA under `"allow"`.
  Under `"character"` it is an error too, because the handler returns one
  class for every batch and text for only the batches that hold such a
  value could not be combined. The conditions are zuarrow's classes
  (`zuarrow_lossy_error`, `zuarrow_lossy_warning`), so a caller handles
  them with the rest of zuarrow's.

### 9.4 The zuarrow registrations

Decided 2026-11-25 (Stage 9). In `.onLoad()`, zuint sets a
`packageEvent("zuarrow", "onLoad")` hook, as for its other Suggests, and
registers with `package = "zuint"`, so zuarrow drops the entries when zuint
unloads:

| Key | `to` reads | `from` class | `from` writes |
| --- | --- | --- | --- |
| `l` | `int64` | `zu_int64` | `l` |
| `L` | `uint64` | `zu_uint64` | `L` |
| `arrow.opaque` | `hugeint` → `int128`, `uhugeint` → `uint128`; any other opaque type through zuarrow's own conversion | `zu_int128`, `zu_uint128` | the extension of §9.1 |

All three are exact. There is no `d:*` registration (review X5): a decimal
column is the `decimal` package's, and `to = int128()` is the opt-in that
reads a `decimal128(p, 0)` with `p` up to 38 as its bits. When a caller
names a zuint prototype for a column of another format, zuarrow calls that
class's handler, which reads the column, through zuarrow's built-in
conversion if zuint does not read the format itself, and casts it to the
prototype's type under zuint's rules. The `arrow.opaque` handler serves
two classes, so it casts nothing. Under an `int64()` or `uint64()`
prototype, zuint reads the small integer formats (`c`, `C`, `s`, `S`, `i`,
`I`) itself, exactly, before the cast (decided 2026-11-27, #155): through
zuarrow they became R integers first, whose `NA` is INT32_MIN. Every
handler error about the schema or the array is a `zuint_arrow_error`
(#166).

### 9.2 Per-partner mapping

| Partner | Mapping |
| --- | --- |
| bit64 `integer64` | zero-copy both ways (`as_integer64()`, and `int64()` on an integer64 only swaps the class) |
| Arrow | through zuarrow (§9.4): `int64` ↔ int64, `uint64` ↔ uint64, `arrow.opaque` hugeint/uhugeint ↔ int128/uint128; `decimal128(p, 0)` → int128 only with `to = int128()`. `decimal128(p, s>0)` has no zuint reader: the Arrow mapping of zuint's `decimal128` class waits (§2.2, §15). arrow R today converts uint64, uint32 and decimal128 to double. Since Stage 9 zuint registers no methods on arrow's generics |
| DuckDB | BIGINT ↔ int64, UBIGINT ↔ uint64, HUGEINT ↔ int128, UHUGEINT ↔ uint128, via DuckDB's Arrow export and zuarrow: `SET arrow_lossless_conversion = true`, since the default export loses UHUGEINT values ≥ 2¹²⁷ (§9.1), then `zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))`. The former `zu_duckdb_query()` and `zu_duckdb_register()` are gone (Stage 9). Today the R client's `bigint` option accepts only `"numeric"` and `"integer64"`; HUGEINT and UHUGEINT always arrive as doubles |
| nanoarrow | zuarrow reads and writes nanoarrow handles; zuint registers no nanoarrow methods since Stage 9. Today `convert_array(uint64_array, bit64::integer64())` clamps 2⁶³ and above to 2⁶³ − 1 |
| data.table | int64 works natively. Other types: `as.character()` or `as_integer64()` before keyed joins; documented. data.table pads `uint64`, `int128` and `uint128` columns with R's NA bits, a valid value, in `rbindlist(fill = TRUE)`, `d[c(1, NA)]`, `shift()` and `:= NA`, and groups a `uint64` NA with its neighbour (decided 2026-11-28, #162; §4.1) |
| vctrs / dplyr / tibble | `vec_ptype2`/`vec_cast`/`vec_proxy` registered lazily; `vec_proxy` returns the payload for exact equality and ordering |

### 9.3 Upstream adoption (the real distribution channel)

- **duckdb R client (Kirill Müller):** propose `bigint = "zuint"` (or a
  type-mapping hook) so UBIGINT/HUGEINT/UHUGEINT come back as zuint types.
  It would build zuint vectors through the representation contract of §4.3.
- *Removed 2026-11-25 (Stage 9):* listing zuint as nanoarrow's or arrow's
  conversion target. The Arrow route is zuarrow's, so that ask, if any, is
  zuarrow's to make.
- Approach both only after v0.3, with the round-trip matrix (§12) green and
  benchmarks published.

## 10. C core

```text
src/
  zu_wide.h        # type traits: ZU_INT64, ZU_UINT64, ZU_INT128, ZU_UINT128
  zu_ops.h         # add/sub/mul/div with overflow checks
  zu_parse.c       # string → wide (one implementation, all widths)
  zu_format.c      # wide → string (decimal, hex, binary)
  zu_sort.c        # radix sort on unsigned keys
  zu_hash.c        # hash table for match/unique
  zu_altrep.c      # ALTREP classes for uint64/int128/uint128
  zu_arith.c       # vectorised Ops with overflow policies
  zu_reduce.c      # sum (int128 accumulator), min/max, cumulative ops
  zu_arrow.c       # Arrow C Data Interface (vendored abi.h)
  init.c           # registration, ALTREP class init
  zu_fixed.c       # fixed-point DECIMAL(p, s) core, R-free (§2.2)
  zu_api.c         # zuint_api_v1 and zuint_get_api()
inst/include/
  zuint.h          # zuint_api_v1, the R-free C table; no R header
  zuint-r.h        # zuint_api(), its R_GetCCallable resolver
```

- Generic code uses macros or `_Generic` over the four types; no C++.
- The 128-bit type and its primitives come from `zufast/wide.h` (zufast
  0.1.1, merged in `pedrobtz/zufast#40`): a two-word struct type in every
  build, computed with `__int128` where `__SIZEOF_INT128__` is defined
  (gcc/clang on every 64-bit CRAN platform, including Rtools), and with a
  portable fallback otherwise. zuint builds its NA handling, overflow
  *policies* and promotion lattice on those checked and wrapping primitives;
  `zu_ops.h` holds only that policy layer. zuint's CI also builds with the
  fallback forced (`ZUF_NO_INT128`) so the fallback doesn't rot.
- Every routine handles NA first, then the fast path. NA checks are skipped when
  `No_NA` is set.
- No allocation inside loops; results are preallocated. Long vectors are
  supported (`R_xlen_t`).

## 11. R API surface (sketch)

```r
x <- int64("9007199254740993")
y <- uint64("18446744073709551614")
x + 1L                       # int64
x + y                        # int128 (lossless)
sum(int64(c(2^62, 2^62)))    # NA with a warning: int64 overflow
sum(int128(c(2^62, 2^62)))   # int128: 9223372036854775808
wrapping_mul(y, 31L)         # modular
checked_add(int64("9223372036854775807"), 1L)   # error
format_hex(y)                # "0xfffffffffffffffe"
as_integer64(x)              # zero-copy to bit64
zu_storage(int128(1))        # raw CPLXSXP payload
```

Every condition reports the user's call (decided 2026-11-28, #80): the
exported function's or the method's `sys.call()`, except in the `Summary`
group, whose `sys.call()` holds the evaluated payload as doubles; there the
call names the generic over its arguments, `sum(...)`, `min(...)`.

## 12. Testing

- **Round-trip matrix (acceptance test, in CI and the README).** For each engine
  type in §0 and each path (DuckDB → R → DuckDB, Arrow → R → Arrow, Parquet → R
  → Parquet), check that the schema is identical and every value is identical.
  Values include 0, ±1, 2⁵³ ± 1, MIN, MAX, MIN+1, MAX−1, nulls, and random
  fills. The engines' side is replayed from a recorded fixture (§2.1,
  2026-11-27), so it runs everywhere; CI's oracle job checks the fixture
  against the live engines.
- **Oracle:** `gmp::as.bigz` (Suggests) for property-based tests of arithmetic,
  parsing and formatting at random widths, including edge values (0, ±1, 2⁵³ ±
  1, the NaN-pattern ranges, MIN/MAX, MIN+1, MAX−1).
- **Policy tests:** each operation × each overflow policy × each type pair from
  the lattice.
- **ALTREP tests:** materialise-then-write, duplicate, subset,
  serialize/unserialize in both modes, `unclass()` sanity.
- **Interop tests:** round-trips with bit64 in the suite; data.table and
  dplyr in CI's oracle job (`tools/oracle/test-interop.R`), and arrow and
  duckdb through the recorded fixture.
- **bit64 parity:** the int64 suite runs with bit64 attached and without it,
  and the two runs must agree (§4.1). The attached run also covers
  `zu_int64` ⊕ `integer64` dispatch through `chooseOpsMethod()`.
- **Benchmarks** against bit64 for `+`, `sum`, `sort`, `match` and `unique` at
  10⁶–10⁸ elements; not slower than bit64 on int64.
- UBSan/ASan CI builds (signed overflow must never reach UB).

## 13. Milestones

1. **v0.1 core semantics, no ALTREP.** All four types on plain storage (REALSXP
   or CPLXSXP plus class); construction, parsing, formatting, arithmetic with
   policies, comparison, the promotion lattice. Gets the semantics right before
   the ALTREP work.
2. **v0.2 interop: the headline feature.** *Superseded 2026-11-25 (Stage
   9).* It shipped in Stages 4 and 5 as zuint's own bridge (`zu_arrow.c`,
   nanoarrow methods, `zu_duckdb_query()`), and Stage 9 handed the R
   surface to zuarrow (review X1). What remains of it is the C kernels
   behind the registrations (§9.4), the bit64 class-swap bridge, and the
   round-trip matrix, now run through zuarrow.
3. **v0.3 vector toolkit.** sort/order, unique/match, reductions with int128
   accumulation, bit operations, vctrs/pillar registration. **First CRAN release
   here**, with the README before/after table, benchmarks vs bit64, and a blog
   post.
4. **v0.4 ALTREP views** for uint64/int128/uint128: graceful degradation,
   zero-copy wrapping of null-free Arrow buffers (including an int64 wrapper
   whose `Dataptr` exposes the bits, §9.1), exact `Extract_subset`,
   serialization modes. Then approach duckdb and nanoarrow/arrow maintainers
   (§9.3).
5. **Later.** Schema-fidelity classes for small/uint32 types, saturating
   ops, `mean_exact`, quantiles, an
   optional ALTREP view for int64.

## 14. Risks

| Risk | Mitigation |
| --- | --- |
| Class-stripping base functions corrupt int64 | Document clearly; helpers; ALTREP types avoid it |
| ALTREP materialise-on-write loses precision | Warn when any value exceeds 2⁵³ on rebuild; tests |
| Serialized ALTREP needs zuint to load | `zuint.serialize = "double"` mode; document |
| uint64 loses one value to NA | Document; `wrapping_` ops treat it as a normal value? (open question) |
| Lattice surprises (int64 ⊕ uint64 → int128) | Explicit table in the docs; `zu_common_type()` exposed |
| `__int128` unavailable on an exotic platform | `zufast/wide.h`'s portable fallback, tested in zufast's and zuint's CI |
| Conflicts with bit64 methods | Never register on bare `integer64`; only on `zu_*` classes |
| Behaviour depends on whether bit64 is loaded | zuint defines every method bit64 defines for `integer64` (§4.1); the suite runs with and without bit64 attached |
| `zu_int64 + integer64` falls back to double arithmetic on the bits ("incompatible methods") | `chooseOpsMethod()` claims precedence for `zu_*` classes; `R (>= 4.3.0)` |
| DuckDB's default Arrow export reads UHUGEINT ≥ 2¹²⁷ as negative, and `decimal128(38, 0)` writes back as DECIMAL | Export 128-bit types as the `arrow.opaque` hugeint/uhugeint extension; document `arrow_lossless_conversion` on the connection (§9.1) |
| Engine value equal to an NA sentinel (e.g. UINT64_MAX in a UBIGINT column) | zuarrow's `lossy` policy: an error by default, NA with a warning under `"warn"` (§9.1, review X4) |
| Engine behaviour changes (duckdb/arrow type mapping, HUGEINT export format) | Round-trip matrix runs against current and dev versions of duckdb and arrow in CI |
| Upstream maintainers prefer their own solution | Keep zuint useful standalone (nanoarrow path needs no upstream changes); offer integration, don't depend on it |

## 15. Open questions

Open:

- **The Arrow mapping of `decimal128`** (§2.2): reading `decimal128(p, s)`
  into the class and writing it back would need a `d:*` key in zuarrow's
  registry, which review X5 ruled out while decimals belonged to the
  `decimal` package. To settle with zuarrow after 0.1.0.

Resolved on 2026-11-25:

- **The fixed-point R class** (§2.2): one precision and scale per vector
  on the `int128` payload, with DuckDB's result types and common types.
  The maintainer chose it over a scale-only class, which would lose
  DuckDB's `DECIMAL(p, s)` type on a round trip zugodb#72 must keep.
- Should the DuckDB bridge use DuckDB's C API directly (no R duckdb dependency)
  or go through duckdb's Arrow export? Arrow export is the plan (§9.1); the C
  API would add a non-zu runtime dependency (§2.1).


Resolved on 2026-11-25 (Stage 9):

- **Schema-fidelity classes** for the small and `uint32` types are
  zuarrow's, carried by the schema handle passed back at export
  (`arrow_array(x, schema =)`), not classes in zuint or a separate package
  (review X7).
- **Name check:** `zuint` is free on CRAN, r-universe and PyPI (checked
  2026-10-23 by the joint review).

Resolved on 2026-10-15:

- **`integer ⊕ uint64 → uint64` and `integer ⊕ uint128 → uint128`** (§5).
  The former `int128` rule made `y + 1L` change type on the most common
  unsigned operation and left `uint128 + 1L` an error. A negative integer
  operand is out of range and goes through the overflow policy, so the rule
  stays lossless or explicit.
- **The NA sentinel stays NA under `wrapping_`** (§6), and a result landing
  on it becomes NA. The alternative would make NA-ness depend on which
  policy produced the bits.
- **`sum()` is type stable** (§7): the input's type, NA plus a warning on
  overflow, as base R. `sum(int128(x))` is the wide sum. The `.wide`
  argument is dropped because it cannot pass through `sum(...)` cleanly.

- The duckdb R client (1.5.4.1) accepts only `bigint = "numeric" |
  "integer64"`; UBIGINT under `"integer64"` is the bits reinterpreted, and
  HUGEINT / UHUGEINT are always doubles (§0, §9.2).
- DuckDB exports HUGEINT and UHUGEINT as `decimal128(38, 0)` with the raw bits
  by default, and as the `arrow.opaque` extension over `fixed_size_binary(16)`
  with `arrow_lossless_conversion = true`, which it re-imports exactly (§9.1).
- arrow R (24.0.0) converts `uint64`, `uint32` and `decimal128` to double;
  nanoarrow (0.9.0) converts `uint64` to double by default and clamps it when
  asked for `integer64` (§9.2).
- An ALTREP int64 wrapper does not break `integer64` interop when its
  `Dataptr` returns the bits rather than a double view; it is the v0.4
  zero-copy path (§9.1, §13).
