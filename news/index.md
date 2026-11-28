# Changelog

## zuint 0.0.0.9000

- [`cut()`](https://rdrr.io/r/base/cut.html) of a zuint or decimal
  vector compares exactly against the breaks, zuint or numbers, with
  base’s `labels`, `right`, `include.lowest` and `ordered_result`; the
  default labels write the breaks in full. A single number of intervals
  is a `zuint_unsupported_error`
  ([\#165](https://github.com/pedrobtz/zuint/issues/165)).
- The help says what base R cannot dispatch
  ([\#149](https://github.com/pedrobtz/zuint/issues/149),
  [\#162](https://github.com/pedrobtz/zuint/issues/162),
  [\#165](https://github.com/pedrobtz/zuint/issues/165)):
  [`?zu_match`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  no longer claims base [`match()`](https://rdrr.io/r/base/match.html)
  and `%in%` agree with it, because a bare double is compared as text,
  and
  [`?zu_ifelse`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
  lists the base functions that read the payload, each with its zuint
  route, and the data-frame and data.table row padding that writes R’s
  NA bits as a value.
- Arguments zuint methods ignored are now honoured or refused
  ([\#163](https://github.com/pedrobtz/zuint/issues/163)):
  [`mean()`](https://rdrr.io/r/base/mean.html) and
  [`median()`](https://rdrr.io/r/stats/median.html) read `na.rm` as a
  logical (`NA` or text is a `zuint_type_error`);
  [`sort()`](https://rdrr.io/r/base/sort.html) returns `list(x, ix)` for
  `index.return = TRUE`, checks `na.last`, and refuses `partial` with a
  `zuint_unsupported_error`;
  [`duplicated()`](https://rdrr.io/r/base/duplicated.html),
  [`unique()`](https://rdrr.io/r/base/unique.html) and
  [`anyDuplicated()`](https://rdrr.io/r/base/duplicated.html) honour
  `incomparables`; [`format()`](https://rdrr.io/r/base/format.html)
  honours `big.interval`, `zero.print`, `trim` and a textual `width`,
  and `format(big.mark = ".")` no longer warns under
  `options(OutDec = ",")`; [`diff()`](https://rdrr.io/r/base/diff.html)
  refuses a `lag` or `differences` below 1 or fractional;
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  refuses a `nomatch` of length other than one;
  [`print()`](https://rdrr.io/r/base/print.html) accepts `quote` and
  truncates a fractional `max` as base R does, and refuses a missing,
  negative or non-numeric one.
- [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md) and
  [`seq()`](https://rdrr.io/r/base/seq.html) of a zuint vector no longer
  ignore `to` when `length.out` is given: the whole step between them is
  computed, and a fractional one is a `zuint_type_error`. The step
  defaults to -1 when `to` is below `from`, `seq(n)` is `1:n`, and a
  fractional `length.out` rounds up as in base R; a negative or `NA` one
  is a `zuint_type_error`
  ([\#159](https://github.com/pedrobtz/zuint/issues/159)).
- [`round()`](https://rdrr.io/r/base/Round.html) and
  [`signif()`](https://rdrr.io/r/base/Round.html) take a fractional
  `digits` as base R does (round half up, so `round(x, 2.5)` rounds to 3
  digits), and an infinite or very large one no longer fails with an
  unclassed error; an `NA` `digits` is a `zuint_type_error`
  ([\#157](https://github.com/pedrobtz/zuint/issues/157)).
- `x ^ y` with an integral double exponent of 2^128 or more stays in the
  type: 0, 1 and -1 have their exact answers and any other base
  overflows. `NA ^ 0` and `1 ^ NA` are 1, as in base R and bit64
  ([\#158](https://github.com/pedrobtz/zuint/issues/158)).
- [`int64()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
  [`uint64()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md),
  [`int128()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md)
  and
  [`uint128()`](https://pedrobtz.github.io/zuint/reference/zuint-types.md)
  create signed and unsigned 64- and 128-bit integer vectors from
  logical, integer, double, decimal character, bit64 `integer64` and
  each other. Conversion is exact or gives `NA` with a
  `zuint_cast_warning`; it never rounds or clamps.
- `int64` has class `c("zu_int64", "integer64")` and bit64’s storage, so
  code that reads `integer64` reads it unchanged.
- `NA_int64_`, `NA_uint64_`, `NA_int128_` and `NA_uint128_`.
- The base vector protocol for all four types: subsetting and assignment
  (with exact casting of the assigned value),
  [`c()`](https://rdrr.io/r/base/c.html),
  [`rep()`](https://rdrr.io/r/base/rep.html),
  [`rev()`](https://rdrr.io/r/base/rev.html), `length<-`,
  [`is.na()`](https://rdrr.io/r/base/NA.html),
  [`anyNA()`](https://rdrr.io/r/base/NA.html),
  [`as.character()`](https://rdrr.io/r/base/character.html),
  [`as.double()`](https://rdrr.io/r/base/double.html) (with a
  `zuint_precision_warning` when it rounds),
  [`as.integer()`](https://rdrr.io/r/base/integer.html),
  [`as.logical()`](https://rdrr.io/r/base/logical.html),
  [`as.list()`](https://rdrr.io/r/base/list.html), data frame columns,
  [`format()`](https://rdrr.io/r/base/format.html),
  [`print()`](https://rdrr.io/r/base/print.html),
  [`str()`](https://rdrr.io/r/utils/str.html) and
  [`summary()`](https://rdrr.io/r/base/summary.html).
- Exact arithmetic: `+`, `-`, `*`, `%/%` (floor), `%%` (sign of the
  divisor), `^` with a non-negative integer exponent, unary minus,
  [`abs()`](https://rdrr.io/r/base/MathFun.html) and
  [`sign()`](https://rdrr.io/r/base/sign.html). An out-of-range result
  is `NA` with one `zuint_overflow_warning` per call. `/` and other
  `Math` functions compute in double.
- [`checked_add()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`checked_sub()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`checked_mul()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`checked_pow()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`checked_neg()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  raise a `zuint_overflow_error` instead, and
  [`checked_idiv()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`checked_mod()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  a `zuint_division_error` on a zero divisor;
  [`wrapping_add()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`wrapping_sub()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`wrapping_mul()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`wrapping_pow()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`wrapping_neg()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  compute modulo 2^64 or 2^128.
- Mixed types follow a lossless promotion order
  ([`zu_common_type()`](https://pedrobtz.github.io/zuint/reference/zu_common_type.md)),
  in arithmetic and in [`c()`](https://rdrr.io/r/base/c.html). A double
  must be integral and in range, unless
  `options(zuint.double = "allow")`.
- Comparison is exact across all types and doubles: `int64(1) == 1.5` is
  `FALSE`, and nothing is compared through double.
- The constructors read `0x` hex and `0b` binary as well as decimal,
  with an optional sign, `_` between digits and surrounding whitespace;
  `"NA"` and blank strings are `NA`. Exponents are not accepted.
- [`format_hex()`](https://pedrobtz.github.io/zuint/reference/format_hex.md)
  and
  [`format_bin()`](https://pedrobtz.github.io/zuint/reference/format_hex.md),
  with `pad = TRUE` for the full width;
  [`format()`](https://rdrr.io/r/base/format.html) takes `width` and
  `big.mark`; [`print()`](https://rdrr.io/r/base/print.html) stops at
  `getOption("max.print")`.
- Bit operations:
  [`bit_and()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`bit_or()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`bit_xor()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`bit_not()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`shift_left()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`shift_right()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`popcount()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md),
  [`clz()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md)
  and
  [`ctz()`](https://pedrobtz.github.io/zuint/reference/zuint-bits.md).
- With zuarrow installed, zuint registers its four types with zuarrow’s
  registry, so
  [`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html),
  [`zuarrow::arrow_read()`](https://pedrobtz.github.io/zuarrow/reference/arrow_read.html)
  and
  [`zuarrow::arrow_array()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html)
  read and write `int64`, `uint64` and DuckDB’s `arrow.opaque`
  `hugeint`/`uhugeint` exactly (`?zuint-arrow`). A value equal to a
  type’s `NA` bit pattern follows zuarrow’s `lossy` policy: an error by
  default, `NA` with a warning under `lossy = "warn"`.
- The Arrow and DuckDB functions of the development versions are gone,
  each replaced by zuarrow:
  - `zu_from_arrow()` and `zu_to_arrow()`:
    [`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html)
    and
    [`zuarrow::arrow_array()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html).
    `decimal128(p, 0)` reads as `int128` with `to = int128()`; the
    `decimal = TRUE` export has no replacement.
  - `zu_sentinel_check()`: the `zuarrow_lossy_error` that
    [`zuarrow::arrow_to_r()`](https://pedrobtz.github.io/zuarrow/reference/arrow_to_r.html)
    raises.
  - `zu_duckdb_query()`:
    `zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, sql))` after
    `SET arrow_lossless_conversion = true`.
  - `zu_duckdb_register()`, `zu_arrow_table()` and
    `zu_from_arrow_table()`:
    [`zuarrow::arrow_stream()`](https://pedrobtz.github.io/zuarrow/reference/arrow_array.html),
    [`zuarrow::arrow_write()`](https://pedrobtz.github.io/zuarrow/reference/arrow_write.html)
    and
    [`zuarrow::arrow_read()`](https://pedrobtz.github.io/zuarrow/reference/arrow_read.html).
  - The nanoarrow methods (`convert_array()`, `as_nanoarrow_array()`,
    `infer_nanoarrow_schema()`) and the arrow methods
    (`as_arrow_array()`, `infer_type()`): zuarrow, which reads and
    writes nanoarrow handles.
- [`zu_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
  and
  [`zu_from_storage()`](https://pedrobtz.github.io/zuint/reference/zu_storage.md)
  document the payload shapes and `NA` bit patterns as the public
  representation contract.
- [`as_integer64()`](https://pedrobtz.github.io/zuint/reference/as_integer64.md)
  returns a plain bit64 `integer64`.
- [`sort()`](https://rdrr.io/r/base/sort.html), and base
  [`order()`](https://rdrr.io/r/base/order.html) and
  [`rank()`](https://rdrr.io/r/base/rank.html) through an exact
  [`xtfrm()`](https://rdrr.io/r/base/xtfrm.html), with a stable radix
  sort; [`unique()`](https://rdrr.io/r/base/unique.html),
  [`duplicated()`](https://rdrr.io/r/base/duplicated.html) and
  [`anyDuplicated()`](https://rdrr.io/r/base/duplicated.html) with an
  exact hash; [`match()`](https://rdrr.io/r/base/match.html), `%in%` and
  [`table()`](https://rdrr.io/r/base/table.html) compare exact values,
  and
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  and `%zin%` do it faster.
- [`sum()`](https://rdrr.io/r/base/sum.html) is type stable and exact,
  `NA` with a warning when the total does not fit;
  [`prod()`](https://rdrr.io/r/base/prod.html),
  [`cumsum()`](https://rdrr.io/r/base/cumsum.html),
  [`cumprod()`](https://rdrr.io/r/base/cumsum.html),
  [`cummax()`](https://rdrr.io/r/base/cumsum.html) and
  [`cummin()`](https://rdrr.io/r/base/cumsum.html);
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html) and
  [`range()`](https://rdrr.io/r/base/range.html) are exact;
  [`mean()`](https://rdrr.io/r/base/mean.html) and
  [`median()`](https://rdrr.io/r/stats/median.html) are doubles from the
  exact values; [`diff()`](https://rdrr.io/r/base/diff.html) and
  [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md).
- [`summary()`](https://rdrr.io/r/base/summary.html) adds the median and
  the mean.
- [`rep()`](https://rdrr.io/r/base/rep.html) of an empty vector pads
  with the type’s `NA`
  ([\#55](https://github.com/pedrobtz/zuint/issues/55));
  [`range()`](https://rdrr.io/r/base/range.html) takes `finite`, which
  drops `NA` ([\#56](https://github.com/pedrobtz/zuint/issues/56));
  under `options(zuint.double = "allow")`,
  [`sum()`](https://rdrr.io/r/base/sum.html),
  [`prod()`](https://rdrr.io/r/base/prod.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html),
  [`max()`](https://rdrr.io/r/base/Extremes.html) and
  [`range()`](https://rdrr.io/r/base/range.html) give base R’s double
  answer ([\#60](https://github.com/pedrobtz/zuint/issues/60));
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  and `%zin%` treat a value the common type cannot hold as no match, as
  [`match()`](https://rdrr.io/r/base/match.html) does
  ([\#58](https://github.com/pedrobtz/zuint/issues/58));
  [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md)
  counts in the elements’ own type, so it reaches the top of the
  unsigned ranges ([\#59](https://github.com/pedrobtz/zuint/issues/59)).
- The Arrow import refuses a schema whose format is not the array’s own
  (`zuint_arrow_error`), which would have read past the data
  ([\#61](https://github.com/pedrobtz/zuint/issues/61)).
- A C table for other packages, `zuint_api_v1` in
  `inst/include/zuint.h`, resolved through `zuint-r.h`: DuckDB’s
  fixed-point `DECIMAL(p, s)` on a 128-bit coefficient (parse, format,
  rescale, compare, and conversion to and from double, each as DuckDB
  2.0.1 does it, with two of DuckDB’s bugs fixed), and checked 128-bit
  arithmetic. `zuint.h` includes no R header, and every member is safe
  on any thread ([\#103](https://github.com/pedrobtz/zuint/issues/103)).
- [`decimal128()`](https://pedrobtz.github.io/zuint/reference/decimal128.md)
  holds DuckDB’s `DECIMAL(p, s)` exactly, with
  [`is_decimal128()`](https://pedrobtz.github.io/zuint/reference/decimal128.md),
  [`decimal_precision()`](https://pedrobtz.github.io/zuint/reference/decimal128.md)
  and
  [`decimal_scale()`](https://pedrobtz.github.io/zuint/reference/decimal128.md).
  `+`, `-`, `*`, [`round()`](https://rdrr.io/r/base/Round.html),
  [`floor()`](https://rdrr.io/r/base/Round.html),
  [`ceiling()`](https://rdrr.io/r/base/Round.html),
  [`trunc()`](https://rdrr.io/r/base/Round.html),
  [`cumsum()`](https://rdrr.io/r/base/cumsum.html),
  [`c()`](https://rdrr.io/r/base/c.html), `x[i] <- value` and vctrs give
  DuckDB’s result types, and only
  [`decimal128()`](https://pedrobtz.github.io/zuint/reference/decimal128.md)
  rounds a value into one; comparison is exact across scales and with
  any integer or double; [`match()`](https://rdrr.io/r/base/match.html),
  `%in%` and
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  find equal values whatever their scales; `/`,
  [`mean()`](https://rdrr.io/r/base/mean.html) and the other `Math`
  functions give doubles; and sorting, hashing,
  [`sum()`](https://rdrr.io/r/base/sum.html),
  [`min()`](https://rdrr.io/r/base/Extremes.html) and
  [`max()`](https://rdrr.io/r/base/Extremes.html) work on the
  coefficients ([\#104](https://github.com/pedrobtz/zuint/issues/104),
  [\#108](https://github.com/pedrobtz/zuint/issues/108) to
  [\#129](https://github.com/pedrobtz/zuint/issues/129)).
- With vctrs, dplyr and tibble: zuint columns combine by the promotion
  order, cast exactly, arrange, group, summarise, bind and print.
  data.table keys on `int64` natively.
- [`zu_ifelse()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
  and
  [`zu_vapply()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
  keep the type where [`ifelse()`](https://rdrr.io/r/base/ifelse.html)
  and [`vapply()`](https://rdrr.io/r/base/lapply.html) would read raw
  bits. [`unique()`](https://rdrr.io/r/base/unique.html) drops names, as
  base R’s does.
- A getting-started vignette, and benchmarks against bit64 in the
  README.
- [`mean()`](https://rdrr.io/r/base/mean.html) and
  [`median()`](https://rdrr.io/r/stats/median.html) of every type,
  decimals included, are the exact mean rounded once to the nearest
  double; they had rounded the sum first, so a mean could lie above
  [`max()`](https://rdrr.io/r/base/Extremes.html)
  ([\#148](https://github.com/pedrobtz/zuint/issues/148)).
- DuckDB’s `arrow.opaque` extension is recognised by reading its JSON as
  DuckDB does: the top-level `vendor_name` must be `"DuckDB"` and the
  top-level `type_name` `"hugeint"` or `"uhugeint"`, escapes decoded.
  Another vendor’s type, or a `type_name` nested deeper, no longer reads
  as `int128`, and DuckDB’s own metadata with the keys in another order
  or written with escapes no longer reads as raw bytes. A decimal under
  any other `arrow.opaque` type no longer reads as `int128`
  ([\#154](https://github.com/pedrobtz/zuint/issues/154)).
- `to = int64()` and `to = uint64()` read 8-, 16- and 32-bit integer
  columns exactly: `-2147483648` had been lost as R’s `NA_integer_`
  ([\#155](https://github.com/pedrobtz/zuint/issues/155)).
- The Arrow decimal format `d:P,S` is read in the specification’s form
  only: a precision or scale past `INT_MAX` no longer wraps into range,
  and signs and spaces are refused
  ([\#156](https://github.com/pedrobtz/zuint/issues/156)).
- Errors about an Arrow schema are `zuint_arrow_error`, and a schema
  with more than 4096 metadata entries is one too, where a DuckDB
  `HUGEINT` column had silently read as raw bytes
  ([\#166](https://github.com/pedrobtz/zuint/issues/166)).
- A plain bit64 `integer64` operand is read by its values when bit64 is
  not loaded: in `&`, `|` and
  [`xor()`](https://rdrr.io/r/base/Logic.html),
  [`zu_match()`](https://pedrobtz.github.io/zuint/reference/zu_match.md)
  and `%zin%`,
  [`zu_ifelse()`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)’s
  `test`,
  [`checked_idiv()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md)
  and
  [`checked_mod()`](https://pedrobtz.github.io/zuint/reference/zuint-arith.md),
  [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md)’s
  `by`, [`round()`](https://rdrr.io/r/base/Round.html)’s `digits`,
  comparisons and `&` with a `decimal128`, and vctrs casts to every
  zuint type. Base R had read its bits, where `-1` is `NA` and `NA` is a
  value ([\#150](https://github.com/pedrobtz/zuint/issues/150)).
- With bit64 attached, `integer64 * uint64`, `/`, `^` and assigning a
  uint64 into an `integer64` are exact: bit64 had computed on the
  uint64’s bits ([\#151](https://github.com/pedrobtz/zuint/issues/151)).
- [`Conj()`](https://rdrr.io/r/base/complex.html),
  [`Re()`](https://rdrr.io/r/base/complex.html),
  [`Im()`](https://rdrr.io/r/base/complex.html),
  [`Mod()`](https://rdrr.io/r/base/complex.html) and
  [`Arg()`](https://rdrr.io/r/base/complex.html) are a
  `zuint_unsupported_error` for every type, where they had computed on
  the payload and kept the class
  ([\#152](https://github.com/pedrobtz/zuint/issues/152)).
- A zuint or `integer64` count is read as the number it stands for, as
  an index is: [`rep()`](https://rdrr.io/r/base/rep.html)’s `times`,
  `each` and `length.out`,
  [`diff()`](https://rdrr.io/r/base/diff.html)’s `lag` and
  `differences`, [`head()`](https://rdrr.io/r/utils/head.html) and
  [`tail()`](https://rdrr.io/r/utils/head.html), `length<-`,
  [`seq_zu()`](https://pedrobtz.github.io/zuint/reference/seq_zu.md)’s
  and [`seq()`](https://rdrr.io/r/base/seq.html)’s `length.out`, and
  [`format()`](https://rdrr.io/r/base/format.html)’s `width`,
  [`print()`](https://rdrr.io/r/base/print.html)’s `max` and
  [`str()`](https://rdrr.io/r/utils/str.html)’s `vec.len`
  ([\#153](https://github.com/pedrobtz/zuint/issues/153)).
- `%*%`, and from R 4.4.0
  [`crossprod()`](https://rdrr.io/r/base/crossprod.html) and
  [`tcrossprod()`](https://rdrr.io/r/base/crossprod.html), are a
  `zuint_unsupported_error` for every type, with or without bit64; for
  int64 the answer had depended on whether bit64 was loaded.
  [`matrix()`](https://rdrr.io/r/base/matrix.html),
  [`array()`](https://rdrr.io/r/base/array.html),
  [`outer()`](https://rdrr.io/r/base/outer.html) and
  [`diag()`](https://rdrr.io/r/base/diag.html) cannot be intercepted, as
  [`?zu_ifelse`](https://pedrobtz.github.io/zuint/reference/zu_ifelse.md)
  says ([\#160](https://github.com/pedrobtz/zuint/issues/160)).
- With bit64 attached, its
  [`setdiff()`](https://rdrr.io/r/base/sets.html),
  [`union()`](https://rdrr.io/r/base/sets.html),
  [`intersect()`](https://rdrr.io/r/base/sets.html),
  [`is.element()`](https://rdrr.io/r/base/sets.html) and
  [`setequal()`](https://rdrr.io/r/base/sets.html) work on int64: zuint
  declares `zu_int64` a subclass of `integer64` for
  [`methods::as()`](https://rdrr.io/r/methods/as.html)
  ([\#161](https://github.com/pedrobtz/zuint/issues/161)).
- [`abs()`](https://rdrr.io/r/base/MathFun.html),
  [`sign()`](https://rdrr.io/r/base/sign.html), the other `Math`
  functions computed in double, `!`, `&`, `|` and the double fallback of
  `options(zuint.double = "allow")` in arithmetic, `^` and
  [`c()`](https://rdrr.io/r/base/c.html) keep names, as base R does
  ([\#164](https://github.com/pedrobtz/zuint/issues/164)).
