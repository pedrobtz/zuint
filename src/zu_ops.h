/*
 * zu_ops.h -- the NA and overflow-policy layer (design 6, 10).
 *
 * The arithmetic itself is zufast/wide.h's checked and wrapping primitives;
 * this file decides what an out-of-range result becomes. Each operation on
 * non-NA operands returns one of:
 *
 *   ZU_OK       *out holds the result
 *   ZU_NA       the result is NA, silently: division by zero
 *   ZU_OVERFLOW the exact result does not fit the type, and *out holds it
 *               modulo 2^width
 *
 * A result equal to the NA sentinel is out of range like any other, since
 * the types' ranges exclude it. The caller turns ZU_OVERFLOW into NA plus a
 * warning (default), an error (checked_*) or the wrapped value
 * (wrapping_*); a wrapped value on the sentinel is NA (design 6).
 *
 * Values are raw words, uint64_t for the 64-bit types (an int64 is its two's
 * complement bits) and zuf_u128 for the 128-bit ones. Signed 64-bit work is
 * done in unsigned arithmetic, so no signed overflow ever reaches C.
 */
#ifndef ZUINT_OPS_H
#define ZUINT_OPS_H

#include "zu_wide.h"

typedef enum { ZU_POLICY_DEFAULT = 0, ZU_POLICY_CHECKED = 1, ZU_POLICY_WRAP = 2 } zu_policy;
typedef enum { ZU_OK = 0, ZU_NA = 1, ZU_OVERFLOW = 2 } zu_status;

typedef enum {
    ZU_OP_ADD = 1, ZU_OP_SUB = 2, ZU_OP_MUL = 3, ZU_OP_IDIV = 4, ZU_OP_MOD = 5
} zu_op;

/* ---- 64-bit ------------------------------------------------------------- */

static inline int64_t zu_i64(uint64_t b)
{
    int64_t v;
    memcpy(&v, &b, sizeof v);
    return v;
}

static inline uint64_t zu_u64(int64_t v)
{
    uint64_t b;
    memcpy(&b, &v, sizeof b);
    return b;
}

static inline zu_status zu_op64(zu_op op, zu_type t, uint64_t a, uint64_t b, uint64_t *out)
{
    bool sgn = t == ZU_INT64, ovf = false;
    uint64_t r = 0;
    switch (op) {
    case ZU_OP_ADD:
        r = a + b;
        ovf = sgn ? (((a ^ r) & (b ^ r)) >> 63) != 0 : r < a;
        break;
    case ZU_OP_SUB:
        r = a - b;
        ovf = sgn ? (((a ^ b) & (a ^ r)) >> 63) != 0 : b > a;
        break;
    case ZU_OP_MUL:
        if (sgn) {
            zuf_i128 p = zuf_i128_mul_i64_i64(zu_i64(a), zu_i64(b));
            int64_t v;
            ovf = !zuf_i128_to_i64(p, &v);
            r = a * b;   /* unsigned: the low word, which is the wrapped result */
        } else {
            zuf_u128 p = zuf_u128_mul_u64_u64(a, b);
            ovf = zuf_u128_high(p) != 0;
            r = zuf_u128_low(p);
        }
        break;
    case ZU_OP_IDIV:
    case ZU_OP_MOD:
        if (b == 0) return ZU_NA;
        if (sgn) {
            /* neither operand is INT64_MIN, so C's / and % cannot overflow */
            int64_t x = zu_i64(a), y = zu_i64(b), q = x / y, m = x % y;
            if (m != 0 && ((m < 0) != (y < 0))) { q -= 1; m += y; }   /* floor */
            r = zu_u64(op == ZU_OP_IDIV ? q : m);
        } else {
            r = op == ZU_OP_IDIV ? a / b : a % b;
        }
        break;
    }
    *out = r;
    return ovf || r == zu_na64(t) ? ZU_OVERFLOW : ZU_OK;
}

static inline zu_status zu_neg64(zu_type t, uint64_t a, uint64_t *out)
{
    *out = UINT64_C(0) - a;
    /* the signed range is symmetric; only an unsigned zero negates */
    return t == ZU_INT64 || a == 0 ? ZU_OK : ZU_OVERFLOW;
}

/* ---- 128-bit ------------------------------------------------------------ */

static inline zu_status zu_op128(zu_op op, zu_type t, zuf_u128 a, zuf_u128 b, zuf_u128 *out)
{
    bool ovf = false;
    zuf_u128 r = zuf_u128_make(0, 0);
    if (t == ZU_INT128) {
        zuf_i128 x = zuf_i128_from_u128(a), y = zuf_i128_from_u128(b), s = zuf_i128_from_u128(r), m;
        switch (op) {
        case ZU_OP_ADD:
            if (!zuf_i128_add(x, y, &s)) { ovf = true; s = zuf_i128_add_wrap(x, y); }
            break;
        case ZU_OP_SUB:
            if (!zuf_i128_sub(x, y, &s)) { ovf = true; s = zuf_i128_sub_wrap(x, y); }
            break;
        case ZU_OP_MUL:
            if (!zuf_i128_mul(x, y, &s)) { ovf = true; s = zuf_i128_mul_wrap(x, y); }
            break;
        case ZU_OP_IDIV:
        case ZU_OP_MOD:
            /* false only for a zero divisor: MIN, the one overflowing
               dividend, is the NA sentinel */
            if (!zuf_i128_divmod_floor(x, y, &s, &m)) return ZU_NA;
            if (op == ZU_OP_MOD) s = m;
            break;
        }
        r = zuf_u128_from_i128(s);
    } else {
        zuf_u128 m;
        switch (op) {
        case ZU_OP_ADD:
            if (!zuf_u128_add(a, b, &r)) { ovf = true; r = zuf_u128_add_wrap(a, b); }
            break;
        case ZU_OP_SUB:
            if (!zuf_u128_sub(a, b, &r)) { ovf = true; r = zuf_u128_sub_wrap(a, b); }
            break;
        case ZU_OP_MUL:
            if (!zuf_u128_mul(a, b, &r)) { ovf = true; r = zuf_u128_mul_wrap(a, b); }
            break;
        case ZU_OP_IDIV:
        case ZU_OP_MOD:
            if (!zuf_u128_divmod(a, b, &r, &m)) return ZU_NA;
            if (op == ZU_OP_MOD) r = m;
            break;
        }
    }
    *out = r;
    return ovf || zuf_u128_cmp(r, zu_na128(t)) == 0 ? ZU_OVERFLOW : ZU_OK;
}

static inline zu_status zu_neg128(zu_type t, zuf_u128 a, zuf_u128 *out)
{
    *out = zu_negate_bits(a);
    return t == ZU_INT128 || (zuf_u128_high(a) | zuf_u128_low(a)) == 0 ? ZU_OK : ZU_OVERFLOW;
}

#endif /* ZUINT_OPS_H */
