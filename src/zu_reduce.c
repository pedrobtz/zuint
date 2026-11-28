/*
 * zu_reduce.c -- reductions (design 7).
 *
 * sum() is type stable and exact: the 64-bit types accumulate in 128 bits,
 * which cannot overflow for any vector R can hold, and the 128-bit types
 * accumulate modulo 2^128 while counting the wrap-arounds, so a sum that
 * passes beyond the range and comes back is still exact. The result is NA
 * with an overflow when it does not fit the type. prod() is exact the same
 * way; a zero anywhere makes it zero. The cumulative functions are NA from
 * the first NA, or the first overflow, onwards. mean() is the exact sum
 * divided by the count, rounded once to the nearest double.
 *
 * With na_rm FALSE, an NA makes the result NA (cumulative: from there on).
 */
#include "zu_ops.h"
#include <limits.h>
#include <math.h>

static SEXP zu_pair_r(SEXP value, R_xlen_t n)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)n));
    UNPROTECT(1);
    return out;
}

/* A running sum modulo 2^128 and how many times it wrapped (+1 up, -1
   down); the exact sum is acc + wraps * 2^128 with acc read in the type. */
typedef struct {
    zuf_u128 acc;
    int64_t wraps;
} zu_wide_sum;

static void zu_sum_add(zu_wide_sum *s, zu_type t, zuf_u128 v)
{
    zuf_u128 r = zuf_u128_add_wrap(s->acc, v);
    if (zu_type_is_signed(t)) {
        /* v is two's complement of its type, sign-extended to 128 bits */
        bool sa = (zuf_u128_high(s->acc) & ZU_SIGN64) != 0, sv = (zuf_u128_high(v) & ZU_SIGN64) != 0,
             sr = (zuf_u128_high(r) & ZU_SIGN64) != 0;
        if (t == ZU_INT128 && sa == sv && sr != sa) s->wraps += sa ? -1 : 1;
    } else if (zuf_u128_cmp(r, s->acc) < 0) {
        s->wraps++;
    }
    s->acc = r;
}

/* The value as 128 raw bits: sign-extended for int64, zero-extended for
   uint64. */
static zuf_u128 zu_wide_bits(SEXP x, zu_type t, R_xlen_t i)
{
    if (zu_type_is_128(t)) return zu_get128(COMPLEX(x), i);
    uint64_t b = zu_get64(REAL(x), i);
    return zuf_u128_make(t == ZU_INT64 && (b & ZU_SIGN64) ? ~UINT64_C(0) : 0, b);
}

/* Does the exact sum fit the type, NA pattern excluded? */
static bool zu_sum_fits(zu_wide_sum s, zu_type t)
{
    uint64_t hi = zuf_u128_high(s.acc), lo = zuf_u128_low(s.acc);
    if (s.wraps != 0) return false;
    switch (t) {
    case ZU_INT64:   /* high word is the sign extension of the low word */
        return hi == ((lo & ZU_SIGN64) ? ~UINT64_C(0) : 0) && lo != ZU_SIGN64;
    case ZU_UINT64:
        return hi == 0 && lo != ~UINT64_C(0);
    default:
        return zuf_u128_cmp(s.acc, zu_na128(t)) != 0;
    }
}

static zuf_u128 zu_raw_bits(SEXP x, zu_type t, R_xlen_t i)
{
    return zu_type_is_128(t) ? zu_get128(COMPLEX(x), i) : zuf_u128_from_u64(zu_get64(REAL(x), i));
}

static void zu_put_bits(SEXP out, zu_type t, R_xlen_t i, zuf_u128 v)
{
    if (zu_type_is_128(t)) zu_set128(COMPLEX(out), i, v);
    else zu_set64(REAL(out), i, zuf_u128_low(v));
}

SEXP zu_sum_c(SEXP x, SEXP type_, SEXP na_rm_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool na_rm = Rf_asLogical(na_rm_) == TRUE;
    R_xlen_t n = XLENGTH(x), ovf = 0;
    zu_wide_sum s = {zuf_u128_make(0, 0), 0};
    SEXP out = PROTECT(zu_alloc(t, 1));
    if (!zu_type_is_128(t)) {
        /* 64-bit values: fewer than 2^63 of them cannot wrap the 128-bit
           total. */
        const double *p = REAL(x);
        const uint64_t na = zu_na64(t);
        const bool sgn = t == ZU_INT64;
        R_xlen_t nas = 0;
        /* Each value as 32-bit halves, summed in separate 64-bit lanes: no
           carry chain, so the loop vectorises, and no lane can overflow
           within 2^31 values. A signed value's high half is summed
           unsigned and corrected by 2^32 for each negative value. Every
           chunk folds into the 128-bit total exactly. */
        zuf_u128 total = zuf_u128_make(0, 0);
        const R_xlen_t chunk = (R_xlen_t)1 << 31;
        for (R_xlen_t from = 0; from < n; from += chunk) {
            R_xlen_t to = n - from < chunk ? n : from + chunk;
            uint64_t lo_sum = 0, hi_sum = 0, negs = 0, k = 0;
            for (R_xlen_t i = from; i < to; i++) {
                uint64_t v = zu_get64(p, i), isna = v == na;
                v = isna ? 0 : v;
                k += isna;
                lo_sum += v & 0xFFFFFFFFu;
                hi_sum += v >> 32;
                negs += v >> 63;
            }
            nas += (R_xlen_t)k;
            /* chunk = hi_sum * 2^32 + lo_sum - (signed ? negs * 2^64 : 0) */
            zuf_u128 c = zuf_u128_add_wrap(zuf_int_u128_shl(zuf_u128_from_u64(hi_sum), 32), zuf_u128_from_u64(lo_sum));
            if (sgn) c = zuf_u128_sub_wrap(c, zuf_u128_make(negs, 0));
            total = zuf_u128_add_wrap(total, c);
        }
        uint64_t lo = zuf_u128_low(total), hi = zuf_u128_high(total);
        if (nas > 0 && !na_rm) {
            zu_set_na(out, t, 0);
            out = zu_pair_r(out, 0);
            UNPROTECT(1);
            return out;
        }
        s.acc = zuf_u128_make(hi, lo);
        if (zu_sum_fits(s, t)) zu_put_bits(out, t, 0, s.acc);
        else { zu_set_na(out, t, 0); ovf = 1; }
        out = zu_pair_r(out, ovf);
        UNPROTECT(1);
        return out;
    }
    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) {
            if (na_rm) continue;
            zu_set_na(out, t, 0);
            out = zu_pair_r(out, 0);
            UNPROTECT(1);
            return out;
        }
        zu_sum_add(&s, t, zu_wide_bits(x, t, i));
    }
    if (zu_sum_fits(s, t)) zu_put_bits(out, t, 0, s.acc);
    else { zu_set_na(out, t, 0); ovf = 1; }
    out = zu_pair_r(out, ovf);
    UNPROTECT(1);
    return out;
}

static zu_status zu_mul_raw(zu_type t, zuf_u128 a, zuf_u128 b, zuf_u128 *r)
{
    if (zu_type_is_128(t)) return zu_op128(ZU_OP_MUL, t, a, b, r);
    uint64_t r64;
    zu_status s = zu_op64(ZU_OP_MUL, t, zuf_u128_low(a), zuf_u128_low(b), &r64);
    *r = zuf_u128_from_u64(r64);
    return s;
}

SEXP zu_prod_c(SEXP x, SEXP type_, SEXP na_rm_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool na_rm = Rf_asLogical(na_rm_) == TRUE, zero = false, overflowed = false;
    R_xlen_t n = XLENGTH(x);
    zuf_u128 acc = zuf_u128_from_u64(1);
    SEXP out = PROTECT(zu_alloc(t, 1));
    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) {
            if (na_rm) continue;
            zu_set_na(out, t, 0);
            out = zu_pair_r(out, 0);
            UNPROTECT(1);
            return out;
        }
        zuf_u128 v = zu_raw_bits(x, t, i);
        if ((zuf_u128_high(v) | zuf_u128_low(v)) == 0) zero = true;
        if (!overflowed && !zero) {
            zuf_u128 r;
            if (zu_mul_raw(t, acc, v, &r) == ZU_OVERFLOW) overflowed = true;
            else acc = r;
        }
    }
    if (zero) zu_put_bits(out, t, 0, zuf_u128_make(0, 0));
    else if (overflowed) zu_set_na(out, t, 0);
    else zu_put_bits(out, t, 0, acc);
    out = zu_pair_r(out, !zero && overflowed);
    UNPROTECT(1);
    return out;
}

typedef enum { ZU_CUMSUM = 1, ZU_CUMPROD, ZU_CUMMAX, ZU_CUMMIN } zu_cum;

SEXP zu_cum_c(SEXP x, SEXP type_, SEXP what_)
{
    zu_type t = zu_type_arg(type_);
    zu_cum what = (zu_cum)Rf_asInteger(what_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), ovf = 0, i = 0;
    SEXP out = PROTECT(zu_alloc(t, n));
    zu_wide_sum s = {zuf_u128_make(0, 0), 0};
    zuf_u128 acc = zuf_u128_from_u64(1);
    zu_val best = zu_val_na();
    for (; i < n; i++) {
        if (zu_is_na(x, t, i)) break;
        if (what == ZU_CUMSUM) {
            zu_sum_add(&s, t, zu_wide_bits(x, t, i));
            if (!zu_sum_fits(s, t)) { ovf = 1; break; }
            zu_put_bits(out, t, i, s.acc);
        } else if (what == ZU_CUMPROD) {
            zuf_u128 r;
            if (zu_mul_raw(t, acc, zu_raw_bits(x, t, i), &r) == ZU_OVERFLOW) { ovf = 1; break; }
            acc = r;
            zu_put_bits(out, t, i, acc);
        } else {
            zu_val v = zu_val_get(x, t, i);
            int c = best.na ? 0 : zu_val_cmp(v, best);
            if (best.na || (what == ZU_CUMMAX ? c > 0 : c < 0)) best = v;
            zu_val_put(out, t, i, best);
        }
    }
    for (; i < n; i++) zu_set_na(out, t, i);
    out = zu_pair_r(out, ovf);
    UNPROTECT(1);
    return out;
}

/* The double nearest (Q + R / m) / D, ties to even, for R < m < 2^63 and
   1 <= D < 2^127: the one rounding of an exact quotient (design 7). The
   bits are produced by long division until there are 64 of them, the
   rest folded into a sticky bit, then rounded to 53. The state (A, R)
   stands for the fraction (A + R / m) / D still to come, with A < D. */
static double zu_round_quotient(zuf_u128 Q, uint64_t R, uint64_t m, zuf_u128 D)
{
    zuf_u128 M, A;
    zuf_u128_divmod(Q, D, &M, &A);
    if (zuf_int_u128_is_zero(M) && zuf_int_u128_is_zero(A) && R == 0) return 0;
    int k = 0;   /* M = floor(value * 2^k) */
    while (zuf_int_u128_bit_width(M) < 64) {
        uint64_t r2 = R << 1;   /* R < m < 2^63: no overflow */
        unsigned c = R >= m - R;   /* 2R >= m */
        if (c) r2 -= m;
        R = r2;
        zuf_u128 a2 = zuf_u128_add_wrap(zuf_int_u128_shl(A, 1), zuf_u128_from_u64(c));   /* < 2D <= 2^128 */
        unsigned bit = zuf_u128_cmp(a2, D) >= 0;
        if (bit) a2 = zuf_u128_sub_wrap(a2, D);
        A = a2;
        M = zuf_u128_add_wrap(zuf_int_u128_shl(M, 1), zuf_u128_from_u64(bit));
        k++;
    }
    bool sticky = !zuf_int_u128_is_zero(A) || R != 0;
    unsigned shift = zuf_int_u128_bit_width(M) - 53;   /* 11..75 */
    uint64_t mant = zuf_u128_low(zuf_int_u128_shr(M, shift));
    zuf_u128 rest = zuf_u128_sub_wrap(M, zuf_int_u128_shl(zuf_u128_from_u64(mant), shift));
    int c = zuf_u128_cmp(rest, zuf_int_u128_shl(zuf_u128_from_u64(1), shift - 1));
    if (c > 0 || (c == 0 && (sticky || (mant & 1)))) mant++;   /* up to 2^53, exact */
    return ldexp((double)mant, (int)shift - k);
}

/* 10^s as 128 bits, s in 0..38. */
static zuf_u128 zu_pow10_128(int s)
{
    if (s <= 19) return zuf_u128_from_u64(zuf_int_pow10_u64((unsigned)s));
    return zuf_u128_mul_u64_u64(zuf_int_pow10_u64(19), zuf_int_pow10_u64((unsigned)(s - 19)));
}

/* The mean as a double: the exact sum / (n * 10^scale), rounded once (the
   scale is a decimal's, 0 for the integer types). The 64-bit types sum
   exactly in 128 bits; the 128-bit types keep sum = q * n + r with
   |r| < n, so nothing overflows. */
SEXP zu_mean_c(SEXP x, SEXP type_, SEXP na_rm_, SEXP scale_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool na_rm = Rf_asLogical(na_rm_) == TRUE;
    int scale = Rf_asInteger(scale_);
    if (scale == NA_INTEGER || scale < 0 || scale > 38) Rf_error("zuint: the scale must be in 0..38");
    R_xlen_t n = XLENGTH(x), m = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) {
            if (!na_rm) return Rf_ScalarReal(NA_REAL);
        } else {
            m++;
        }
    }
    if (m == 0) return Rf_ScalarReal(R_NaN);
    /* the mean is (neg ? -1 : 1) * (Q + R / m) with 0 <= R < m */
    bool neg;
    zuf_u128 Q;
    uint64_t R;
    if (!zu_type_is_128(t)) {
        zu_wide_sum s = {zuf_u128_make(0, 0), 0};
        for (R_xlen_t i = 0; i < n; i++)
            if (!zu_is_na(x, t, i)) zu_sum_add(&s, t, zu_wide_bits(x, t, i));
        /* the 128-bit total, signed for int64 */
        zu_val v = zu_type_is_signed(t) && (zuf_u128_high(s.acc) & ZU_SIGN64)
            ? zu_val_make(true, zu_negate_bits(s.acc)) : zu_val_make(false, s.acc);
        neg = v.neg;
        zuf_u128_divmod_u64(v.mag, (uint64_t)m, &Q, &R);
    } else {
        /* q and r, each with its own sign; r is folded into q whenever |r|
           reaches m, so sum = q * m + r throughout */
        zu_val q = zu_val_make(false, zuf_u128_make(0, 0));
        int64_t r = 0;
        for (R_xlen_t i = 0; i < n; i++) {
            zu_val v = zu_val_get(x, t, i);
            if (v.na) continue;
            zuf_u128 qi;
            uint64_t ri;
            zuf_u128_divmod_u64(v.mag, (uint64_t)m, &qi, &ri);
            /* q += sign * qi, with q in sign-magnitude */
            zu_val add = zu_val_make(v.neg, qi);
            if (q.neg == add.neg) {
                zuf_u128_add(q.mag, add.mag, &q.mag);   /* bounded by max |x| */
            } else if (zuf_u128_cmp(q.mag, add.mag) >= 0) {
                q.mag = zuf_u128_sub_wrap(q.mag, add.mag);
            } else {
                q = zu_val_make(add.neg, zuf_u128_sub_wrap(add.mag, q.mag));
            }
            q = zu_val_make(q.neg, q.mag);
            r += v.neg ? -(int64_t)ri : (int64_t)ri;
            if (r >= (int64_t)m || r <= -(int64_t)m) {
                int64_t carry = r / (int64_t)m;
                r -= carry * (int64_t)m;
                zu_val c = zu_val_make(carry < 0, zuf_u128_from_u64(carry < 0 ? (uint64_t)(-carry) : (uint64_t)carry));
                if (q.neg == c.neg) zuf_u128_add(q.mag, c.mag, &q.mag);
                else if (zuf_u128_cmp(q.mag, c.mag) >= 0) q.mag = zuf_u128_sub_wrap(q.mag, c.mag);
                else q = zu_val_make(c.neg, zuf_u128_sub_wrap(c.mag, q.mag));
                q = zu_val_make(q.neg, q.mag);
            }
        }
        /* to one sign: |q| + |r| / m, or |q| - |r| / m = (|q| - 1) + (m - |r|) / m */
        uint64_t ar = r < 0 ? (uint64_t)(-r) : (uint64_t)r;
        bool rneg = r < 0;
        if (ar == 0) {
            neg = q.neg; Q = q.mag; R = 0;
        } else if (zuf_int_u128_is_zero(q.mag)) {
            neg = rneg; Q = q.mag; R = ar;
        } else if (rneg == q.neg) {
            neg = q.neg; Q = q.mag; R = ar;
        } else {
            neg = q.neg;
            Q = zuf_u128_sub_wrap(q.mag, zuf_u128_from_u64(1));
            R = (uint64_t)m - ar;
        }
    }
    double d = zu_round_quotient(Q, R, (uint64_t)m, zu_pow10_128(scale));
    return Rf_ScalarReal(neg && d != 0 ? -d : d);
}
