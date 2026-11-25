/*
 * Fuzz target for zuint's two readers of untrusted bytes, each compared
 * with a reference written from its specification, not from the code:
 *
 *   - zu_parse() (src/zu_parse.c), the one text parser, against
 *     ref_parse() below, written from the grammar in zu_parse.c's header
 *     comment with unsigned __int128 arithmetic instead of zufast's;
 *   - zu_metadata_get_bounded() (src/zu_metadata.c), Arrow's binary schema
 *     metadata, against ref_metadata() below, written from the Arrow C Data
 *     Interface's description of the format.
 *
 * Every input goes to both. Any disagreement traps, so libFuzzer reports it
 * as a finding; ASan and UBSan catch the rest. The input is copied into a
 * buffer of exactly its size, so a read one byte past the end is an ASan
 * report, not a silent read of libFuzzer's buffer.
 *
 * Built by r-actions' fuzz.yml (.github/workflows/fuzz.yaml), and locally by
 * tools/fuzz/run-local for a plain random run without libFuzzer.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

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

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    unsigned char *copy = malloc(size ? size : 1);
    if (copy == NULL) return 0;
    if (size) memcpy(copy, data, size);
    fuzz_parse(copy, size);
    fuzz_metadata(copy, size);
    free(copy);
    return 0;
}
