/*
 * zu_bits.c -- bit operations (design 6) on the two's complement bits of
 * each type's full width. A result whose bits are the NA pattern is out of
 * range and counts as an overflow, as in arithmetic. Shifts by a negative
 * amount or by the width or more give NA.
 */
#include "zu_wide.h"

typedef enum { ZU_BIT_AND = 1, ZU_BIT_OR, ZU_BIT_XOR, ZU_BIT_NOT, ZU_SHL, ZU_SHR } zu_bitop;

static SEXP zu_pair_bits(SEXP value, R_xlen_t n)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)n));
    UNPROTECT(1);
    return out;
}

static R_xlen_t zu_len2(R_xlen_t a, R_xlen_t b) { return a == 0 || b == 0 ? 0 : (a > b ? a : b); }

/* Logical shift left, logical shift right, or arithmetic shift right of the
   raw words of type t by s in 0..width-1. */
static zuf_u128 zu_shift(zuf_u128 v, zu_type t, zu_bitop op, unsigned s)
{
    if (zu_type_is_128(t)) {
        if (op == ZU_SHL) return zuf_int_u128_shl(v, s);
        zuf_u128 r = zuf_int_u128_shr(v, s);
        if (t == ZU_INT128 && (zuf_u128_high(v) & ZU_SIGN64) && s > 0) {
            /* fill the vacated high bits with the sign */
            zuf_u128 ones = zuf_u128_make(~UINT64_C(0), ~UINT64_C(0));
            zuf_u128 fill = zuf_int_u128_shl(ones, 128 - s);
            r = zuf_u128_make(zuf_u128_high(r) | zuf_u128_high(fill), zuf_u128_low(r) | zuf_u128_low(fill));
        }
        return r;
    }
    uint64_t w = zuf_u128_low(v), r;
    if (op == ZU_SHL) r = w << s;
    else {
        r = w >> s;
        if (t == ZU_INT64 && (w & ZU_SIGN64) && s > 0) r |= ~UINT64_C(0) << (64 - s);
    }
    return zuf_u128_from_u64(r);
}

static zuf_u128 zu_raw(SEXP x, zu_type t, R_xlen_t i)
{
    return zu_type_is_128(t) ? zu_get128(COMPLEX(x), i) : zuf_u128_from_u64(zu_get64(REAL(x), i));
}

/* Store raw words; the NA pattern counts as an overflow. */
static int zu_put_raw(SEXP out, zu_type t, R_xlen_t i, zuf_u128 r)
{
    if (zu_type_is_128(t)) {
        zu_set128(COMPLEX(out), i, r);
        return zuf_u128_cmp(r, zu_na128(t)) == 0;
    }
    zu_set64(REAL(out), i, zuf_u128_low(r));
    return zuf_u128_low(r) == zu_na64(t);
}

/* x op y for and, or, xor (y a payload of type t), x op n for the shifts (n
   an integer vector), and not x (y ignored). */
SEXP zu_bitop_c(SEXP op_, SEXP x, SEXP y, SEXP type_)
{
    zu_bitop op = (zu_bitop)Rf_asInteger(op_);
    zu_type t = zu_type_arg(type_);
    unsigned width = zu_type_is_128(t) ? 128 : 64;
    zu_check_payload(x, t);
    if (op == ZU_SHL || op == ZU_SHR) {
        if (TYPEOF(y) != INTSXP) Rf_error("zuint: shift amounts must be integers");
    } else if (op != ZU_BIT_NOT) {
        zu_check_payload(y, t);
    } else {
        y = x;
    }
    if (op < ZU_BIT_AND || op > ZU_SHR) Rf_error("zuint: invalid bit operation %d", (int)op);
    R_xlen_t nx = XLENGTH(x), ny = XLENGTH(y), n = zu_len2(nx, ny), ovf = 0;
    SEXP out = PROTECT(zu_alloc(t, n));
    for (R_xlen_t i = 0, ix = 0, iy = 0; i < n; i++) {
        if (zu_is_na(x, t, ix)) {
            zu_set_na(out, t, i);
        } else if (op == ZU_SHL || op == ZU_SHR) {
            int s = INTEGER(y)[iy];
            if (s == NA_INTEGER || s < 0 || (unsigned)s >= width) zu_set_na(out, t, i);
            else if (zu_put_raw(out, t, i, zu_shift(zu_raw(x, t, ix), t, op, (unsigned)s))) { zu_set_na(out, t, i); ovf++; }
        } else if (op != ZU_BIT_NOT && zu_is_na(y, t, iy)) {
            zu_set_na(out, t, i);
        } else {
            zuf_u128 a = zu_raw(x, t, ix), b = zu_raw(y, t, iy), r;
            uint64_t h, l;
            switch (op) {
            case ZU_BIT_AND: h = zuf_u128_high(a) & zuf_u128_high(b); l = zuf_u128_low(a) & zuf_u128_low(b); break;
            case ZU_BIT_OR:  h = zuf_u128_high(a) | zuf_u128_high(b); l = zuf_u128_low(a) | zuf_u128_low(b); break;
            case ZU_BIT_XOR: h = zuf_u128_high(a) ^ zuf_u128_high(b); l = zuf_u128_low(a) ^ zuf_u128_low(b); break;
            default:         h = ~zuf_u128_high(a); l = ~zuf_u128_low(a); break;
            }
            r = zu_type_is_128(t) ? zuf_u128_make(h, l) : zuf_u128_from_u64(l);
            if (zu_put_raw(out, t, i, r)) { zu_set_na(out, t, i); ovf++; }
        }
        if (++ix == nx) ix = 0;
        if (++iy == ny) iy = 0;
    }
    out = zu_pair_bits(out, ovf);
    UNPROTECT(1);
    return out;
}

typedef enum { ZU_POPCOUNT = 1, ZU_CLZ, ZU_CTZ } zu_bitcount;

/* An integer per value: set bits, leading zeros or trailing zeros of the
   full width (clz and ctz of 0 are the width). */
SEXP zu_bitcount_c(SEXP x, SEXP type_, SEXP what_)
{
    zu_type t = zu_type_arg(type_);
    zu_bitcount what = (zu_bitcount)Rf_asInteger(what_);
    zu_check_payload(x, t);
    unsigned width = zu_type_is_128(t) ? 128 : 64;
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
    int *po = INTEGER(out);
    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) { po[i] = NA_INTEGER; continue; }
        zuf_u128 v = zu_raw(x, t, i);
        unsigned c = 0;
        if (what == ZU_POPCOUNT) {
            for (uint64_t w = zuf_u128_high(v); w; w &= w - 1) c++;
            for (uint64_t w = zuf_u128_low(v); w; w &= w - 1) c++;
        } else if (what == ZU_CLZ) {
            c = width - zuf_int_u128_bit_width(v);
        } else {
            c = (zuf_u128_high(v) | zuf_u128_low(v)) == 0 ? width : zuf_int_u128_ctz(v);
        }
        po[i] = (int)c;
    }
    UNPROTECT(1);
    return out;
}
