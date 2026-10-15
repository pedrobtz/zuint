# RFC 0009: `zuint`, lossless Arrow and DuckDB integers in R

Adopted from [RFC 0009](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0009-zuint-wide-integers.md)
on 2026-10-15. From here on this file is authoritative; the RFC is history.

Wide integer vectors for R (`int64`, `uint64`, `int128`, `uint128`) matching the
integer types of Arrow and DuckDB. They share one C core and one promotion
lattice, and convert exactly to and from `integer64`, Arrow, DuckDB and
`decimal`.

- **Status:** Adopted 2026-10-15. Revised on 2026-10-14 alongside RFC 0035
  (`zutempo`): the 128-bit type, its checked and wrapping arithmetic, floor
  division and portable fallback come from `zufast`'s `wide.h` header
  (zufast 0.1.1, merged in `pedrobtz/zufast#40`) instead of being written
  here, so that zuint and `zutempo` share one implementation (§10).
  Reviewed on 2026-10-15: §0.1 (relation to bit64) added, the promotion
  table and the ALTREP slot layout corrected, and every engine behaviour
  previously marked *(verify)* checked against duckdb 1.5.4.1, arrow 24.0.0,
  nanoarrow 0.9.0 and bit64 4.8.2 on R 4.6.1 (§9, §15).
- **Date:** 2026-10-09; revised 2026-10-14; reviewed 2026-10-15.
- **Packages:** `zuint` (not yet created; name availability unchecked);
  `LinkingTo: zufast (>= 0.1.1)`, build time only; companion to `decimal`;
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
| decimals | `decimal32/64/128/256` | `DECIMAL(p, s)` | double | **`decimal`** (companion package) |

The pitch: **zuint + decimal cover every numeric Arrow/DuckDB type R can't
represent.**

Success criteria:

1. A DuckDB/Arrow → R → DuckDB/Arrow round trip preserves both the schema and
   every value, for every type in the table. The one documented exception is
   a value equal to the type's NA sentinel (§4, §9.1).
2. One-line adoption: `nanoarrow::convert_array(x, zuint::uint64())`, and
   eventually a duckdb option.
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
   DuckDB, Arrow and `decimal`.
6. Graceful degradation: misused uint64/int128 values look like approximate
   numbers, never garbage.
7. No dependencies outside the zu-* family (§2.1). vctrs/pillar integration
   is registered lazily.

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
  anything there (testthat, withr, gmp as the oracle, and the engines for
  the round-trip matrix), skipped when absent. Outside the tests, a Suggests
  package appears only in lazily registered methods on its own generics
  (bit64, nanoarrow, arrow, duckdb, vctrs, pillar), and the core, including
  the Arrow bridge, never calls into one.
- **The Arrow bridge is self-contained.** zuint speaks the Arrow C Data
  Interface through the vendored `abi.h` (§9.1) and exchanges `ArrowArray`
  and `ArrowSchema` structs as external pointers. nanoarrow, arrow and duckdb
  glue is sugar on top of that, not a requirement.
- **`decimal` depends on zuint, never the reverse.** Both bridge functions in
  §9.2 live in `decimal`.

## 3. Non-goals

- Forking bit64 or changing its behaviour. `int64` is a second implementation
  of the same layout (§0.1): code written for `integer64` keeps working, both
  packages load together, and zuint registers nothing on bare `integer64`.
- Arithmetic on small types (`int8`/`int16`/`uint8`/`uint16`/`uint32`). Values
  fit in R integers or doubles exactly. Thin "schema-fidelity" classes that only
  remember the engine type for write-back are a later, optional milestone.
- Arbitrary precision (`gmp`, `Rmpfr`) and decimals (`decimal`).
- Matrix algebra on wide integers.

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

### 4.3 Escape hatch

`zu_storage(x)` returns the raw payload (REALSXP or CPLXSXP with bits) for C
consumers, and `zu_from_storage(payload, type)` reverses it. Keeping the
representation behind these accessors means a future native R int64 type can be
adopted by changing only them.

## 5. Promotion lattice

Every mixed operation is lossless or an error. The promotion order (it is not
a lattice: `int128` and `uint128` have no common type):

```text
logical ─► integer ─► int64 ──► int128
                   └► uint64 ─┤
                       └─────────► uint128
```

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
  double.
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
| `mean` | exact sum ÷ n, returned as double; `mean_exact()` returns the quotient and remainder |
| `min`, `max`, `range` | exact; `na.rm` supported |
| `sort`, `order`, `rank`, `xtfrm` | LSD radix sort on the unsigned-key transform (sign bit flipped for signed types); stable. `xtfrm` returns integer ranks (ties `"min"`, NA kept), never a double proxy, so base `order()` on several keys stays exact |
| `unique`, `duplicated`, `match`, `%in%`, `table` | open-addressing hash on the exact bits, never through double |
| `diff`, `rev`, `rep`, `seq_zu()` | exact |
| `quantile` | exact order statistics; type-7 interpolation returns double |

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

### 9.1 One bridge: the Arrow C Data Interface

All engine interop goes through the **Arrow C Data Interface** (`ArrowSchema` /
`ArrowArray` structs). One C code path then serves arrow, duckdb (which imports
and exports Arrow streams), ADBC drivers and polars.

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
  the `arrow.opaque` extension above by default, because DuckDB turns a
  `decimal128(38, 0)` column into `DECIMAL(38,0)`, not HUGEINT. `decimal =
  TRUE` exports `d:38,0` instead for consumers without extension support,
  with an error when a value has more than 38 digits.
- **NA ↔ null:** sentinel values map to null bits both ways. A real value equal
  to a sentinel (e.g. UINT64_MAX in an engine column) is imported as NA with a
  warning; documented as the one lossy edge.
- The bridge's own R surface is `zu_from_arrow(array, schema)` and
  `zu_to_arrow(x)`, taking and returning the structs as external pointers.
  When `nanoarrow` is loaded, zuint registers `convert_array()` targets and
  `as_nanoarrow_array()` methods on top of it (lazily, via
  `setHook(packageEvent("nanoarrow", "onLoad"), …)`); nothing in the core
  calls nanoarrow, arrow or duckdb (§2.1).

### 9.2 Per-partner mapping

| Partner | Mapping |
| --- | --- |
| bit64 `integer64` | zero-copy both ways (`as_integer64()`, and `int64()` on an integer64 only swaps the class) |
| Arrow | `int64` ↔ int64, `uint64` ↔ uint64, `decimal128(p, 0)` → int128 (bits as-is, §9.1), int128/uint128 → `arrow.opaque` hugeint/uhugeint by default or `decimal128(38, 0)` on request. `decimal128(p, s>0)` goes to the `decimal` package. arrow R today converts uint64, uint32 and decimal128 to double. Methods: `as_arrow_array()`, `infer_type()` |
| DuckDB | BIGINT ↔ int64, UBIGINT ↔ uint64, HUGEINT ↔ int128, UHUGEINT ↔ uint128, via DuckDB's Arrow export/import (`duckdb_fetch_arrow` / `duckdb_register_arrow`). Helper `zu_duckdb_query(con, sql)` sets `arrow_lossless_conversion = true` on the connection first, since the default export loses UHUGEINT values ≥ 2¹²⁷ (§9.1), and returns a data frame with zuint columns. Today the R client's `bigint` option accepts only `"numeric"` and `"integer64"`; HUGEINT and UHUGEINT always arrive as doubles |
| nanoarrow | `convert_array(x, zuint::uint64())` etc.; `as_nanoarrow_array()` for zuint vectors. Today `convert_array(uint64_array, bit64::integer64())` clamps 2⁶³ and above to 2⁶³ − 1 |
| decimal | `as_decimal(int128, scale)` and `as_int128(decimal)` (exact or error), both implemented in `decimal`, which depends on zuint (§2.1) |
| data.table | int64 works natively. Other types: `as.character()` or `as_integer64()` before keyed joins; documented |
| vctrs / dplyr / tibble | `vec_ptype2`/`vec_cast`/`vec_proxy` registered lazily; `vec_proxy` returns the payload for exact equality and ordering |

### 9.3 Upstream adoption (the real distribution channel)

- **duckdb R client (Kirill Müller):** propose `bigint = "zuint"` (or a
  type-mapping hook) so UBIGINT/HUGEINT/UHUGEINT come back as zuint types.
- **nanoarrow / arrow R (Dewey Dunnington et al.):** list zuint as the
  documented conversion target for `uint64` and 128-bit values.
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

## 12. Testing

- **Round-trip matrix (acceptance test, in CI and the README).** For each engine
  type in §0 and each path (DuckDB → R → DuckDB, Arrow → R → Arrow, Parquet → R
  → Parquet), check that the schema is identical and every value is identical.
  Values include 0, ±1, 2⁵³ ± 1, MIN, MAX, MIN+1, MAX−1, nulls, and random
  fills. Skipped when duckdb/arrow are not installed; always run in CI.
- **Oracle:** `gmp::as.bigz` (Suggests) for property-based tests of arithmetic,
  parsing and formatting at random widths, including edge values (0, ±1, 2⁵³ ±
  1, the NaN-pattern ranges, MIN/MAX, MIN+1, MAX−1).
- **Policy tests:** each operation × each overflow policy × each type pair from
  the lattice.
- **ALTREP tests:** materialise-then-write, duplicate, subset,
  serialize/unserialize in both modes, `unclass()` sanity.
- **Interop tests:** round-trips with bit64, data.table `fread` output, arrow
  and duckdb (skip if not installed).
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
2. **v0.2 interop: the headline feature.** Arrow C Data Interface import/export
   (`zu_arrow.c`, copying every buffer), nanoarrow `convert_array()` /
   `as_nanoarrow_array()` methods, the bit64 class-swap bridge, a
   `zu_duckdb_query()` helper, and the **round-trip matrix green in CI**.
   With this the package is demo-able, even before the full vector toolkit
   exists.
3. **v0.3 vector toolkit.** sort/order, unique/match, reductions with int128
   accumulation, bit operations, vctrs/pillar registration. **First CRAN release
   here**, with the README before/after table, benchmarks vs bit64, and a blog
   post.
4. **v0.4 ALTREP views** for uint64/int128/uint128: graceful degradation,
   zero-copy wrapping of null-free Arrow buffers (including an int64 wrapper
   whose `Dataptr` exposes the bits, §9.1), exact `Extract_subset`,
   serialization modes. Then approach duckdb and nanoarrow/arrow maintainers
   (§9.3).
5. **Later.** Schema-fidelity classes for small/uint32 types, the `decimal`
   bridge for scale > 0 decimals, saturating ops, `mean_exact`, quantiles, an
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
| DuckDB's default Arrow export reads UHUGEINT ≥ 2¹²⁷ as negative, and `decimal128(38, 0)` writes back as DECIMAL | Export 128-bit types as the `arrow.opaque` hugeint/uhugeint extension; `zu_duckdb_query()` enables `arrow_lossless_conversion` (§9.1) |
| Engine value equal to an NA sentinel (e.g. UINT64_MAX in a UBIGINT column) | Import as NA with a warning; documented as the single lossy edge; `zu_sentinel_check()` reports affected columns |
| Engine behaviour changes (duckdb/arrow type mapping, HUGEINT export format) | Round-trip matrix runs against current and dev versions of duckdb and arrow in CI |
| Upstream maintainers prefer their own solution | Keep zuint useful standalone (nanoarrow path needs no upstream changes); offer integration, don't depend on it |

## 15. Open questions

Open:

- Should the DuckDB bridge use DuckDB's C API directly (no R duckdb dependency)
  or go through duckdb's Arrow export? Arrow export is the plan (§9.1); the C
  API would add a non-zu runtime dependency (§2.1).
- Should schema-fidelity classes for small types live in zuint or in a separate
  tiny package?
- Name check: `zuint` on CRAN, r-universe and PyPI.

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
