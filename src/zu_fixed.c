/*
 * zu_fixed.c -- fixed-point DECIMAL(p, s) on a 128-bit coefficient
 * (design 2.2). See zu_fixed.h for the contract; this file never calls R.
 *
 * Everything works on a sign and a magnitude (zuf_u128). A coefficient of
 * a valid type is below 10^38 < 2^127, so negating a magnitude back is
 * always exact.
 *
 * The text parser decides which texts DuckDB 2.0.0 accepts by running a
 * port of DuckDB's own state machine (dk_*, below), then computes the
 * value exactly from the digits. The port is of
 * src/include/duckdb/common/operator/decimal_cast_operators.hpp
 * (DecimalCastOperation) and integer_cast_operator.hpp (IntegerCastLoop,
 * TryIntegerCast) at DuckDB commit d54cbbe3df, Copyright 2018-2026
 * Stichting DuckDB Foundation, MIT licence (inst/COPYRIGHTS). Two answers
 * of DuckDB's are wrong, and design 2.2 records where zuint differs:
 *   - it accepts some texts whose value has more digits than p (after a
 *     positive exponent moves fractional digits into the integer part);
 *     zuint refuses them, since the result would not be a DECIMAL(p, s);
 *   - it drops digits past its storage type's width (4, 9, 18 or 38), so a
 *     text with leading zeros and an exponent can lose its value; zuint
 *     keeps every digit.
 */
#include "zu_fixed.h"

#include <math.h>
#include <string.h>

/* ---- constants ----------------------------------------------------------- */

/* 10^0 .. 10^38 as {low, high}. */
static const zuf_u128 zu_fx_pow10[39] = {
#define P(h, l) {UINT64_C(l), UINT64_C(h)}
    P(0x0000000000000000, 0x0000000000000001), P(0x0000000000000000, 0x000000000000000a),
    P(0x0000000000000000, 0x0000000000000064), P(0x0000000000000000, 0x00000000000003e8),
    P(0x0000000000000000, 0x0000000000002710), P(0x0000000000000000, 0x00000000000186a0),
    P(0x0000000000000000, 0x00000000000f4240), P(0x0000000000000000, 0x0000000000989680),
    P(0x0000000000000000, 0x0000000005f5e100), P(0x0000000000000000, 0x000000003b9aca00),
    P(0x0000000000000000, 0x00000002540be400), P(0x0000000000000000, 0x000000174876e800),
    P(0x0000000000000000, 0x000000e8d4a51000), P(0x0000000000000000, 0x000009184e72a000),
    P(0x0000000000000000, 0x00005af3107a4000), P(0x0000000000000000, 0x00038d7ea4c68000),
    P(0x0000000000000000, 0x002386f26fc10000), P(0x0000000000000000, 0x016345785d8a0000),
    P(0x0000000000000000, 0x0de0b6b3a7640000), P(0x0000000000000000, 0x8ac7230489e80000),
    P(0x0000000000000005, 0x6bc75e2d63100000), P(0x0000000000000036, 0x35c9adc5dea00000),
    P(0x000000000000021e, 0x19e0c9bab2400000), P(0x000000000000152d, 0x02c7e14af6800000),
    P(0x000000000000d3c2, 0x1bcecceda1000000), P(0x0000000000084595, 0x161401484a000000),
    P(0x000000000052b7d2, 0xdcc80cd2e4000000), P(0x00000000033b2e3c, 0x9fd0803ce8000000),
    P(0x00000000204fce5e, 0x3e25026110000000), P(0x00000001431e0fae, 0x6d7217caa0000000),
    P(0x0000000c9f2c9cd0, 0x4674edea40000000), P(0x0000007e37be2022, 0xc0914b2680000000),
    P(0x000004ee2d6d415b, 0x85acef8100000000), P(0x0000314dc6448d93, 0x38c15b0a00000000),
    P(0x0001ed09bead87c0, 0x378d8e6400000000), P(0x0013426172c74d82, 0x2b878fe800000000),
    P(0x00c097ce7bc90715, 0xb34b9f1000000000), P(0x0785ee10d5da46d9, 0x00f436a000000000),
    P(0x4b3b4ca85a86c47a, 0x098a224000000000)
#undef P
};

/* DuckDB's NumericHelper::DOUBLE_POWERS_OF_TEN, the doubles nearest 10^k. */
static const double zu_fx_dpow10[39] = {
    1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,  1e8,  1e9,  1e10, 1e11, 1e12,
    1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22, 1e23, 1e24, 1e25,
    1e26, 1e27, 1e28, 1e29, 1e30, 1e31, 1e32, 1e33, 1e34, 1e35, 1e36, 1e37, 1e38};

/* ---- sign and magnitude --------------------------------------------------- */

static bool fx_zero(zuf_u128 m) { return m.low == 0 && m.high == 0; }

static zuf_u128 fx_mag(zuf_i128 c, bool *neg)
{
    *neg = zuf_i128_is_neg(c);
    return zuf_int_i128_magnitude(c);
}

/* A magnitude below 2^127 with a sign; zero is never negative. */
static zuf_i128 fx_join(bool neg, zuf_u128 m)
{
    if (neg && !fx_zero(m)) m = zuf_u128_sub_wrap(zuf_u128_make(0, 0), m);
    return zuf_i128_from_u128(m);
}

/* m * 10 + d, wrapping; callers bound m first. */
static zuf_u128 fx_mul10_add(zuf_u128 m, unsigned d)
{
    return zuf_u128_add_wrap(zuf_u128_mul_wrap(m, zuf_u128_from_u64(10)), zuf_u128_from_u64(d));
}

static unsigned fx_mod10(zuf_u128 *m)
{
    zuf_u128 q;
    uint64_t r;
    (void)zuf_u128_divmod_u64(*m, 10, &q, &r);
    *m = q;
    return (unsigned)r;
}

static bool fx_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static bool fx_digit(unsigned char c) { return c >= '0' && c <= '9'; }

/* ---- types --------------------------------------------------------------- */

int zu_fx_type_check(int p, int s)
{
    if (p < 1 || p > ZU_FX_MAX_PRECISION || s < 0 || s > p) return ZU_FX_TYPE;
    return ZU_FX_OK;
}

static bool fx_mag_fits(zuf_u128 m, int p) { return zuf_u128_cmp(m, zu_fx_pow10[p]) < 0; }

int zu_fx_fits(zuf_i128 c, int p)
{
    bool neg;
    if (p < 1 || p > ZU_FX_MAX_PRECISION) return ZU_FX_TYPE;
    return fx_mag_fits(fx_mag(c, &neg), p) ? ZU_FX_OK : ZU_FX_OVERFLOW;
}

/* ---- rescale ------------------------------------------------------------- */

int zu_fx_rescale(zuf_i128 c, int s, int p_to, int s_to, zuf_i128 *out)
{
    bool neg;
    zuf_u128 m, q, r;
    if (!out) return ZU_FX_ARGUMENT;
    if (s < 0 || s > ZU_FX_MAX_PRECISION || zu_fx_type_check(p_to, s_to) != ZU_FX_OK) return ZU_FX_TYPE;
    m = fx_mag(c, &neg);
    if (s_to >= s) {
        if (!zuf_u128_mul(m, zu_fx_pow10[s_to - s], &m)) return ZU_FX_OVERFLOW;
    } else {
        /* half away from zero: up when the remainder is at least 10^k / 2 */
        zuf_u128 d = zu_fx_pow10[s - s_to], half;
        (void)zuf_u128_divmod(m, d, &q, &r);
        half = zuf_int_u128_shr(d, 1);
        if (zuf_u128_cmp(r, half) >= 0) q = zuf_u128_add_wrap(q, zuf_u128_from_u64(1));
        m = q;
    }
    if (!fx_mag_fits(m, p_to)) return ZU_FX_OVERFLOW;
    *out = fx_join(neg, m);
    return ZU_FX_OK;
}

/* ---- text: DuckDB's acceptance, ported ------------------------------------ */

enum { DK_NONE = 0, DK_POSITIVE = 1, DK_NEGATIVE = 2 };

typedef struct {
    zuf_u128 result; /* DuckDB's StoreType value, as a magnitude */
    zuf_u128 limit;  /* 10^width */
    zuf_u128 max_div10;
    int width, scale, max_digits;
    int digit_count, decimal_count;
    bool round_set, should_round;
    int excessive_decimals;
    int exponent_type;
} dk_state;

/* DuckDB stores DECIMAL(p, s) in int16, int32, int64 or hugeint by p, and
   its parser's digit cap and overflow guard are that type's. */
static void dk_init(dk_state *st, int p, int s)
{
    memset(st, 0, sizeof *st);
    st->width = p;
    st->scale = s;
    st->limit = zu_fx_pow10[p];
    if (p <= 4) {
        st->max_digits = 4;
        st->max_div10 = zuf_u128_from_u64(INT16_MAX / 10);
    } else if (p <= 9) {
        st->max_digits = 9;
        st->max_div10 = zuf_u128_from_u64(INT32_MAX / 10);
    } else if (p <= 18) {
        st->max_digits = 18;
        st->max_div10 = zuf_u128_from_u64(INT64_MAX / 10);
    } else {
        st->max_digits = 38;
        st->max_div10 = zuf_u128_make(UINT64_C(0x0ccccccccccccccc), UINT64_C(0xcccccccccccccccc));
    }
}

static bool dk_digit(dk_state *st, unsigned d)
{
    if (fx_zero(st->result) && d == 0) return true; /* leading zeros do not count */
    if (st->digit_count == st->width - st->scale) return false;
    st->digit_count++;
    if (zuf_u128_cmp(st->result, st->max_div10) > 0) return false;
    st->result = fx_mul10_add(st->result, d);
    return true;
}

static void dk_round_up(dk_state *st) { st->result = zuf_u128_add_wrap(st->result, zuf_u128_from_u64(1)); }

static void dk_decimal(dk_state *st, unsigned d)
{
    if (st->decimal_count == st->scale && !st->round_set) {
        st->round_set = true;
        st->should_round = d >= 5;
    }
    if (st->digit_count + st->decimal_count >= st->max_digits) return;
    st->decimal_count++;
    st->result = fx_mul10_add(st->result, d);
}

static void dk_truncate(dk_state *st)
{
    bool round_up = false;
    for (int i = 0; i < st->excessive_decimals; i++) round_up = fx_mod10(&st->result) >= 5;
    if (st->exponent_type == DK_POSITIVE && round_up) dk_round_up(st);
    st->decimal_count = st->scale;
}

static bool dk_finalize(dk_state *st)
{
    if (st->exponent_type != DK_POSITIVE && st->decimal_count > st->scale)
        st->excessive_decimals = st->decimal_count - st->scale;
    if (st->excessive_decimals) dk_truncate(st);
    if (st->exponent_type == DK_NONE && st->round_set && st->should_round) dk_round_up(st);
    for (int i = st->decimal_count; i < st->scale; i++) st->result = fx_mul10_add(st->result, 0);
    return zuf_u128_cmp(st->result, st->limit) < 0;
}

static bool dk_exponent(dk_state *st, int e)
{
    int excess = st->decimal_count > st->scale ? st->decimal_count - st->scale : 0;
    if (e > 0) {
        st->exponent_type = DK_POSITIVE;
        if (excess > e) {
            st->excessive_decimals = excess - e;
            e = 0;
        } else {
            e -= excess;
        }
    } else if (e < 0) {
        st->exponent_type = DK_NEGATIVE;
    }
    if (!dk_finalize(st)) return false;
    if (e < 0) {
        bool round_up = false;
        for (long i = 0; i < -(long)e; i++) {
            unsigned mod = fx_mod10(&st->result);
            round_up = mod >= 5;
            if (fx_zero(st->result) && mod == 0) break;
        }
        if (round_up) dk_round_up(st);
        return true;
    }
    for (int i = 0; i < e; i++)
        if (!dk_digit(st, 0)) return false;
    return true;
}

/* The exponent: DuckDB's IntegerCastLoop over an int16_t, no fraction. */
static bool dk_exponent_text(const unsigned char *buf, size_t len, int *out)
{
    bool neg = buf[0] == '-';
    size_t start = (neg || buf[0] == '+') ? 1 : 0, pos = start;
    int v = 0;
    while (pos < len) {
        if (!fx_digit(buf[pos])) {
            if (buf[pos] == '.') {
                bool before = pos > start;
                pos++;
                if (pos < len && fx_digit(buf[pos])) return false; /* no fraction in an exponent */
                if (!before) return false;
                if (pos >= len) break;
            }
            if (fx_space(buf[pos])) {
                if (pos == start) return false;
                while (++pos < len)
                    if (!fx_space(buf[pos])) return false;
                break;
            }
            return false;
        }
        int d = buf[pos++] - '0';
        if (neg) {
            if (v < (INT16_MIN + d) / 10) return false;
            v = v * 10 - d;
        } else {
            if (v > (INT16_MAX - d) / 10) return false;
            v = v * 10 + d;
        }
        if (pos != len && buf[pos] == '_') {
            pos++;
            if (pos == len || !fx_digit(buf[pos])) return false;
        }
    }
    if (pos <= start) return false;
    *out = v;
    return true;
}

/* DuckDB's IntegerCastLoop with DecimalCastOperation, after the sign. */
static bool dk_loop(const unsigned char *buf, size_t len, bool neg, dk_state *st)
{
    size_t start = (neg || buf[0] == '+') ? 1 : 0, pos = start;
    while (pos < len) {
        if (!fx_digit(buf[pos])) {
            if (buf[pos] == '.') {
                bool before = pos > start;
                size_t first;
                pos++;
                first = pos;
                while (pos < len) {
                    if (!fx_digit(buf[pos])) break;
                    dk_decimal(st, (unsigned)(buf[pos] - '0'));
                    pos++;
                    if (pos != len && buf[pos] == '_') {
                        pos++;
                        if (pos == len || !fx_digit(buf[pos])) return false;
                    }
                }
                if (!(before || pos > first)) return false;
                if (pos >= len) break;
            }
            if (fx_space(buf[pos])) {
                if (pos == start) return false;
                while (++pos < len)
                    if (!fx_space(buf[pos])) return false;
                break;
            }
            if (buf[pos] == 'e' || buf[pos] == 'E') {
                int e;
                if (pos == start) return false;
                pos++;
                if (pos >= len) return false;
                if (!dk_exponent_text(buf + pos, len - pos, &e)) return false;
                return dk_exponent(st, e);
            }
            return false;
        }
        if (!dk_digit(st, (unsigned)(buf[pos++] - '0'))) return false;
        if (pos != len && buf[pos] == '_') {
            pos++;
            if (pos == len || !fx_digit(buf[pos])) return false;
        }
    }
    if (!dk_finalize(st)) return false;
    return pos > start;
}

/* DuckDB's TryDecimalStringCast: whether it accepts the text. */
static bool dk_accepts(const unsigned char *buf, size_t len, int p, int s)
{
    dk_state st;
    while (len > 0 && fx_space(*buf)) {
        buf++;
        len--;
    }
    if (len == 0) return false;
    dk_init(&st, p, s);
    if (*buf == '-') return dk_loop(buf, len, true, &st);
    if (len > 1 && buf[0] == '0' && (buf[1] == 'x' || buf[1] == 'X' || buf[1] == 'b' || buf[1] == 'B'))
        return false; /* DuckDB's hex and binary loops refuse every digit of a DECIMAL */
    return dk_loop(buf, len, false, &st);
}

/* ---- text: the exact value -------------------------------------------------- */

#define FX_KEEP 41 /* significant digits kept: more than any result needs */

typedef struct {
    bool neg;
    unsigned char sig[FX_KEEP]; /* the first significant digits */
    int64_t nsig;               /* significant digits in all, leading zeros dropped */
    int64_t frac;               /* digits after the point, leading zeros included */
    int64_t exponent;
} fx_number;

/* Reads a text dk_accepts() took: sign, digits with '_', '.', exponent. */
static void fx_read(const unsigned char *p, const unsigned char *end, fx_number *x)
{
    bool after_point = false;
    memset(x, 0, sizeof *x);
    while (p < end && fx_space(*p)) p++;
    if (p < end && (*p == '-' || *p == '+')) x->neg = *p++ == '-';
    for (; p < end; p++) {
        unsigned char c = *p;
        if (fx_digit(c)) {
            if (x->nsig > 0 || c != '0') {
                if (x->nsig < FX_KEEP) x->sig[x->nsig] = (unsigned char)(c - '0');
                x->nsig++;
            }
            if (after_point) x->frac++;
        } else if (c == '.') {
            after_point = true;
        } else if (c == '_') {
            continue;
        } else {
            break;
        }
    }
    if (p < end && (*p == 'e' || *p == 'E')) {
        bool eneg = false;
        int64_t e = 0;
        p++;
        if (p < end && (*p == '-' || *p == '+')) eneg = *p++ == '-';
        for (; p < end && (fx_digit(*p) || *p == '_'); p++)
            if (*p != '_') e = e * 10 + (*p - '0'); /* dk_accepts() bounded it to int16 */
        x->exponent = eneg ? -e : e;
    }
}

/* The coefficient at scale s: the value rounded half away from zero. */
static int fx_exact(const fx_number *x, int p, int s, zuf_i128 *out)
{
    zuf_u128 m = zuf_u128_make(0, 0);
    int64_t k = x->exponent - x->frac + s, keep;
    if (x->nsig == 0) {
        *out = zuf_i128_from_u128(m);
        return ZU_FX_OK;
    }
    keep = x->nsig + k; /* significant digits left of the result's last place */
    /* 39 digits with a nonzero first one are at least 10^38, beyond every
       precision, and could wrap 128 bits before the check below */
    if (keep > ZU_FX_MAX_PRECISION) return ZU_FX_OVERFLOW;
    if (keep >= 0) {
        int64_t i, take = keep < x->nsig ? keep : x->nsig;
        for (i = 0; i < take; i++) m = fx_mul10_add(m, x->sig[i]);
        for (; i < keep; i++)
            if (!zuf_u128_mul(m, zu_fx_pow10[1], &m)) return ZU_FX_OVERFLOW;
        if (keep < x->nsig && x->sig[keep] >= 5) m = zuf_u128_add_wrap(m, zuf_u128_from_u64(1));
    }
    if (!fx_mag_fits(m, p)) return ZU_FX_OVERFLOW;
    *out = fx_join(x->neg, m);
    return ZU_FX_OK;
}

/* Whether the text matches DuckDB's grammar, whatever its value: what
   decides ZU_FX_INVALID against ZU_FX_OVERFLOW once DuckDB refuses it. */
static bool fx_grammar(const unsigned char *p, const unsigned char *end)
{
    bool digits = false;
    while (p < end && fx_space(*p)) p++;
    while (end > p && fx_space(end[-1])) end--;
    if (p == end) return false;
    if (*p == '-' || *p == '+') p++;
    if (end - p > 1 && p[0] == '0' && (p[1] == 'x' || p[1] == 'X' || p[1] == 'b' || p[1] == 'B'))
        return false;
    while (p < end && fx_digit(*p)) {
        digits = true;
        p++;
        if (p < end && *p == '_') {
            p++;
            if (p == end || !fx_digit(*p)) return false;
        }
    }
    if (p < end && *p == '.') {
        p++;
        if (p < end && *p == '_') return false;
        while (p < end && fx_digit(*p)) {
            digits = true;
            p++;
            if (p < end && *p == '_') {
                p++;
                if (p == end || !fx_digit(*p)) return false;
            }
        }
    }
    if (!digits) return false;
    if (p < end && (*p == 'e' || *p == 'E')) {
        bool edigits = false;
        p++;
        if (p < end && (*p == '-' || *p == '+')) p++;
        while (p < end && fx_digit(*p)) {
            edigits = true;
            p++;
            if (p < end && *p == '_') {
                p++;
                if (p == end || !fx_digit(*p)) return false;
            }
        }
        if (!edigits) return false;
        if (p < end && *p == '.') p++; /* DuckDB takes "1e2." as 1e2 */
    }
    return p == end;
}

int zu_fx_parse(const char *text, size_t len, int p, int s, zuf_i128 *out)
{
    const unsigned char *b = (const unsigned char *)text;
    fx_number x;
    if (!out || (!text && len)) return ZU_FX_ARGUMENT;
    if (zu_fx_type_check(p, s) != ZU_FX_OK) return ZU_FX_TYPE;
    if (!text) b = (const unsigned char *)""; /* NULL + 0 is undefined in C */
    if (!dk_accepts(b, len, p, s)) return fx_grammar(b, b + len) ? ZU_FX_OVERFLOW : ZU_FX_INVALID;
    fx_read(b, b + len, &x);
    return fx_exact(&x, p, s, out);
}

/* ---- text out -------------------------------------------------------------- */

int zu_fx_format(zuf_i128 c, int p, int s, char *buf, size_t cap, size_t *len)
{
    char digits[ZUF_U128_MAX_CHARS], tmp[ZU_FX_MAX_CHARS];
    bool neg;
    zuf_u128 m;
    size_t nd, n = 0;
    if (!buf || !len) return ZU_FX_ARGUMENT;
    if (zu_fx_type_check(p, s) != ZU_FX_OK) return ZU_FX_TYPE;
    m = fx_mag(c, &neg);
    if (!fx_mag_fits(m, p)) return ZU_FX_OVERFLOW;
    nd = (size_t)(zuf_write_u128(digits, m) - digits);
    if (neg) tmp[n++] = '-';
    if (s == 0) {
        memcpy(tmp + n, digits, nd);
        n += nd;
    } else {
        size_t us = (size_t)s;
        /* DuckDB writes no integer part when p == s: ".50", "-.05" */
        if (nd > us) {
            memcpy(tmp + n, digits, nd - us);
            n += nd - us;
        } else if (p > s) {
            tmp[n++] = '0';
        }
        tmp[n++] = '.';
        if (nd < us) {
            memset(tmp + n, '0', us - nd);
            n += us - nd;
            memcpy(tmp + n, digits, nd);
            n += nd;
        } else {
            memcpy(tmp + n, digits + (nd - us), us);
            n += us;
        }
    }
    if (n > cap) return ZU_FX_BUFFER;
    memcpy(buf, tmp, n);
    *len = n;
    return ZU_FX_OK;
}

/* ---- doubles ---------------------------------------------------------------- */

static unsigned fx_bits(zuf_u128 m) { return zuf_int_u128_bit_width(m); }

/* 5^0 .. 5^38, every one below 2^89. */
static zuf_u128 fx_pow5(int s)
{
    zuf_u128 r = zuf_u128_from_u64(1);
    for (int i = 0; i < s; i++) r = zuf_u128_mul_wrap(r, zuf_u128_from_u64(5));
    return r;
}

/* c / 10^s, correctly rounded. c / 10^s = (c / 5^s) * 2^-s, and the power
   of two is exact, so only m / 5^s is rounded: q = floor(m * 2^t / 5^s)
   with 54 or 55 bits, then rounded to 53 bits, ties to even. */
int zu_fx_to_double(zuf_i128 c, int p, int s, double *out)
{
    bool neg, sticky = false;
    zuf_u128 m, d, q, r;
    int t, drop;
    uint64_t mant;
    double v;
    if (!out) return ZU_FX_ARGUMENT;
    if (zu_fx_type_check(p, s) != ZU_FX_OK) return ZU_FX_TYPE;
    m = fx_mag(c, &neg);
    if (fx_zero(m)) {
        *out = 0.0;
        return ZU_FX_OK;
    }
    if (m.high == 0 && m.low < (UINT64_C(1) << 53) && s <= 22) {
        /* both exact, so IEEE division rounds correctly: DuckDB's fast path */
        v = (double)m.low / zu_fx_dpow10[s];
        *out = neg ? -v : v;
        return ZU_FX_OK;
    }
    d = fx_pow5(s);
    t = 54 - ((int)fx_bits(m) - (int)fx_bits(d));
    if (t <= 0) {
        /* floor(floor(m / 2^-t) / d) == floor(m / (d * 2^-t)) */
        zuf_u128 low = (t == 0) ? zuf_u128_make(0, 0) : zuf_u128_sub_wrap(zuf_int_u128_shl(zuf_u128_from_u64(1), (unsigned)-t), zuf_u128_from_u64(1));
        sticky = (m.low & low.low) != 0 || (m.high & low.high) != 0;
        m = zuf_int_u128_shr(m, (unsigned)-t);
        (void)zuf_u128_divmod(m, d, &q, &r);
    } else {
        /* shift m in by at most 39 bits at a time, so r << step stays in
           128 bits: r < d < 2^89 */
        int left = t;
        (void)zuf_u128_divmod(m, d, &q, &r);
        while (left > 0) {
            int step = left > 39 ? 39 : left;
            zuf_u128 qq;
            r = zuf_int_u128_shl(r, (unsigned)step);
            (void)zuf_u128_divmod(r, d, &qq, &r);
            q = zuf_u128_add_wrap(zuf_int_u128_shl(q, (unsigned)step), qq);
            left -= step;
        }
    }
    sticky = sticky || !fx_zero(r);
    drop = (int)fx_bits(q) - 53;
    if (drop > 0) {
        uint64_t guard = (q.low >> (drop - 1)) & 1u;
        uint64_t below = q.low & ((UINT64_C(1) << (drop - 1)) - 1u);
        mant = q.low >> drop;
        sticky = sticky || below != 0;
        if (guard && (sticky || (mant & 1u))) mant++;
        if (mant == (UINT64_C(1) << 53)) {
            mant >>= 1;
            drop++;
        }
    } else {
        mant = q.low; /* not reached: q has at least 54 bits */
        drop = 0;
    }
    v = ldexp((double)mant, drop - t - s);
    *out = neg ? -v : v;
    return ZU_FX_OK;
}

int zu_fx_from_double(double x, int p, int s, zuf_i128 *out)
{
    double v, r;
    zuf_i128 c;
    if (!out) return ZU_FX_ARGUMENT;
    if (zu_fx_type_check(p, s) != ZU_FX_OK) return ZU_FX_TYPE;
    if (!isfinite(x)) return ZU_FX_INVALID;
    v = x * zu_fx_dpow10[s];
    r = round(v);
    if (!isfinite(r)) return ZU_FX_OVERFLOW;
    if (r <= -zu_fx_dpow10[p] || r >= zu_fx_dpow10[p]) return ZU_FX_OVERFLOW;
    if (!zuf_i128_from_f64(r, &c)) return ZU_FX_OVERFLOW; /* not reached: |r| < 1e38 */
    if (r == 0) c = zuf_int_i128_make(0, 0);              /* no negative zero */
    *out = c;
    return ZU_FX_OK;
}

/* ---- comparison and arithmetic -------------------------------------------------- */

int zu_fx_compare(zuf_i128 a, int sa, zuf_i128 b, int sb, int *out)
{
    bool na, nb;
    zuf_u128 ma, mb;
    int cmp;
    if (!out) return ZU_FX_ARGUMENT;
    if (sa < 0 || sa > ZU_FX_MAX_PRECISION || sb < 0 || sb > ZU_FX_MAX_PRECISION) return ZU_FX_TYPE;
    ma = fx_mag(a, &na);
    mb = fx_mag(b, &nb);
    if (fx_zero(ma)) na = false;
    if (fx_zero(mb)) nb = false;
    if (na != nb) {
        *out = na ? -1 : 1;
        return ZU_FX_OK;
    }
    /* put both on the larger scale; a magnitude that overflows is larger */
    if (sa < sb) {
        if (!zuf_u128_mul(ma, zu_fx_pow10[sb - sa], &ma)) cmp = 1;
        else cmp = zuf_u128_cmp(ma, mb);
    } else if (sb < sa) {
        if (!zuf_u128_mul(mb, zu_fx_pow10[sa - sb], &mb)) cmp = -1;
        else cmp = zuf_u128_cmp(ma, mb);
    } else {
        cmp = zuf_u128_cmp(ma, mb);
    }
    *out = na ? -cmp : cmp;
    return ZU_FX_OK;
}

int zu_fx_add(zuf_i128 a, zuf_i128 b, zuf_i128 *out)
{
    zuf_i128 r;
    if (!out) return ZU_FX_ARGUMENT;
    if (!zuf_i128_add(a, b, &r)) return ZU_FX_OVERFLOW;
    *out = r;
    return ZU_FX_OK;
}

int zu_fx_sub(zuf_i128 a, zuf_i128 b, zuf_i128 *out)
{
    zuf_i128 r;
    if (!out) return ZU_FX_ARGUMENT;
    if (!zuf_i128_sub(a, b, &r)) return ZU_FX_OVERFLOW;
    *out = r;
    return ZU_FX_OK;
}

int zu_fx_mul(zuf_i128 a, zuf_i128 b, zuf_i128 *out)
{
    zuf_i128 r;
    if (!out) return ZU_FX_ARGUMENT;
    if (!zuf_i128_mul(a, b, &r)) return ZU_FX_OVERFLOW;
    *out = r;
    return ZU_FX_OK;
}

const char *zu_fx_strerror(int status)
{
    switch (status) {
    case ZU_FX_OK: return "ok";
    case ZU_FX_OVERFLOW: return "the value does not fit the type";
    case ZU_FX_INVALID: return "not a number DuckDB reads as a decimal";
    case ZU_FX_TYPE: return "precision must be 1 to 38 and scale 0 to the precision";
    case ZU_FX_BUFFER: return "the output buffer is too small";
    case ZU_FX_ARGUMENT: return "a NULL pointer";
    default: return NULL;
    }
}
