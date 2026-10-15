/*
 * zu_wide.h -- the four zuint types over zufast/wide.h (design 4, 10).
 *
 * Storage (design 4, plain storage until the ALTREP views):
 *   ZU_INT64   REALSXP, each double's bits an int64_t   NA = INT64_MIN
 *   ZU_UINT64  REALSXP, each double's bits a uint64_t   NA = UINT64_MAX
 *   ZU_INT128  CPLXSXP, re = low word, im = high word   NA = INT128_MIN
 *   ZU_UINT128 CPLXSXP, as ZU_INT128                    NA = UINT128_MAX
 *
 * Bits move between doubles and integers with memcpy only, never through a
 * floating-point conversion, so NaN payloads survive.
 *
 * zu_val is the common currency for code that is not hot: a sign and a
 * 128-bit magnitude. `neg` is never set on a zero magnitude, so comparing
 * two values is comparing (neg, mag).
 */
#ifndef ZUINT_WIDE_H
#define ZUINT_WIDE_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <zufast/wide.h>

typedef enum { ZU_INT64 = 1, ZU_UINT64 = 2, ZU_INT128 = 3, ZU_UINT128 = 4 } zu_type;

typedef struct {
    bool na;
    bool neg;
    zuf_u128 mag;
} zu_val;

#define ZU_SIGN64 (UINT64_C(1) << 63)

static inline bool zu_type_is_128(zu_type t) { return t == ZU_INT128 || t == ZU_UINT128; }
static inline bool zu_type_is_signed(zu_type t) { return t == ZU_INT64 || t == ZU_INT128; }

/* A type code from R, checked. */
static inline zu_type zu_type_arg(SEXP type)
{
    int t = Rf_asInteger(type);
    if (t < ZU_INT64 || t > ZU_UINT128) Rf_error("zuint: invalid type code %d", t);
    return (zu_type)t;
}

static inline SEXPTYPE zu_sexptype(zu_type t) { return zu_type_is_128(t) ? CPLXSXP : REALSXP; }

/* The payload of `t`, checked against its storage type. */
static inline void zu_check_payload(SEXP x, zu_type t)
{
    if (TYPEOF(x) != zu_sexptype(t)) Rf_error("zuint: corrupt payload for type %d", (int)t);
}

/* ---- raw words ---------------------------------------------------------- */

static inline uint64_t zu_get64(const double *p, R_xlen_t i)
{
    uint64_t v;
    memcpy(&v, p + i, sizeof v);
    return v;
}

static inline void zu_set64(double *p, R_xlen_t i, uint64_t v) { memcpy(p + i, &v, sizeof v); }

static inline zuf_u128 zu_get128(const Rcomplex *p, R_xlen_t i)
{
    uint64_t low, high;
    memcpy(&low, &p[i].r, sizeof low);
    memcpy(&high, &p[i].i, sizeof high);
    return zuf_u128_make(high, low);
}

static inline void zu_set128(Rcomplex *p, R_xlen_t i, zuf_u128 v)
{
    uint64_t low = zuf_u128_low(v), high = zuf_u128_high(v);
    memcpy(&p[i].r, &low, sizeof low);
    memcpy(&p[i].i, &high, sizeof high);
}

/* The NA bit pattern of each type, as raw words. */
static inline uint64_t zu_na64(zu_type t) { return t == ZU_INT64 ? ZU_SIGN64 : ~UINT64_C(0); }

static inline zuf_u128 zu_na128(zu_type t)
{
    return t == ZU_INT128 ? zuf_u128_make(ZU_SIGN64, 0) : zuf_u128_make(~UINT64_C(0), ~UINT64_C(0));
}

static inline void zu_set_na(SEXP x, zu_type t, R_xlen_t i)
{
    if (zu_type_is_128(t)) zu_set128(COMPLEX(x), i, zu_na128(t));
    else zu_set64(REAL(x), i, zu_na64(t));
}

static inline bool zu_is_na(SEXP x, zu_type t, R_xlen_t i)
{
    if (zu_type_is_128(t)) {
        zuf_u128 v = zu_get128(COMPLEX(x), i), na = zu_na128(t);
        return zuf_u128_high(v) == zuf_u128_high(na) && zuf_u128_low(v) == zuf_u128_low(na);
    }
    return zu_get64(REAL(x), i) == zu_na64(t);
}

/* ---- zu_val ------------------------------------------------------------- */

static inline zu_val zu_val_na(void)
{
    zu_val v;
    v.na = true;
    v.neg = false;
    v.mag = zuf_u128_make(0, 0);
    return v;
}

static inline zu_val zu_val_make(bool neg, zuf_u128 mag)
{
    zu_val v;
    v.na = false;
    v.mag = mag;
    v.neg = neg && (zuf_u128_high(mag) | zuf_u128_low(mag)) != 0;
    return v;
}

static inline zuf_u128 zu_negate_bits(zuf_u128 v) { return zuf_u128_sub_wrap(zuf_u128_make(0, 0), v); }

/* Element i of a payload of type t. */
static inline zu_val zu_val_get(SEXP x, zu_type t, R_xlen_t i)
{
    if (zu_is_na(x, t, i)) return zu_val_na();
    switch (t) {
    case ZU_INT64: {
        uint64_t b = zu_get64(REAL(x), i);
        bool neg = (b & ZU_SIGN64) != 0;
        return zu_val_make(neg, zuf_u128_from_u64(neg ? UINT64_C(0) - b : b));
    }
    case ZU_UINT64:
        return zu_val_make(false, zuf_u128_from_u64(zu_get64(REAL(x), i)));
    case ZU_INT128: {
        zuf_u128 b = zu_get128(COMPLEX(x), i);
        bool neg = (zuf_u128_high(b) & ZU_SIGN64) != 0;
        return zu_val_make(neg, neg ? zu_negate_bits(b) : b);
    }
    case ZU_UINT128:
    default:
        return zu_val_make(false, zu_get128(COMPLEX(x), i));
    }
}

/* Does v fit type t, the NA sentinel excluded? */
static inline bool zu_val_fits(zu_val v, zu_type t)
{
    uint64_t high = zuf_u128_high(v.mag), low = zuf_u128_low(v.mag);
    switch (t) {
    case ZU_INT64:   /* |v| <= 2^63 - 1 */
        return high == 0 && low < ZU_SIGN64;
    case ZU_UINT64:  /* 0 <= v <= 2^64 - 2 */
        return !v.neg && high == 0 && low != ~UINT64_C(0);
    case ZU_INT128:  /* |v| <= 2^127 - 1 */
        return high < ZU_SIGN64;
    case ZU_UINT128: /* 0 <= v <= 2^128 - 2 */
    default:
        return !v.neg && !(high == ~UINT64_C(0) && low == ~UINT64_C(0));
    }
}

/* Store v at i; NA when v is NA or does not fit. Returns false only when a
   non-NA value did not fit. */
static inline bool zu_val_put(SEXP x, zu_type t, R_xlen_t i, zu_val v)
{
    if (v.na) { zu_set_na(x, t, i); return true; }
    if (!zu_val_fits(v, t)) { zu_set_na(x, t, i); return false; }
    if (zu_type_is_128(t)) {
        zu_set128(COMPLEX(x), i, v.neg ? zu_negate_bits(v.mag) : v.mag);
    } else {
        uint64_t low = zuf_u128_low(v.mag);
        zu_set64(REAL(x), i, v.neg ? UINT64_C(0) - low : low);
    }
    return true;
}

/* -1, 0 or 1; both arguments non-NA. */
static inline int zu_val_cmp(zu_val a, zu_val b)
{
    if (a.neg != b.neg) return a.neg ? -1 : 1;
    int c = zuf_u128_cmp(a.mag, b.mag);
    return a.neg ? -c : c;
}

SEXP zu_alloc(zu_type t, R_xlen_t n);

#endif /* ZUINT_WIDE_H */
