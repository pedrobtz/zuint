/*
 * A main() for tools/fuzz/harness.c without libFuzzer: replays the files
 * named on the command line, then a fixed number of generated inputs from
 * a fixed seed. Any disagreement with the references traps, so the exit
 * status says whether every input agreed. tools/fuzz/Makefile builds it;
 * mutation.yaml runs it against each mutant.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

static uint64_t state = 0x9e3779b97f4a7c15u;

static uint64_t next(void)
{
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return state;
}

static size_t put(unsigned char *buf, size_t n, size_t cap, const char *s)
{
    size_t k = strlen(s);
    if (n + k > cap) return n;
    memcpy(buf + n, s, k);
    return n + k;
}

/* Text from the grammar's own pieces, so most inputs are near-valid. */
static size_t gen_text(unsigned char *buf, size_t cap)
{
    static const char *pre[] = {"", "", " ", "\t", "+", "-", "0x", "0X", "0b", "-0x", "+0b", "N", "NA"};
    static const char *piece[] = {"0", "1", "7", "9", "a", "F", "f", "g", "_", "__", " ", "x", "b",
                                  ".", "e", "E", "e-", "e+", "5", "-", "+", "\v"};
    size_t n = 0;
    n = put(buf, n, cap, pre[next() % (sizeof pre / sizeof pre[0])]);
    size_t len = next() % 48;
    for (size_t i = 0; i < len; i++) {
        uint64_t r = next() % 100;
        const char *p = r < 70 ? (const char[]){"0123456789abcdefABCDEF"[next() % 22], 0}
                               : piece[next() % (sizeof piece / sizeof piece[0])];
        n = put(buf, n, cap, p);
    }
    if (next() % 4 == 0) n = put(buf, n, cap, " ");
    return n;
}

/* Metadata: a count, then entries whose lengths are sometimes wrong. */
static size_t gen_metadata(unsigned char *buf, size_t cap)
{
    static const char *keys[] = {"ARROW:extension:name", "ARROW:extension:metadata", "k", ""};
    size_t n = 0;
    int32_t count = (int32_t)(next() % 6);
    if (next() % 10 == 0) count = (int32_t)(next() % 8192) - 4096;
    memcpy(buf, &count, 4);
    n = 4;
    for (int32_t i = 0; i < count && n + 64 < cap; i++) {
        const char *k = keys[next() % 4];
        int32_t kl = (int32_t)strlen(k), vl = (int32_t)(next() % 16);
        if (next() % 8 == 0) kl += (int32_t)(next() % 5) - 2;
        memcpy(buf + n, &kl, 4); n += 4;
        n = put(buf, n, cap, k);
        memcpy(buf + n, &vl, 4); n += 4;
        for (int32_t j = 0; j < vl && n < cap; j++) buf[n++] = (unsigned char)next();
    }
    if (n > 0 && next() % 6 == 0) n -= next() % n;   /* truncate */
    return n;
}

/* Metadata at the entry cap: count - 1 empty entries, then the key. */
static size_t gen_cap(unsigned char *buf, size_t cap)
{
    static const char key[] = "ARROW:extension:name";
    int32_t count = 4094 + (int32_t)(next() % 5), zero = 0, kl = (int32_t)strlen(key), vl = 1;
    size_t n = 0;
    memcpy(buf, &count, 4);
    n = 4;
    for (int32_t i = 0; i + 1 < count && n + 8 <= cap; i++) {
        memcpy(buf + n, &zero, 4);
        memcpy(buf + n + 4, &zero, 4);
        n += 8;
    }
    memcpy(buf + n, &kl, 4); n += 4;
    n = put(buf, n, cap, key);
    memcpy(buf + n, &vl, 4); n += 4;
    buf[n++] = 'x';
    return n;
}

/* JSON values from the grammar's own pieces; one in ten pieces is a near
   miss (a bad escape or number, a stray comma), so most documents are
   valid and the rest fail in one place. */
static size_t gen_json_value(unsigned char *buf, size_t n, size_t cap, int depth)
{
    static const char *str[] = {"\"hugeint\"", "\"uhugeint\"", "\"DuckDB\"", "\"\"", "\"huge\\u0069nt\"",
                                "\"Duck\\u0044B\"", "\"\\ud83d\\ude00\"", "\"\\\"type_name\\\"\"", "\"\xc3\xa9\"",
                                "\"a\\nb\\t\\/\\\\\""};
    static const char *bad[] = {"\"\\q\"", "01", "1.", "-", "\"\\ud800\"", "\"\\udc00x\"", "\"\xc3\"",
                                "\"\xed\xa0\x80\"", "\"\x01\"", "tru", "\"\\u12\"", ",", "[1,]", "{\"a\"}", "\""};
    static const char *num[] = {"0", "-1", "7", "-2.5e3", "1E+9", "0.125", "true", "false", "null"};
    uint64_t r = next() % 100;
    if (r < 8) return put(buf, n, cap, bad[next() % (sizeof bad / sizeof bad[0])]);
    if (r < 40) return put(buf, n, cap, str[next() % (sizeof str / sizeof str[0])]);
    if (r < 70 || depth > 3) return put(buf, n, cap, num[next() % (sizeof num / sizeof num[0])]);
    bool obj = r < 85;
    n = put(buf, n, cap, obj ? "{" : "[");
    int k = (int)(next() % 4);
    for (int i = 0; i < k; i++) {
        if (i) n = put(buf, n, cap, next() % 2 ? "," : " , ");
        if (obj) n = put(buf, n, cap, next() % 2 ? "\"type_name\":" : "\"x\" : ");
        n = gen_json_value(buf, n, cap, depth + 1);
    }
    return put(buf, n, cap, obj ? "}" : "]");
}

/* A top-level object whose members are often DuckDB's two keys. */
static size_t gen_json(unsigned char *buf, size_t cap)
{
    static const char *key[] = {"\"type_name\"", "\"vendor_name\"", "\"x\"", "\"type\\u005fname\"",
                                "\"vendor_name \"", "\"Type_name\""};
    static const char *ws[] = {"", "", " ", "\n", "\t", "\r", "\f"};
    size_t n = put(buf, 0, cap, next() % 20 ? "{" : "[");
    /* half the time DuckDB's two members, at random places among others */
    bool duck = next() % 2;
    int k = (int)(next() % 5) + (duck ? 2 : 0), at_t = duck ? (int)(next() % k) : -1, at_v = -1;
    if (duck) do at_v = (int)(next() % k); while (at_v == at_t);
    for (int i = 0; i < k; i++) {
        if (i) n = put(buf, n, cap, ",");
        n = put(buf, n, cap, ws[next() % 7]);
        if (i == at_t || i == at_v) {
            n = put(buf, n, cap, i == at_t ? "\"type_name\"" : "\"vendor_name\"");
            n = put(buf, n, cap, ws[next() % 7]);
            n = put(buf, n, cap, ":");
            n = put(buf, n, cap, i == at_v ? "\"DuckDB\"" : next() % 2 ? "\"hugeint\"" : "\"uhugeint\"");
            continue;
        }
        n = put(buf, n, cap, key[next() % 3 ? next() % 2 + 2 : next() % 6]);
        n = put(buf, n, cap, ws[next() % 7]);
        n = put(buf, n, cap, next() % 30 ? ":" : "");
        n = put(buf, n, cap, ws[next() % 7]);
        uint64_t r = next() % 10;
        n = r < 3 ? put(buf, n, cap, next() % 2 ? "\"hugeint\"" : "\"uhugeint\"")
          : r < 5 ? put(buf, n, cap, "\"DuckDB\"") : gen_json_value(buf, n, cap, 1);
    }
    n = put(buf, n, cap, ws[next() % 7]);
    n = put(buf, n, cap, next() % 20 ? "}" : "");
    if (next() % 10 == 0) n = put(buf, n, cap, next() % 2 ? " x" : " ");
    if (n && next() % 20 == 0) n -= next() % n;   /* truncate */
    return n;
}

/* Decimal format strings, near the spec's form. */
static size_t gen_format(unsigned char *buf, size_t cap)
{
    static const char *piece[] = {"d:", "d", ":", ",", "0", "1", "5", "38", "39", "128", "256", "4294967296",
                                  "99999999999999999999", "+", "-", " ", "x"};
    static const char *head[] = {"d:", "d:", "d:", "d", "D:", "", "d;", "dd:"};
    size_t n = put(buf, 0, cap, head[next() % 8]), len = next() % 8;
    for (size_t i = 0; i < len; i++) n = put(buf, n, cap, piece[next() % (sizeof piece / sizeof piece[0])]);
    if (n > 2 && next() % 5 == 0) n = 2 + next() % (n - 1);
    return n;
}

int main(int argc, char **argv)
{
    static unsigned char buf[65536];
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        if (f == NULL) { perror(argv[i]); return 2; }
        size_t n = fread(buf, 1, sizeof buf, f);
        fclose(f);
        LLVMFuzzerTestOneInput(buf, n);
    }
    const char *env = getenv("ZU_FUZZ_RUNS");
    long runs = env ? strtol(env, NULL, 10) : 200000;
    for (long i = 0; i < runs; i++) {
        size_t n = i % 1000 == 999 ? gen_cap(buf, sizeof buf)
                 : i % 4 == 1 ? gen_metadata(buf, 4096)
                 : i % 4 == 2 ? gen_json(buf, 4096)
                 : i % 4 == 3 ? gen_format(buf, 4096) : gen_text(buf, 4096);
        LLVMFuzzerTestOneInput(buf, n);
    }
    return 0;
}
