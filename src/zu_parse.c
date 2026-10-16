/*
 * zu_parse.c -- text to a wide integer, one implementation for every type
 * (design 8).
 *
 * Accepted: optional surrounding whitespace, an optional '+' or '-', then
 * decimal digits, or "0x"/"0X" and hex digits, or "0b"/"0B" and binary
 * digits. A single '_' may separate two digits. "NA" and an empty or blank
 * string are NA. Anything else -- exponents, fractions, a lone sign or
 * prefix, a misplaced '_' -- is invalid, and a value beyond 128 bits is out
 * of range; both are lost values, never a wrong one.
 */
#include "zu_parse.h"

static bool zu_is_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static int zu_digit(unsigned char c, unsigned base)
{
    unsigned d;
    if (c >= '0' && c <= '9') d = (unsigned)(c - '0');
    else if (c >= 'a' && c <= 'f') d = 10u + (unsigned)(c - 'a');
    else if (c >= 'A' && c <= 'F') d = 10u + (unsigned)(c - 'A');
    else return -1;
    return d < base ? (int)d : -1;
}

zu_parse_status zu_parse(const char *s, size_t len, zu_val *out)
{
    const unsigned char *p = (const unsigned char *)s, *end = p + len;
    unsigned base = 10;
    bool neg = false, ovf = false, any = false;
    zuf_u128 mag = zuf_u128_make(0, 0), b, d;

    while (p < end && zu_is_space(*p)) p++;
    while (end > p && zu_is_space(end[-1])) end--;
    if (p == end || (end - p == 2 && p[0] == 'N' && p[1] == 'A')) {
        *out = zu_val_na();
        return ZU_PARSE_NA;
    }
    if (*p == '+' || *p == '-') neg = *p++ == '-';
    if (end - p > 2 && p[0] == '0') {
        if (p[1] == 'x' || p[1] == 'X') { base = 16; p += 2; }
        else if (p[1] == 'b' || p[1] == 'B') { base = 2; p += 2; }
    }
    b = zuf_u128_from_u64(base);
    while (p < end) {
        int v = zu_digit(*p, base);
        if (v < 0) {
            /* '_' only between two digits */
            if (*p != '_' || !any || p + 1 == end || zu_digit(p[1], base) < 0) return ZU_PARSE_INVALID;
            p++;
            continue;
        }
        any = true;
        d = zuf_u128_from_u64((uint64_t)v);
        if (!ovf && (!zuf_u128_mul(mag, b, &mag) || !zuf_u128_add(mag, d, &mag))) ovf = true;
        p++;
    }
    if (!any) return ZU_PARSE_INVALID;
    if (ovf) return ZU_PARSE_RANGE;
    *out = zu_val_make(neg, mag);
    return ZU_PARSE_OK;
}
