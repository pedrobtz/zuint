## New submission

This is the first submission of zuint.

zuint needs zufast (>= 0.1.1) through `LinkingTo` for its 128-bit
arithmetic, and suggests zuarrow for the Arrow bridge; both are by the
same maintainer and are on CRAN.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

R CMD check --as-cran on GitHub Actions, through the shared workflows of
https://github.com/pedrobtz/r-actions:

* macOS (latest), R release
* Windows (latest), R release and R-devel
* Ubuntu (latest), R release and R oldrel-1
* R-devel containers matching CRAN's compilers: clang23, ubuntu-clang,
  ubuntu-gcc16
* R-devel with only the hard dependencies installed (R-hub nosuggests,
  CRAN's NOSUGGESTS flavor)
* R-devel built with `--disable-long-double` (R-hub nold, CRAN's NOLD
  flavor)
* Ubuntu, R release, built without `__int128` (zufast's portable fallback)

The compiled code is also checked under ASan and UBSan (gcc and clang),
valgrind, rchk, LTO, `gctorture(TRUE)` and the compilers' static
analysers.

## Method References

There are no published references describing the methods in this
package. It implements fixed-width integer arithmetic, conversion and
formatting, with the semantics of the integer and DECIMAL types of the
DuckDB database.

## Copyright

`src/vendor/arrow/abi.h` is the Arrow C Data Interface header from Apache
Arrow 26.0.0 (Apache-2.0), unmodified. The `dk_*` functions in
`src/zu_fixed.c` port DuckDB's VARCHAR to DECIMAL state machine (MIT).
Both copyright holders are in `Authors@R` as `cph`, and `inst/COPYRIGHTS`
gives the details.
