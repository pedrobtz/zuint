/*
 * Fuzz target for zuint's two readers of untrusted bytes, each compared
 * with a reference written from its specification, not from the code:
 *
 *   - zu_parse() (src/zu_parse.c), the one text parser, against
 *     ref_parse() below, written from the grammar in zu_parse.c's header
 *     comment with unsigned __int128 arithmetic instead of zufast's;
 *   - zu_metadata_get_bounded() (src/zu_metadata.c), Arrow's binary schema
 *     metadata, against ref_metadata() below, written from the Arrow C Data
 *     Interface's description of the format;
 *   - zu_fx_parse() (src/zu_fixed.c), DuckDB's text to DECIMAL(p, s), against
 *     ref_dec_grammar() and ref_dec_exact() below, written from design 2.2:
 *     a text outside the grammar is invalid, one inside it is refused only
 *     as out of range, an accepted one is the exact value rounded half away
 *     from zero, and without an exponent the acceptance rule is the
 *     spec's. Its text then reads back to the same value. Each accepted
 *     value also goes through the rest of zu_fixed.c, each result checked:
 *     to double against zufast's zuf_parse_f64() of its text, which rounds
 *     correctly in every locale and FPU mode (DuckDB's two-word sum at
 *     scale 0 past 18 digits), back from double where that is exact,
 *     rescaling up and down again, comparison across scales, and c + c
 *     against c * 2.
 *
 * Every input goes to both. Any disagreement traps, so libFuzzer reports it
 * as a finding; ASan and UBSan catch the rest. The input is copied into a
 * buffer of exactly its size, so a read one byte past the end is an ASan
 * report, not a silent read of libFuzzer's buffer.
 *
 * Built by r-actions' fuzz.yml (.github/workflows/fuzz.yaml), and locally by
 * tools/fuzz/run-local for a plain random run without libFuzzer.
 */
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <zufast/number.h>

#include "zu_fixed.h"
#include "zu_metadata.h"
#include "zu_parse.h"

#define CHECK(cond) do { if (!(cond)) __builtin_trap(); } while (0)

/* ---- text ---------------------------------------------------------------- */

typedef unsigned __int128 u128;

static bool ref_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static int ref_digit(unsigned char c, unsigned base)
{
    int d = -1;
    if (c >= '0' && c <= '9') d = c - '0';
    if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
    if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
    return d >= 0 && (unsigned)d < base ? d : -1;
}

/* The grammar: optional surrounding whitespace, an optional sign, then
   decimal digits, or 0x/0X and hex digits, or 0b/0B and binary digits; a
   single '_' between two digits. "NA" or blank is NA. Beyond 128 bits is
   out of range; anything else is invalid. */
static zu_parse_status ref_parse(const unsigned char *s, size_t n, bool *neg, u128 *mag)
{
    size_t a = 0, b = n;
    while (a < b && ref_space(s[a])) a++;
    while (b > a && ref_space(s[b - 1])) b--;
    if (a == b || (b - a == 2 && s[a] == 'N' && s[a + 1] == 'A')) return ZU_PARSE_NA;

    *neg = false;
    if (s[a] == '+' || s[a] == '-') *neg = s[a++] == '-';

    unsigned base = 10;
    /* a prefix needs at least one character after it */
    if (b - a >= 3 && s[a] == '0' && (s[a + 1] | 0x20) == 'x') { base = 16; a += 2; }
    else if (b - a >= 3 && s[a] == '0' && (s[a + 1] | 0x20) == 'b') { base = 2; a += 2; }

    /* groups of one or more digits, separated by single underscores */
    if (a == b) return ZU_PARSE_INVALID;
    bool want_digit = true, big = false;
    u128 v = 0;
    for (size_t i = a; i < b; i++) {
        int d = ref_digit(s[i], base);
        if (d < 0) {
            if (s[i] != '_' || want_digit) return ZU_PARSE_INVALID;
            want_digit = true;
            continue;
        }
        want_digit = false;
        if (!big) {
            u128 max = ~(u128)0;
            if (v > (max - (u128)d) / base) big = true;
            else v = v * base + (u128)d;
        }
    }
    if (want_digit) return ZU_PARSE_INVALID;   /* empty, or a trailing '_' */
    if (big) return ZU_PARSE_RANGE;
    *mag = v;
    if (v == 0) *neg = false;
    return ZU_PARSE_OK;
}

static void fuzz_parse(const unsigned char *data, size_t size)
{
    zu_val got;
    bool rneg = false;
    u128 rmag = 0;
    zu_parse_status st = zu_parse((const char *)data, size, &got);
    zu_parse_status want = ref_parse(data, size, &rneg, &rmag);
    CHECK(st == want);
    if (st != ZU_PARSE_OK) return;
    u128 gmag = ((u128)zuf_u128_high(got.mag) << 64) | zuf_u128_low(got.mag);
    CHECK(gmag == rmag);
    CHECK(got.neg == rneg);
}

/* ---- Arrow binary metadata --------------------------------------------- */

static int32_t ref_i32(const unsigned char *p)
{
    int32_t v;
    memcpy(&v, p, 4);
    return v;
}

/* int32 count, then per entry an int32 key length, the key, an int32 value
   length and the value. A negative count or length, more than
   ZU_METADATA_MAX_ENTRIES entries, or bytes past the end: no metadata.
   Returns the offset of the first matching key's value, or -1. */
static long ref_metadata(const unsigned char *md, size_t n, const char *key, int32_t *len)
{
    size_t want = strlen(key), off = 0;
    if (n < 4) return -1;
    int32_t count = ref_i32(md);
    off = 4;
    if (count < 0 || count > ZU_METADATA_MAX_ENTRIES) return -1;
    for (int32_t i = 0; i < count; i++) {
        if (n - off < 4) return -1;
        int32_t kl = ref_i32(md + off);
        off += 4;
        if (kl < 0 || n - off < (size_t)kl) return -1;
        size_t k = off;
        off += (size_t)kl;
        if (n - off < 4) return -1;
        int32_t vl = ref_i32(md + off);
        off += 4;
        if (vl < 0 || n - off < (size_t)vl) return -1;
        if ((size_t)kl == want && memcmp(md + k, key, want) == 0) {
            *len = vl;
            return (long)off;
        }
        off += (size_t)vl;
    }
    return -1;
}

static void fuzz_metadata(const unsigned char *data, size_t size)
{
    static const char *keys[] = {"ARROW:extension:name", "ARROW:extension:metadata", "", "k"};
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++) {
        int32_t glen = -7, rlen = -7;
        const char *got = zu_metadata_get_bounded((const char *)data, (const char *)data + size, keys[i], &glen);
        long want = ref_metadata(data, size, keys[i], &rlen);
        if (want < 0) {
            CHECK(got == NULL);
        } else {
            CHECK(got == (const char *)data + want);
            CHECK(glen == rlen);
        }
    }
}

/* ---- DECIMAL text ---------------------------------------------------------- */

static bool ref_ddigit(unsigned char c) { return c >= '0' && c <= '9'; }

/* Digits with single '_' between two of them; returns the end, or NULL
   for a misplaced '_'. *any is set when there was a digit. */
static const unsigned char *ref_run(const unsigned char *p, const unsigned char *end, bool *any)
{
    while (p < end && ref_ddigit(*p)) {
        *any = true;
        p++;
        if (p < end && *p == '_') {
            if (p + 1 == end || !ref_ddigit(p[1])) return NULL;
            p++;
        }
    }
    return p;
}

/* Design 2.2's grammar: whitespace, a sign, digits, a point, digits (one
   digit at least), then an exponent: e or E, a sign and digits, and a
   point DuckDB lets end it; whitespace. A '_' sits between two digits. */
static bool ref_dec_grammar(const unsigned char *p, size_t n, bool *has_exp)
{
    const unsigned char *end = p + n;
    bool mant = false, edig = false;
    *has_exp = false;
    while (p < end && ref_space(*p)) p++;
    while (end > p && ref_space(end[-1])) end--;
    if (p < end && (*p == '+' || *p == '-')) p++;
    if (!(p = ref_run(p, end, &mant))) return false;
    if (p < end && *p == '.') {
        if (p + 1 < end && p[1] == '_') return false;
        if (!(p = ref_run(p + 1, end, &mant))) return false;
    }
    if (!mant) return false;
    if (p < end && (*p == 'e' || *p == 'E')) {
        *has_exp = true;
        p++;
        if (p < end && (*p == '+' || *p == '-')) p++;
        if (!(p = ref_run(p, end, &edig)) || !edig) return false;
        if (p < end && *p == '.') p++;
    }
    return p == end;
}

typedef struct {
    bool neg;
    unsigned char sig[64];
    long nsig, nint_sig, frac;
    long exponent; /* clamped well past any result */
} ref_dec;

static void ref_dec_read(const unsigned char *p, size_t n, ref_dec *x)
{
    const unsigned char *end = p + n;
    bool point = false;
    memset(x, 0, sizeof *x);
    while (p < end && ref_space(*p)) p++;
    if (p < end && (*p == '+' || *p == '-')) x->neg = *p++ == '-';
    for (; p < end && (ref_ddigit(*p) || *p == '_' || *p == '.'); p++) {
        if (*p == '.') { point = true; continue; }
        if (*p == '_') continue;
        if (point) x->frac++;
        if (x->nsig == 0 && *p == '0') continue;
        if (x->nsig < 64) x->sig[x->nsig] = (unsigned char)(*p - '0');
        x->nsig++;
        if (!point) x->nint_sig++;
    }
    if (p < end && (*p == 'e' || *p == 'E')) {
        bool eneg = false;
        p++;
        if (p < end && (*p == '+' || *p == '-')) eneg = *p++ == '-';
        for (; p < end && (ref_ddigit(*p) || *p == '_'); p++)
            if (*p != '_' && x->exponent < 1000000) x->exponent = x->exponent * 10 + (*p - '0');
        if (eneg) x->exponent = -x->exponent;
    }
}

/* The coefficient at scale s, half away from zero; false beyond 10^p. */
static bool ref_dec_exact(const ref_dec *x, int p, int s, bool *neg, u128 *mag)
{
    u128 m = 0, lim = 1;
    long keep = x->nsig + x->exponent - x->frac + s;
    for (int i = 0; i < p; i++) lim *= 10;
    *neg = false;
    if (x->nsig == 0 || keep < 0) { *mag = 0; return true; }
    if (keep > 38) return false;
    for (long i = 0; i < keep; i++) m = m * 10 + (i < x->nsig ? x->sig[i] : 0);
    if (keep < x->nsig && x->sig[keep] >= 5) m++;
    if (m >= lim) return false;
    *neg = x->neg && m != 0;
    *mag = m;
    return true;
}

static bool same(zuf_i128 a, zuf_i128 b) { return a.high == b.high && a.low == b.low; }

/* The rest of zu_fixed.c on one accepted value c of DECIMAL(p, s), whose
   text is `text`. */
static void fuzz_decimal_value(zuf_i128 c, int p, int s, const char *text)
{
    double d, want;
    zuf_i128 r, r2, one = zuf_int_i128_make(0, 1);
    zuf_u128 m = zuf_int_i128_magnitude(c);
    int cmp;
    bool small = m.high == 0 && m.low < UINT64_C(1000000000000000);

    /* to double: correctly rounded, so strtod() of the text, except
       DuckDB's sum of the two words at scale 0 past 18 digits */
    CHECK(zu_fx_to_double(c, p, s, &d) == ZU_FX_OK);
    if (s == 0 && p > 18) {
        int64_t hi;
        memcpy(&hi, &c.high, sizeof hi);
        want = hi == -1 ? -(double)(UINT64_MAX - c.low) - 1 : (double)c.low + (double)hi * 18446744073709551616.0;
    } else {
        /* zuf_parse_f64() reads ".50" and "-.05", and takes no '+' */
        {
            const char *end = text + strlen(text);
            zuf_result pr = zuf_parse_f64(text, end, &want);
            CHECK(pr.status == ZUF_OK && pr.ptr == end);
        }
    }
    CHECK(memcmp(&d, &want, sizeof d) == 0 || (d == 0 && want == 0));

    /* back from double: exact while c and 10^s are small enough */
    if (small && s <= 22) {
        CHECK(zu_fx_from_double(d, p, s, &r) == ZU_FX_OK);
        CHECK(same(r, c));
    }

    /* rescale up by k and back down is the value; it compares equal */
    for (int k = 1; s + k <= 38; k += 7) {
        if (zu_fx_rescale(c, s, 38, s + k, &r) != ZU_FX_OK) continue;
        CHECK(zu_fx_compare(c, s, r, s + k, &cmp) == ZU_FX_OK && cmp == 0);
        CHECK(zu_fx_compare(r, s + k, c, s, &cmp) == ZU_FX_OK && cmp == 0);
        CHECK(zu_fx_rescale(r, s + k, p, s, &r2) == ZU_FX_OK && same(r2, c));
    }
    /* down to scale 0, half away from zero: within half of the value */
    if (zu_fx_rescale(c, s, 38, 0, &r) == ZU_FX_OK && s > 0) {
        zuf_i128 up, scaled;
        /* the rounding can carry to 10^(38 - s), whose scale-s coefficient
           is 10^38: an overflow, and only then */
        int st = zu_fx_rescale(r, 0, 38, s, &up);
        CHECK(st == ZU_FX_OK || st == ZU_FX_OVERFLOW);
        if (st == ZU_FX_OVERFLOW) {
            /* at scale 38 any nonzero integer overflows */
            CHECK(s == 38 ? (r.high | r.low) != 0 : zu_fx_fits(r, 38 - s) == ZU_FX_OVERFLOW);
            goto arith;
        }
        CHECK(zu_fx_sub(up, c, &scaled) == ZU_FX_OK);
        {
            zuf_u128 diff = zuf_int_i128_magnitude(scaled), half = zuf_u128_from_u64(5);
            for (int i = 1; i < s; i++) half = zuf_u128_mul_wrap(half, zuf_u128_from_u64(10));
            CHECK(zuf_u128_cmp(diff, half) <= 0);
        }
    }

arith:
    /* c < c + 1, and c + c == c * 2 */
    if (zu_fx_add(c, one, &r) == ZU_FX_OK) {
        CHECK(zu_fx_compare(c, s, r, s, &cmp) == ZU_FX_OK && cmp == -1);
        CHECK(zu_fx_sub(r, one, &r2) == ZU_FX_OK && same(r2, c));
    }
    {
        /* near 10^38 both leave 128 bits: they agree, status and value */
        int sa = zu_fx_add(c, c, &r), sm = zu_fx_mul(c, zuf_int_i128_make(0, 2), &r2);
        CHECK(sa == sm && (sa == ZU_FX_OVERFLOW || (sa == ZU_FX_OK && same(r, r2))));
    }
    CHECK(zu_fx_fits(c, p) == ZU_FX_OK);
}

/* The contract's refusals, once. */
static void fuzz_decimal_contract(void)
{
    static bool done = false;
    zuf_i128 c = zuf_int_i128_make(0, 1), big = zuf_int_i128_make(UINT64_C(0x7fffffffffffffff), ~UINT64_C(0));
    double d;
    int cmp;
    size_t len;
    char buf[ZU_FX_MAX_CHARS];
    if (done) return;
    done = true;
    CHECK(zu_fx_type_check(0, 0) == ZU_FX_TYPE && zu_fx_type_check(39, 0) == ZU_FX_TYPE);
    CHECK(zu_fx_type_check(5, 6) == ZU_FX_TYPE && zu_fx_type_check(5, -1) == ZU_FX_TYPE);
    CHECK(zu_fx_fits(c, 0) == ZU_FX_TYPE && zu_fx_fits(big, 38) == ZU_FX_OVERFLOW);
    CHECK(zu_fx_parse("1", 1, 39, 0, &c) == ZU_FX_TYPE && zu_fx_parse("1", 1, 5, 2, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_parse(NULL, 1, 5, 2, &c) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_rescale(c, 39, 38, 0, &c) == ZU_FX_TYPE && zu_fx_rescale(c, 0, 38, 0, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_rescale(big, 0, 38, 1, &c) == ZU_FX_OVERFLOW);
    CHECK(zu_fx_format(c, 39, 0, buf, sizeof buf, &len) == ZU_FX_TYPE);
    CHECK(zu_fx_format(c, 5, 0, NULL, 0, &len) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_format(big, 38, 0, buf, sizeof buf, &len) == ZU_FX_OVERFLOW);
    CHECK(zu_fx_to_double(c, 38, 39, &d) == ZU_FX_TYPE && zu_fx_to_double(c, 38, 0, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_from_double(1, 38, 39, &c) == ZU_FX_TYPE && zu_fx_from_double(1, 38, 0, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_from_double(NAN, 38, 0, &c) == ZU_FX_INVALID && zu_fx_from_double(1e300, 38, 0, &c) == ZU_FX_OVERFLOW);
    CHECK(zu_fx_from_double(1e300, 38, 38, &c) == ZU_FX_OVERFLOW);
    CHECK(zu_fx_compare(c, 39, c, 0, &cmp) == ZU_FX_TYPE && zu_fx_compare(c, 0, c, 0, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_add(big, big, &c) == ZU_FX_OVERFLOW && zu_fx_add(c, c, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_sub(zuf_int_i128_make(UINT64_C(0x8000000000000000), 0), zuf_int_i128_make(0, 1), &c) == ZU_FX_OVERFLOW);
    CHECK(zu_fx_sub(c, c, NULL) == ZU_FX_ARGUMENT);
    CHECK(zu_fx_mul(big, big, &c) == ZU_FX_OVERFLOW && zu_fx_mul(c, c, NULL) == ZU_FX_ARGUMENT);
    for (int st = 0; st >= -5; st--) CHECK(zu_fx_strerror(st) != NULL);
    CHECK(zu_fx_strerror(1) == NULL);
}

static void fuzz_decimal(const unsigned char *data, size_t size)
{
    static const int types[][2] = {{38, 0}, {38, 10}, {38, 38}, {18, 4}, {9, 2}, {4, 4}, {5, 0}, {1, 0}};
    bool has_exp, grammar = ref_dec_grammar(data, size, &has_exp);
    ref_dec x;
    ref_dec_read(data, size, &x);
    for (size_t t = 0; t < sizeof types / sizeof types[0]; t++) {
        int p = types[t][0], s = types[t][1], st;
        bool rneg;
        u128 rmag;
        zuf_i128 c = zuf_int_i128_make(7, 7), back;
        st = zu_fx_parse((const char *)data, size, p, s, &c);
        if (!grammar) {
            CHECK(st == ZU_FX_INVALID);
            continue;
        }
        CHECK(st == ZU_FX_OK || st == ZU_FX_OVERFLOW);
        if (!has_exp) {
            /* the spec's rule: integer digits within p - s, and the
               rounded value below 10^p */
            bool fits = ref_dec_exact(&x, p, s, &rneg, &rmag);
            CHECK((st == ZU_FX_OK) == (fits && x.nint_sig <= p - s));
        }
        if (st != ZU_FX_OK) {
            CHECK(c.high == 7 && c.low == 7); /* untouched */
            continue;
        }
        CHECK(ref_dec_exact(&x, p, s, &rneg, &rmag));
        {
            zuf_u128 g = zuf_int_i128_magnitude(c);
            CHECK((((u128)g.high << 64) | g.low) == rmag);
            CHECK(zuf_i128_is_neg(c) == rneg);
        }
        {
            char buf[ZU_FX_MAX_CHARS + 1];
            size_t len;
            CHECK(zu_fx_format(c, p, s, buf, ZU_FX_MAX_CHARS, &len) == ZU_FX_OK);
            CHECK(zu_fx_parse(buf, len, p, s, &back) == ZU_FX_OK);
            CHECK(back.high == c.high && back.low == c.low);
            CHECK(len == 0 || zu_fx_format(c, p, s, buf, len - 1, &len) == ZU_FX_BUFFER);
            CHECK(zu_fx_format(c, p, s, buf, ZU_FX_MAX_CHARS, &len) == ZU_FX_OK);
            buf[len] = '\0';
            fuzz_decimal_value(c, p, s, buf);
        }
    }
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    unsigned char *copy = malloc(size ? size : 1);
    if (copy == NULL) return 0;
    if (size) memcpy(copy, data, size);
    fuzz_parse(copy, size);
    fuzz_metadata(copy, size);
    fuzz_decimal_contract();
    fuzz_decimal(copy, size);
    free(copy);
    return 0;
}
