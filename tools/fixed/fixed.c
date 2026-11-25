/*
 * tools/fixed/fixed.c -- the fixed-point core's C tests, with no R
 * (design 2.2, Stage 9.1).
 *
 * It sees zuint only through inst/include/zuint.h and zuint_get_api(), as
 * a database engine does: it includes no R header and no zuint source
 * header, and links src/zu_fixed.c and src/zu_api.c.
 *
 *   fixed dectest FILE...  the General Decimal Arithmetic cases that apply
 *                          to fixed point: add, subtract, multiply, compare
 *                          and quantize under half_up, exact
 *   fixed diff             cases from tools/fixed/diff.py on stdin, each
 *                          with Python's decimal's answer
 *   fixed threads N        N threads through the table at once, against
 *                          one thread's results
 *
 * Each prints what it checked and exits 1 on the first wrong answer.
 */
#include "zuint.h"

#include <ctype.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const zuint_api_v1 *zuint_get_api(uint32_t version);

static const zuint_api_v1 *api;

/* ---- 128-bit words, written here, not taken from zuint --------------------- */

static zuint_i128 w_make(uint64_t hi, uint64_t lo)
{
    zuint_i128 v;
    v.hi = hi;
    v.lo = lo;
    return v;
}

static zuint_i128 w_add(zuint_i128 a, zuint_i128 b)
{
    uint64_t lo = a.lo + b.lo;
    return w_make(a.hi + b.hi + (lo < a.lo), lo);
}

static zuint_i128 w_neg(zuint_i128 a) { return w_add(w_make(~a.hi, ~a.lo), w_make(0, 1)); }

static zuint_i128 w_shl(zuint_i128 a, unsigned k) /* 1 <= k <= 63 */
{
    return w_make((a.hi << k) | (a.lo >> (64 - k)), a.lo << k);
}

/* a * 10 + d on a magnitude; false past 2^127. */
static bool w_mul10_add(zuint_i128 *a, unsigned d)
{
    zuint_i128 r;
    /* below 2^127 / 10 the product cannot leave two words; the sign bit
       check below then finds the rest */
    if (a->hi > UINT64_C(0x0ccccccccccccccc)) return false;
    r = w_add(w_add(w_shl(*a, 3), w_shl(*a, 1)), w_make(0, d));
    if (r.hi >> 63) return false;
    *a = r;
    return true;
}

static bool w_eq(zuint_i128 a, zuint_i128 b) { return a.hi == b.hi && a.lo == b.lo; }

/* A signed decimal integer, all of `s`, beyond int128 refused ("-2^127"
   included, which no test needs). */
static bool w_parse(const char *s, zuint_i128 *out)
{
    bool neg = false;
    zuint_i128 m = w_make(0, 0);
    if (*s == '-' || *s == '+') neg = *s++ == '-';
    if (!*s) return false;
    for (; *s; s++) {
        if (!isdigit((unsigned char)*s) || !w_mul10_add(&m, (unsigned)(*s - '0'))) return false;
    }
    *out = neg ? w_neg(m) : m;
    return true;
}

static void w_print(zuint_i128 v, char *buf, size_t cap)
{
    size_t n;
    if (api->dec_format(v, 38, 0, buf, cap - 1, &n) == ZUINT_OK) buf[n] = '\0';
    else snprintf(buf, cap, "0x%016" PRIx64 "%016" PRIx64, v.hi, v.lo);
}

/* ---- General Decimal Arithmetic numbers ------------------------------------- */

/* A finite GDA number: sign, coefficient digits, exponent. */
typedef struct {
    bool neg;
    char digits[400];
    long exponent;
} gda_number;

static bool gda_read(const char *s, gda_number *x)
{
    size_t n = 0;
    bool point = false, any = false;
    long frac = 0;
    memset(x, 0, sizeof *x);
    if (*s == '-' || *s == '+') x->neg = *s++ == '-';
    for (; *s && *s != 'e' && *s != 'E'; s++) {
        if (*s == '.') {
            if (point) return false;
            point = true;
            continue;
        }
        if (!isdigit((unsigned char)*s)) return false;
        any = true;
        if (point) frac++;
        if (n == 0 && *s == '0') continue;
        if (n + 1 >= sizeof x->digits) return false;
        x->digits[n++] = *s;
    }
    if (!any) return false;
    if (*s == 'e' || *s == 'E') {
        char *end;
        long e = strtol(s + 1, &end, 10);
        if (end == s + 1 || *end) return false;
        x->exponent = e;
    }
    x->exponent -= frac;
    return true;
}

/* As a coefficient at scale max(0, -exponent), when it fits 38 digits. */
static bool gda_coef(const gda_number *x, zuint_i128 *c, int *scale)
{
    size_t n = strlen(x->digits);
    zuint_i128 m = w_make(0, 0);
    long zeros = x->exponent > 0 ? x->exponent : 0;
    if (-x->exponent > 38) return false;
    if ((long)n + zeros > 38) return false;
    for (size_t i = 0; i < n; i++) (void)w_mul10_add(&m, (unsigned)(x->digits[i] - '0'));
    for (long i = 0; i < zeros && n > 0; i++) (void)w_mul10_add(&m, 0);
    *c = x->neg ? w_neg(m) : m;
    *scale = x->exponent < 0 ? (int)-x->exponent : 0;
    return true;
}

/* ---- dectest ------------------------------------------------------------------ */

/* Splits a line into tokens, quotes ' and " removed. */
static int tokens(char *line, char **tok, int max)
{
    int n = 0;
    char *p = line;
    while (*p && n < max) {
        while (isspace((unsigned char)*p)) p++;
        if (!*p) break;
        if (p[0] == '-' && p[1] == '-') break;
        if (*p == '\'' || *p == '"') {
            char q = *p++;
            tok[n++] = p;
            while (*p && *p != q) p++;
            if (*p) *p++ = '\0';
        } else {
            tok[n++] = p;
            while (*p && !isspace((unsigned char)*p)) p++;
            if (*p) *p++ = '\0';
        }
    }
    return n;
}

static bool finite_text(const char *s)
{
    for (; *s; s++) {
        int c = tolower((unsigned char)*s);
        if (c == 'n' || c == 'i' || c == 's' || c == '#') return false; /* NaN, Inf, sNaN, null */
    }
    return true;
}

static long dt_checked, dt_skipped;

static int dectest_file(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[4096], rounding[32] = "half_up";
    if (!f) {
        fprintf(stderr, "fixed: cannot open %s\n", path);
        return 1;
    }
    while (fgets(line, sizeof line, f)) {
        char *tok[16], *colon;
        int n, arrow = -1;
        line[strcspn(line, "\r\n")] = '\0';
        if ((colon = strchr(line, ':')) && !strstr(line, "->")) {
            char key[64] = "", val[64] = "";
            if (sscanf(line, " %63[^: ] : %63s", key, val) == 2) {
                for (char *k = key; *k; k++) *k = (char)tolower((unsigned char)*k);
                for (char *v = val; *v; v++) *v = (char)tolower((unsigned char)*v);
                if (strcmp(key, "rounding") == 0) snprintf(rounding, sizeof rounding, "%s", val);
            }
            continue;
        }
        n = tokens(line, tok, 16);
        for (int i = 0; i < n; i++)
            if (strcmp(tok[i], "->") == 0) arrow = i;
        if (n < 4 || arrow < 3 || arrow + 1 >= n) continue;
        {
            const char *id = tok[0], *op = tok[1];
            const char *xs = tok[2], *ys = arrow > 3 ? tok[3] : NULL, *rs = tok[arrow + 1];
            bool conditions = n > arrow + 2;
            bool is_add = strcmp(op, "add") == 0, is_sub = strcmp(op, "subtract") == 0;
            bool is_mul = strcmp(op, "multiply") == 0, is_cmp = strcmp(op, "compare") == 0;
            bool is_q = strcmp(op, "quantize") == 0;
            gda_number gx, gy, gr;
            zuint_i128 cx, cy, cr, got;
            int sx, sy, sr, st, cmp;
            if (!(is_add || is_sub || is_mul || is_cmp || is_q) || !ys) continue;
            if (!finite_text(xs) || !finite_text(ys) || !finite_text(rs)) {
                dt_skipped++;
                continue;
            }
            if (!gda_read(xs, &gx) || !gda_read(ys, &gy) || !gda_read(rs, &gr)) {
                dt_skipped++;
                continue;
            }
            /* exact operations only: a rounded GDA result is not ours */
            if ((is_add || is_sub || is_mul || is_cmp) && conditions) {
                dt_skipped++;
                continue;
            }
            if (is_q && strcmp(rounding, "half_up") != 0) {
                dt_skipped++;
                continue;
            }
            if (!gda_coef(&gx, &cx, &sx) || !gda_coef(&gr, &cr, &sr)) {
                dt_skipped++;
                continue;
            }
            if (is_q) {
                /* the result takes y's exponent */
                int target = gy.exponent <= 0 ? (int)-gy.exponent : -1;
                if (target < 0 || target > 38) {
                    dt_skipped++;
                    continue;
                }
                st = api->dec_rescale(cx, sx, 38, target, &got);
                if (st != ZUINT_OK) {
                    dt_skipped++; /* beyond 38 digits: GDA's precision is not ours */
                    continue;
                }
                if (api->dec_compare(got, target, cr, sr, &cmp) != ZUINT_OK || cmp != 0) {
                    fprintf(stderr, "fixed: %s %s: quantize %s %s -> %s\n", path, id, xs, ys, rs);
                    fclose(f);
                    return 1;
                }
                dt_checked++;
                continue;
            }
            if (!gda_coef(&gy, &cy, &sy)) {
                dt_skipped++;
                continue;
            }
            if (is_cmp) {
                int want = (int)strtol(rs, NULL, 10);
                if (api->dec_compare(cx, sx, cy, sy, &cmp) != ZUINT_OK || cmp != want) {
                    fprintf(stderr, "fixed: %s %s: compare %s %s -> %s, got %d\n", path, id, xs, ys, rs, cmp);
                    fclose(f);
                    return 1;
                }
                dt_checked++;
                continue;
            }
            if (is_mul) {
                if (sx + sy > 38 || api->i128_mul(cx, cy, &got) != ZUINT_OK || api->dec_fits(got, 38) != ZUINT_OK) {
                    dt_skipped++;
                    continue;
                }
                sr = sx + sy;
            } else {
                int s = sx > sy ? sx : sy;
                zuint_i128 ax, ay;
                if (api->dec_rescale(cx, sx, 38, s, &ax) != ZUINT_OK ||
                    api->dec_rescale(cy, sy, 38, s, &ay) != ZUINT_OK) {
                    dt_skipped++;
                    continue;
                }
                st = is_add ? api->i128_add(ax, ay, &got) : api->i128_sub(ax, ay, &got);
                if (st != ZUINT_OK || api->dec_fits(got, 38) != ZUINT_OK) {
                    dt_skipped++;
                    continue;
                }
                sr = s;
            }
            {
                int rsc;
                zuint_i128 want;
                if (!gda_coef(&gr, &want, &rsc) || api->dec_compare(got, sr, want, rsc, &cmp) != ZUINT_OK || cmp != 0) {
                    char b[64];
                    w_print(got, b, sizeof b);
                    fprintf(stderr, "fixed: %s %s: %s %s %s -> %s, got %s at scale %d\n", path, id, op, xs, ys, rs, b, sr);
                    fclose(f);
                    return 1;
                }
            }
            dt_checked++;
        }
    }
    fclose(f);
    return 0;
}

/* ---- diff ---------------------------------------------------------------------- */

static int hexval(int c) { return isdigit(c) ? c - '0' : tolower(c) - 'a' + 10; }

/* Hex text to bytes, in place; the length. */
static size_t unhex(char *s)
{
    size_t n = 0;
    for (size_t i = 0; s[i] && s[i + 1]; i += 2) s[n++] = (char)(hexval((unsigned char)s[i]) * 16 + hexval((unsigned char)s[i + 1]));
    return n;
}

static double bits_double(const char *hex)
{
    uint64_t b = strtoull(hex, NULL, 16);
    double d;
    memcpy(&d, &b, sizeof d);
    return d;
}

static uint64_t double_bits(double d)
{
    uint64_t b;
    memcpy(&b, &d, sizeof b);
    return b;
}

/* "ERR" against a status, or a coefficient against a value. */
static bool check_coef(int st, zuint_i128 got, const char *want)
{
    zuint_i128 w;
    if (strcmp(want, "ERR") == 0) return st == ZUINT_ERR_OVERFLOW;
    if (strcmp(want, "INV") == 0) return st == ZUINT_ERR_INVALID;
    return st == ZUINT_OK && w_parse(want, &w) && w_eq(got, w);
}

static int diff_mode(void)
{
    char line[8192];
    long n = 0, lineno = 0;
    while (fgets(line, sizeof line, stdin)) {
        char *f[8], *p = line;
        int k = 0;
        bool ok = false;
        zuint_i128 a, b, got = w_make(0, 0);
        int st;
        lineno++;
        line[strcspn(line, "\r\n")] = '\0';
        while (k < 8) {
            f[k++] = p;
            p = strchr(p, '\t');
            if (!p) break;
            *p++ = '\0';
        }
        if (strcmp(f[0], "parse") == 0 && k == 5) {
            size_t len = unhex(f[3]);
            st = api->dec_parse(f[3], len, atoi(f[1]), atoi(f[2]), &got);
            ok = check_coef(st, got, f[4]);
        } else if (strcmp(f[0], "format") == 0 && k == 5) {
            char buf[ZUINT_DECIMAL_MAX_CHARS];
            size_t len;
            if (w_parse(f[3], &a)) {
                st = api->dec_format(a, atoi(f[1]), atoi(f[2]), buf, sizeof buf, &len);
                ok = strcmp(f[4], "ERR") == 0 ? st == ZUINT_ERR_OVERFLOW
                                               : st == ZUINT_OK && len == strlen(f[4]) && memcmp(buf, f[4], len) == 0;
            }
        } else if (strcmp(f[0], "rescale") == 0 && k == 6) {
            if (w_parse(f[4], &a)) {
                st = api->dec_rescale(a, atoi(f[1]), atoi(f[2]), atoi(f[3]), &got);
                ok = check_coef(st, got, f[5]);
            }
        } else if (strcmp(f[0], "todouble") == 0 && k == 5) {
            double d = 0;
            if (w_parse(f[3], &a)) {
                st = api->dec_to_double(a, atoi(f[1]), atoi(f[2]), &d);
                ok = st == ZUINT_OK && double_bits(d) == strtoull(f[4], NULL, 16);
            }
        } else if (strcmp(f[0], "fromdouble") == 0 && k == 5) {
            st = api->dec_from_double(bits_double(f[3]), atoi(f[1]), atoi(f[2]), &got);
            ok = check_coef(st, got, f[4]);
        } else if (strcmp(f[0], "compare") == 0 && k == 6) {
            int c = 9;
            if (w_parse(f[3], &a) && w_parse(f[4], &b)) {
                st = api->dec_compare(a, atoi(f[1]), b, atoi(f[2]), &c);
                ok = st == ZUINT_OK && c == atoi(f[5]);
            }
        } else if ((strcmp(f[0], "add") == 0 || strcmp(f[0], "sub") == 0 || strcmp(f[0], "mul") == 0) && k == 4) {
            if (w_parse(f[1], &a) && w_parse(f[2], &b)) {
                st = f[0][0] == 'a' ? api->i128_add(a, b, &got) : f[0][0] == 's' ? api->i128_sub(a, b, &got) : api->i128_mul(a, b, &got);
                ok = check_coef(st, got, f[3]);
            }
        } else {
            fprintf(stderr, "fixed: diff line %ld: unknown case\n", lineno);
            return 1;
        }
        if (!ok) {
            char b2[64];
            w_print(got, b2, sizeof b2);
            fprintf(stderr, "fixed: diff line %ld: %s", lineno, f[0]);
            for (int i = 1; i < k; i++) fprintf(stderr, " %s", f[i]);
            fprintf(stderr, " (got %s)\n", b2);
            return 1;
        }
        n++;
    }
    printf("fixed diff: %ld cases agree with Python's decimal\n", n);
    return n > 0 ? 0 : 1;
}

/* ---- threads ---------------------------------------------------------------------- */

typedef struct {
    uint64_t seed, hash;
    long rounds;
} work;

static uint64_t xs(uint64_t *s)
{
    *s ^= *s << 13;
    *s ^= *s >> 7;
    *s ^= *s << 17;
    return *s;
}

static void mix(uint64_t *h, uint64_t v) { *h = (*h ^ v) * UINT64_C(0x100000001b3); }

static void *worker(void *arg)
{
    work *w = arg;
    uint64_t s = w->seed, h = UINT64_C(0xcbf29ce484222325);
    for (long r = 0; r < w->rounds; r++) {
        char text[48], buf[ZUINT_DECIMAL_MAX_CHARS];
        int p = 1 + (int)(xs(&s) % 38), sc = (int)(xs(&s) % (unsigned)(p + 1)), len = 0, st, cmp = 0;
        zuint_i128 c = w_make(0, 0), d = w_make(0, 0);
        size_t n = 0;
        double v = 0;
        if (xs(&s) & 1) text[len++] = '-';
        for (int i = 0, nd = 1 + (int)(xs(&s) % 40); i < nd; i++) {
            if (i == nd / 2) text[len++] = '.';
            text[len++] = (char)('0' + xs(&s) % 10);
        }
        st = api->dec_parse(text, (size_t)len, p, sc, &c);
        mix(&h, (uint64_t)st);
        if (st == ZUINT_OK) {
            mix(&h, c.lo);
            mix(&h, c.hi);
            st = api->dec_format(c, p, sc, buf, sizeof buf, &n);
            for (size_t i = 0; st == ZUINT_OK && i < n; i++) mix(&h, (unsigned char)buf[i]);
            st = api->dec_to_double(c, p, sc, &v);
            mix(&h, double_bits(v));
            st = api->dec_from_double(v, p, sc, &d);
            mix(&h, (uint64_t)st ^ d.lo ^ d.hi);
            st = api->dec_rescale(c, sc, 38, (int)(xs(&s) % 39), &d);
            mix(&h, (uint64_t)st ^ d.lo);
            st = api->dec_compare(c, sc, d, 0, &cmp);
            mix(&h, (uint64_t)cmp);
        }
    }
    w->hash = h;
    return NULL;
}

static int threads_mode(int n)
{
    work single[16], multi[16];
    pthread_t t[16];
    if (n < 2 || n > 16) n = 4;
    for (int i = 0; i < n; i++) {
        single[i].seed = multi[i].seed = UINT64_C(0x9e3779b97f4a7c15) * (uint64_t)(i + 1);
        single[i].rounds = multi[i].rounds = 20000;
        worker(&single[i]);
    }
    for (int i = 0; i < n; i++)
        if (pthread_create(&t[i], NULL, worker, &multi[i]) != 0) return 1;
    for (int i = 0; i < n; i++) pthread_join(t[i], NULL);
    for (int i = 0; i < n; i++) {
        if (single[i].hash != multi[i].hash) {
            fprintf(stderr, "fixed: thread %d differs from its single-threaded run\n", i);
            return 1;
        }
    }
    printf("fixed threads: %d threads agree with one thread\n", n);
    return 0;
}

int main(int argc, char **argv)
{
    api = zuint_get_api(ZUINT_ABI_VERSION);
    if (!api || api->struct_size < sizeof(zuint_api_v1) || zuint_get_api(ZUINT_ABI_VERSION + 1) != NULL) {
        fprintf(stderr, "fixed: zuint_get_api() did not give a version %u table\n", ZUINT_ABI_VERSION);
        return 1;
    }
    if (argc >= 2 && strcmp(argv[1], "dectest") == 0) {
        for (int i = 2; i < argc; i++)
            if (dectest_file(argv[i]) != 0) return 1;
        printf("fixed dectest: %ld cases checked, %ld outside fixed point skipped\n", dt_checked, dt_skipped);
        /* a suite that applies to nothing checks nothing */
        return dt_checked >= 1000 ? 0 : 1;
    }
    if (argc >= 2 && strcmp(argv[1], "diff") == 0) return diff_mode();
    if (argc >= 2 && strcmp(argv[1], "threads") == 0) return threads_mode(argc >= 3 ? atoi(argv[2]) : 4);
    fprintf(stderr, "usage: fixed dectest FILE... | diff | threads N\n");
    return 2;
}
