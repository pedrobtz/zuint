/*
 * zu_fixed.h -- fixed-point DECIMAL(p, s) on a 128-bit coefficient
 * (design 2.2).
 *
 * A value is a signed coefficient c with a precision p (1 to 38) and a
 * scale s (0 to p): the number c / 10^s, with |c| < 10^p. That is DuckDB's
 * DECIMAL, and every function here gives DuckDB 2.0.0's answer.
 *
 * This file and zu_fixed.c never include an R header and never call R:
 * the C test binary (tools/fixed/), the fuzz harness and other packages
 * (through zuint_api_v1, inst/include/zuint.h) run them without R, on any
 * thread. They read only constant tables and their arguments.
 *
 * Every function returns a status. On anything but ZU_FX_OK the
 * out-pointer is left as it was.
 */
#ifndef ZUINT_FIXED_H
#define ZUINT_FIXED_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <zufast/wide.h>

/* The same numbers as ZUINT_OK and ZUINT_ERR_* in inst/include/zuint.h. */
enum {
    ZU_FX_OK = 0,
    ZU_FX_OVERFLOW = -1, /* beyond 128 bits, or beyond the precision */
    ZU_FX_INVALID = -2,  /* text DuckDB refuses, or a NaN or infinite double */
    ZU_FX_TYPE = -3,     /* a precision outside 1..38, or a scale outside 0..p */
    ZU_FX_BUFFER = -4,   /* the output buffer is too small */
    ZU_FX_ARGUMENT = -5  /* a NULL pointer */
};

#define ZU_FX_MAX_PRECISION 38

/* The longest text zu_fx_format() writes, without a terminating NUL:
   a sign, 37 integer digits, '.' and one fractional digit, or a sign,
   "0." and 37 fractional digits. */
#define ZU_FX_MAX_CHARS 40

/* ZU_FX_OK when 1 <= p <= 38 and 0 <= s <= p, else ZU_FX_TYPE. */
int zu_fx_type_check(int p, int s);

/* ZU_FX_OK when |c| < 10^p, else ZU_FX_OVERFLOW. */
int zu_fx_fits(zuf_i128 c, int p);

/* DuckDB's cast from DECIMAL(_, s) to DECIMAL(p_to, s_to): multiply by a
   power of ten, or divide rounding half away from zero, then check that
   the result fits p_to digits. */
int zu_fx_rescale(zuf_i128 c, int s, int p_to, int s_to, zuf_i128 *out);

/* DuckDB's cast from VARCHAR to DECIMAL(p, s), for `len` bytes of `text`
   (no terminating NUL is needed or read). */
int zu_fx_parse(const char *text, size_t len, int p, int s, zuf_i128 *out);

/* DuckDB's cast from DECIMAL(p, s) to VARCHAR. Writes at most `cap` bytes
   to `buf`, without a NUL, and the length to *len. ZU_FX_BUFFER when `cap`
   is too small; ZU_FX_MAX_CHARS is always enough. */
int zu_fx_format(zuf_i128 c, int p, int s, char *buf, size_t cap, size_t *len);

/* DuckDB's cast from DECIMAL(p, s) to DOUBLE: c / 10^s rounded to the
   nearest double, ties to even. The one exception is DuckDB's: at scale 0
   with p > 18 it adds the two 64-bit halves as doubles, which can be one
   unit in the last place off, and this does the same. */
int zu_fx_to_double(zuf_i128 c, int p, int s, double *out);

/* DuckDB's cast from DOUBLE to DECIMAL(p, s): round(x * 1e<s>) in double
   arithmetic, half away from zero, refused at or beyond 1e<p>. */
int zu_fx_from_double(double x, int p, int s, zuf_i128 *out);

/* Sets *out to -1, 0 or 1 as a / 10^sa is less than, equal to or greater
   than b / 10^sb, exactly. */
int zu_fx_compare(zuf_i128 a, int sa, zuf_i128 b, int sb, int *out);

/* Checked 128-bit arithmetic on two coefficients. The caller has put a
   sum's operands on one scale; a product's scale is sa + sb. These check
   only the 128-bit range; zu_fx_fits() checks a precision. */
int zu_fx_add(zuf_i128 a, zuf_i128 b, zuf_i128 *out);
int zu_fx_sub(zuf_i128 a, zuf_i128 b, zuf_i128 *out);
int zu_fx_mul(zuf_i128 a, zuf_i128 b, zuf_i128 *out);

/* A static message for a status, or NULL for an unknown one. */
const char *zu_fx_strerror(int status);

#endif /* ZUINT_FIXED_H */
