/*
 * zu_arith.c -- vectorised arithmetic and comparison (design 5, 6).
 *
 * Arithmetic entry points take each operand either as a payload of the
 * result type or as R's integer or logical vector (kind 0), recycle them,
 * and return list(result, n_overflow). The policy decides what an overflow
 * stores: NA (default, R warns) or the wrapped value (wrapping_*). checked_*
 * runs as the default does and R turns a non-zero count into an error.
 *
 * Integers are read here rather than converted first, because a negative
 * integer meeting an unsigned type is part of the operation: it counts as an
 * overflow, or under wrapping becomes its value modulo 2^width. Converted to
 * a payload first, -1 would wrap onto the NA pattern and read as NA.
 *
 * Comparison takes the operands as they are, of any two kinds, and is exact:
 * it never converts through double, and a double is compared as the real
 * number it is.
 */
#include "zu_ops.h"
#include <math.h>

static SEXP zu_pair_n(SEXP value, R_xlen_t n)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)n));
    UNPROTECT(1);
    return out;
}

static zu_policy zu_policy_arg(SEXP p)
{
    int v = Rf_asInteger(p);
    if (v < ZU_POLICY_DEFAULT || v > ZU_POLICY_WRAP) Rf_error("zuint: invalid policy %d", v);
    return (zu_policy)v;
}

static R_xlen_t zu_recycled_length(R_xlen_t nx, R_xlen_t ny)
{
    return nx == 0 || ny == 0 ? 0 : (nx > ny ? nx : ny);
}

/* Store the outcome of one operation at i; returns 1 for an overflow. */
static inline int zu_store64(double *p, R_xlen_t i, zu_status s, uint64_t r, zu_type t, zu_policy pol)
{
    if (s == ZU_OK) { zu_set64(p, i, r); return 0; }
    if (s == ZU_OVERFLOW && pol == ZU_POLICY_WRAP) { zu_set64(p, i, r); return 0; }   /* a sentinel reads as NA */
    zu_set64(p, i, zu_na64(t));
    return s == ZU_OVERFLOW;
}

static inline int zu_store128(Rcomplex *p, R_xlen_t i, zu_status s, zuf_u128 r, zu_type t, zu_policy pol)
{
    if (s == ZU_OK) { zu_set128(p, i, r); return 0; }
    if (s == ZU_OVERFLOW && pol == ZU_POLICY_WRAP) { zu_set128(p, i, r); return 0; }
    zu_set128(p, i, zu_na128(t));
    return s == ZU_OVERFLOW;
}

/* Operand element i as the raw words of type t. */
typedef enum { ZU_RAW_OK = 0, ZU_RAW_NA = 1, ZU_RAW_LOST = 2 } zu_raw;

static void zu_check_operand(SEXP x, int kind, zu_type t)
{
    if (kind == 0) {
        if (TYPEOF(x) != INTSXP && TYPEOF(x) != LGLSXP) Rf_error("zuint: expected an integer vector");
    } else {
        if (kind != (int)t) Rf_error("zuint: operand kind %d does not match type %d", kind, (int)t);
        zu_check_payload(x, t);
    }
}

static inline zu_raw zu_raw_int(SEXP x, zu_type t, zu_policy pol, R_xlen_t i, int *v)
{
    *v = (TYPEOF(x) == INTSXP ? INTEGER(x) : LOGICAL(x))[i];
    if (*v == NA_INTEGER) return ZU_RAW_NA;
    if (*v < 0 && !zu_type_is_signed(t) && pol != ZU_POLICY_WRAP) return ZU_RAW_LOST;
    return ZU_RAW_OK;
}

static inline zu_raw zu_raw64(SEXP x, int kind, zu_type t, zu_policy pol, R_xlen_t i, uint64_t *out)
{
    if (kind == 0) {
        int v;
        zu_raw s = zu_raw_int(x, t, pol, i, &v);
        *out = zu_u64((int64_t)v);   /* sign-extended: two's complement, or 2^64 - |v| */
        return s;
    }
    *out = zu_get64(REAL(x), i);
    return *out == zu_na64(t) ? ZU_RAW_NA : ZU_RAW_OK;
}

static inline zu_raw zu_raw128(SEXP x, int kind, zu_type t, zu_policy pol, R_xlen_t i, zuf_u128 *out)
{
    if (kind == 0) {
        int v;
        zu_raw s = zu_raw_int(x, t, pol, i, &v);
        zuf_u128 m = zuf_u128_from_u64(v < 0 ? UINT64_C(0) - (uint64_t)(int64_t)v : (uint64_t)v);
        *out = v < 0 ? zu_negate_bits(m) : m;
        return s;
    }
    *out = zu_get128(COMPLEX(x), i);
    return zuf_u128_cmp(*out, zu_na128(t)) == 0 ? ZU_RAW_NA : ZU_RAW_OK;
}

SEXP zu_arith_c(SEXP op_, SEXP x, SEXP kx_, SEXP y, SEXP ky_, SEXP type_, SEXP policy_)
{
    zu_op op = (zu_op)Rf_asInteger(op_);
    zu_type t = zu_type_arg(type_);
    zu_policy pol = zu_policy_arg(policy_);
    int kx = Rf_asInteger(kx_), ky = Rf_asInteger(ky_);
    if (op < ZU_OP_ADD || op > ZU_OP_MOD) Rf_error("zuint: invalid operator %d", (int)op);
    zu_check_operand(x, kx, t);
    zu_check_operand(y, ky, t);
    R_xlen_t nx = XLENGTH(x), ny = XLENGTH(y), n = zu_recycled_length(nx, ny), ovf = 0;
    SEXP out = PROTECT(zu_alloc(t, n));

    for (R_xlen_t i = 0, ix = 0, iy = 0; i < n; i++) {
        zu_raw sa, sb;
        if (zu_type_is_128(t)) {
            zuf_u128 a, b, r;
            sa = zu_raw128(x, kx, t, pol, ix, &a);
            sb = zu_raw128(y, ky, t, pol, iy, &b);
            if (sa == ZU_RAW_NA || sb == ZU_RAW_NA) zu_set_na(out, t, i);
            else if (sa == ZU_RAW_LOST || sb == ZU_RAW_LOST) { zu_set_na(out, t, i); ovf++; }
            else ovf += zu_store128(COMPLEX(out), i, zu_op128(op, t, a, b, &r), r, t, pol);
        } else {
            uint64_t a, b, r;
            sa = zu_raw64(x, kx, t, pol, ix, &a);
            sb = zu_raw64(y, ky, t, pol, iy, &b);
            if (sa == ZU_RAW_NA || sb == ZU_RAW_NA) zu_set_na(out, t, i);
            else if (sa == ZU_RAW_LOST || sb == ZU_RAW_LOST) { zu_set_na(out, t, i); ovf++; }
            else ovf += zu_store64(REAL(out), i, zu_op64(op, t, a, b, &r), r, t, pol);
        }
        if (++ix == nx) ix = 0;
        if (++iy == ny) iy = 0;
    }
    out = zu_pair_n(out, ovf);
    UNPROTECT(1);
    return out;
}

SEXP zu_neg_c(SEXP x, SEXP type_, SEXP policy_)
{
    zu_type t = zu_type_arg(type_);
    zu_policy pol = zu_policy_arg(policy_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), ovf = 0;
    SEXP out = PROTECT(zu_alloc(t, n));
    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) { zu_set_na(out, t, i); continue; }
        if (zu_type_is_128(t)) {
            zuf_u128 r;
            zu_status s = zu_neg128(t, zu_get128(COMPLEX(x), i), &r);
            ovf += zu_store128(COMPLEX(out), i, s, r, t, pol);
        } else {
            uint64_t r;
            zu_status s = zu_neg64(t, zu_get64(REAL(x), i), &r);
            ovf += zu_store64(REAL(out), i, s, r, t, pol);
        }
    }
    out = zu_pair_n(out, ovf);
    UNPROTECT(1);
    return out;
}

/* abs() and sign() of each value, in the same type; neither can overflow,
   because the signed ranges are symmetric. */
SEXP zu_abs_sign_c(SEXP x, SEXP type_, SEXP sign_)
{
    zu_type t = zu_type_arg(type_);
    bool sign = Rf_asLogical(sign_) == TRUE;
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(zu_alloc(t, n));
    for (R_xlen_t i = 0; i < n; i++) {
        zu_val v = zu_val_get(x, t, i);
        if (!v.na) {
            bool zero = (zuf_u128_high(v.mag) | zuf_u128_low(v.mag)) == 0;
            v = sign ? zu_val_make(v.neg, zuf_u128_from_u64(zero ? 0 : 1)) : zu_val_make(false, v.mag);
        }
        zu_val_put(out, t, i, v);
    }
    UNPROTECT(1);
    return out;
}

/* ---- power -------------------------------------------------------------- */

static zu_status zu_mul_any(zu_type t, zuf_u128 a, zuf_u128 b, zuf_u128 *r)
{
    if (zu_type_is_128(t)) return zu_op128(ZU_OP_MUL, t, a, b, r);
    uint64_t r64;
    zu_status s = zu_op64(ZU_OP_MUL, t, zuf_u128_low(a), zuf_u128_low(b), &r64);
    *r = zuf_u128_from_u64(r64);
    return s;
}

/* a^e by squaring, e >= 0. Under the default policy the first overflow
   ends it; under wrapping every product wraps, which is exact modular
   exponentiation. A squaring overflow matters only while exponent bits
   remain, and then the result would overflow too (|a| >= 2). */
static zu_status zu_pow_one(zu_type t, zuf_u128 a, zuf_u128 e, zu_policy pol, zuf_u128 *out)
{
    zuf_u128 result = zuf_u128_from_u64(1), base = a;
    bool ovf = false;
    while ((zuf_u128_high(e) | zuf_u128_low(e)) != 0) {
        if (zuf_u128_low(e) & 1) {
            if (zu_mul_any(t, result, base, &result) == ZU_OVERFLOW) {
                ovf = true;
                if (pol != ZU_POLICY_WRAP) break;
            }
        }
        e = zuf_int_u128_shr(e, 1);
        if ((zuf_u128_high(e) | zuf_u128_low(e)) != 0 && zu_mul_any(t, base, base, &base) == ZU_OVERFLOW) {
            ovf = true;
            if (pol != ZU_POLICY_WRAP) break;
        }
    }
    *out = result;
    if (ovf) return ZU_OVERFLOW;
    if (zu_type_is_128(t)) return zuf_u128_cmp(result, zu_na128(t)) == 0 ? ZU_OVERFLOW : ZU_OK;
    return zuf_u128_low(result) == zu_na64(t) ? ZU_OVERFLOW : ZU_OK;
}

/* x^e: x of type t (a payload, or an integer vector with kx 0) and e a
   uint128 payload of non-negative exponents. */
SEXP zu_pow_c(SEXP x, SEXP kx_, SEXP e, SEXP type_, SEXP policy_)
{
    zu_type t = zu_type_arg(type_);
    zu_policy pol = zu_policy_arg(policy_);
    int kx = Rf_asInteger(kx_);
    zu_check_operand(x, kx, t);
    zu_check_payload(e, ZU_UINT128);
    R_xlen_t nx = XLENGTH(x), ne = XLENGTH(e), n = zu_recycled_length(nx, ne), ovf = 0;
    SEXP out = PROTECT(zu_alloc(t, n));
    zuf_u128 ena = zu_na128(ZU_UINT128);
    for (R_xlen_t i = 0, ix = 0, ie = 0; i < n; i++) {
        zuf_u128 ev = zu_get128(COMPLEX(e), ie), a, r;
        zu_raw sa;
        if (zu_type_is_128(t)) {
            sa = zu_raw128(x, kx, t, pol, ix, &a);
        } else {
            uint64_t a64;
            sa = zu_raw64(x, kx, t, pol, ix, &a64);
            a = zuf_u128_from_u64(a64);
        }
        if (sa == ZU_RAW_NA || zuf_u128_cmp(ev, ena) == 0) {
            zu_set_na(out, t, i);
        } else if (sa == ZU_RAW_LOST) {
            zu_set_na(out, t, i);
            ovf++;
        } else if (zu_type_is_128(t)) {
            zu_status s = zu_pow_one(t, a, ev, pol, &r);
            ovf += zu_store128(COMPLEX(out), i, s, r, t, pol);
        } else {
            zu_status s = zu_pow_one(t, a, ev, pol, &r);
            ovf += zu_store64(REAL(out), i, s, zuf_u128_low(r), t, pol);
        }
        if (++ix == nx) ix = 0;
        if (++ie == ne) ie = 0;
    }
    out = zu_pair_n(out, ovf);
    UNPROTECT(1);
    return out;
}

/* ---- comparison --------------------------------------------------------- */

/* Operand kinds, as for zu_cast_c(). */
#define ZU_KIND_INT  0
#define ZU_KIND_DBL (-1)

typedef enum { ZU_CMP_EQ = 1, ZU_CMP_NE, ZU_CMP_LT, ZU_CMP_LE, ZU_CMP_GT, ZU_CMP_GE } zu_cmp_op;

typedef struct {
    bool na, is_dbl;
    zu_val v;   /* when !is_dbl */
    double d;   /* when is_dbl */
} zu_operand;

static zu_operand zu_operand_get(SEXP x, int kind, R_xlen_t i)
{
    zu_operand o;
    o.is_dbl = false;
    o.d = 0;
    if (kind == ZU_KIND_DBL) {
        o.is_dbl = true;
        o.d = REAL(x)[i];
        o.na = ISNAN(o.d);
        o.v = zu_val_na();
    } else if (kind == ZU_KIND_INT) {
        int v = (TYPEOF(x) == INTSXP ? INTEGER(x) : LOGICAL(x))[i];
        o.na = v == NA_INTEGER;
        o.v = o.na ? zu_val_na()
                   : zu_val_make(v < 0, zuf_u128_from_u64(v < 0 ? UINT64_C(0) - (uint64_t)(int64_t)v : (uint64_t)v));
    } else {
        o.v = zu_val_get(x, (zu_type)kind, i);
        o.na = o.v.na;
    }
    return o;
}

/* sign(v - d) for a finite or infinite d. floor(d) is an integer double;
   if it is within 128 bits it converts exactly, else its sign decides. A
   d with a fraction lies strictly between floor(d) and floor(d) + 1. */
static int zu_cmp_val_dbl(zu_val v, double d)
{
    double f = floor(d);
    zuf_u128 m;
    int c;
    if (isinf(f) || fabs(f) >= 0x1p128) return f > 0 ? -1 : 1;
    if (!zuf_u128_from_f64(fabs(f), &m)) return f > 0 ? -1 : 1;   /* unreachable: f is integral and in range */
    c = zu_val_cmp(v, zu_val_make(f < 0, m));
    if (c != 0 || f == d) return c;
    return -1;   /* v == floor(d) < d */
}

static int zu_operand_cmp(zu_operand a, zu_operand b)
{
    if (!a.is_dbl && !b.is_dbl) return zu_val_cmp(a.v, b.v);
    if (!a.is_dbl) return zu_cmp_val_dbl(a.v, b.d);
    if (!b.is_dbl) return -zu_cmp_val_dbl(b.v, a.d);
    return (a.d > b.d) - (a.d < b.d);
}

static void zu_check_kind(SEXP x, int kind)
{
    if (kind == ZU_KIND_DBL) {
        if (TYPEOF(x) != REALSXP) Rf_error("zuint: expected a double vector");
    } else if (kind == ZU_KIND_INT) {
        if (TYPEOF(x) != INTSXP && TYPEOF(x) != LGLSXP) Rf_error("zuint: expected an integer vector");
    } else {
        if (kind < ZU_INT64 || kind > ZU_UINT128) Rf_error("zuint: invalid operand kind %d", kind);
        zu_check_payload(x, (zu_type)kind);
    }
}

SEXP zu_compare_c(SEXP op_, SEXP x, SEXP kx_, SEXP y, SEXP ky_)
{
    zu_cmp_op op = (zu_cmp_op)Rf_asInteger(op_);
    int kx = Rf_asInteger(kx_), ky = Rf_asInteger(ky_);
    if (op < ZU_CMP_EQ || op > ZU_CMP_GE) Rf_error("zuint: invalid comparison %d", (int)op);
    zu_check_kind(x, kx);
    zu_check_kind(y, ky);
    R_xlen_t nx = XLENGTH(x), ny = XLENGTH(y), n = zu_recycled_length(nx, ny);
    SEXP out = PROTECT(Rf_allocVector(LGLSXP, n));
    int *po = LOGICAL(out);
    for (R_xlen_t i = 0, ix = 0, iy = 0; i < n; i++) {
        zu_operand a = zu_operand_get(x, kx, ix), b = zu_operand_get(y, ky, iy);
        if (a.na || b.na) {
            po[i] = NA_LOGICAL;
        } else {
            int c = zu_operand_cmp(a, b);
            switch (op) {
            case ZU_CMP_EQ: po[i] = c == 0; break;
            case ZU_CMP_NE: po[i] = c != 0; break;
            case ZU_CMP_LT: po[i] = c < 0; break;
            case ZU_CMP_LE: po[i] = c <= 0; break;
            case ZU_CMP_GT: po[i] = c > 0; break;
            case ZU_CMP_GE: po[i] = c >= 0; break;
            }
        }
        if (++ix == nx) ix = 0;
        if (++iy == ny) iy = 0;
    }
    UNPROTECT(1);
    return out;
}
