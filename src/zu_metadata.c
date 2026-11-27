/*
 * zu_metadata.c -- what an ArrowSchema says in text and bytes, read without
 * R, so the fuzz target (tools/fuzz/harness.c) can build it alone: Arrow's
 * binary schema metadata, the JSON of DuckDB's arrow.opaque extension, and
 * the decimal format string.
 */
#include "zu_metadata.h"
#include <string.h>

/* Value of `key` in Arrow's binary metadata (int32 count, then int32-length
   keys and values), or NULL; *len receives its length. The format carries no
   total length, so an ArrowSchema's metadata cannot be bounded; `end`, when
   not NULL, bounds it (the tests pass one). A negative count or length is
   corrupt and reads as no metadata. More than ZU_METADATA_MAX_ENTRIES
   entries also reads as none, and sets *too_many (when not NULL), so that
   the caller can refuse the schema rather than read it as another type
   (#166). */
const char *zu_metadata_get_bounded(const char *md, const char *end, const char *key, int32_t *len,
                                    bool *too_many)
{
    int32_t n, klen, vlen;
    size_t want = strlen(key);
    if (too_many) *too_many = false;
#define ZU_HAVE(k) (end == NULL || (size_t)(end - md) >= (size_t)(k))
    if (md == NULL || !ZU_HAVE(4)) return NULL;
    memcpy(&n, md, 4);
    md += 4;
    if (n < 0) return NULL;
    if (n > ZU_METADATA_MAX_ENTRIES) {
        if (too_many) *too_many = true;
        return NULL;
    }
    for (int32_t i = 0; i < n; i++) {
        if (!ZU_HAVE(4)) return NULL;
        memcpy(&klen, md, 4);
        md += 4;
        if (klen < 0 || !ZU_HAVE(klen)) return NULL;
        const char *k = md;
        md += klen;
        if (!ZU_HAVE(4)) return NULL;
        memcpy(&vlen, md, 4);
        md += 4;
        if (vlen < 0 || !ZU_HAVE(vlen)) return NULL;
        if ((size_t)klen == want && memcmp(k, key, want) == 0) { *len = vlen; return md; }
        md += vlen;
    }
#undef ZU_HAVE
    return NULL;
}

/* ---- the arrow.opaque extension's JSON ---------------------------------- */

/* JSON as RFC 8259 has it, and as simdjson, which Arrow reads the
   extension's metadata with, accepts it: UTF-8 throughout, no unpaired
   surrogate escape, nesting at most ZU_JSON_MAX_DEPTH deep, the top-level
   object counted. */
#define ZU_JSON_MAX_DEPTH 1024

typedef struct {
    const unsigned char *p, *end;
} zu_json;

static void zu_json_ws(zu_json *j)
{
    while (j->p < j->end && (*j->p == ' ' || *j->p == '\t' || *j->p == '\n' || *j->p == '\r')) j->p++;
}

/* One well-formed UTF-8 sequence of two to four bytes: no overlong form, no
   surrogate, nothing past U+10FFFF. */
static bool zu_json_utf8(zu_json *j)
{
    const unsigned char *p = j->p;
    unsigned c = p[0], n, cp;
    if (c >= 0xC2 && c <= 0xDF) n = 1;
    else if (c >= 0xE0 && c <= 0xEF) n = 2;
    else if (c >= 0xF0 && c <= 0xF4) n = 3;
    else return false;
    if ((size_t)(j->end - p) <= n) return false;
    cp = c & (0x3Fu >> n);
    for (unsigned k = 1; k <= n; k++) {
        if ((p[k] & 0xC0) != 0x80) return false;
        cp = (cp << 6) | (p[k] & 0x3Fu);
    }
    if (n == 2 && (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF))) return false;
    if (n == 3 && (cp < 0x10000 || cp > 0x10FFFF)) return false;
    j->p += n + 1;
    return true;
}

static bool zu_json_hex4(zu_json *j, unsigned *cp)
{
    if (j->end - j->p < 4) return false;
    unsigned v = 0;
    for (int k = 0; k < 4; k++) {
        unsigned c = j->p[k], d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else return false;
        v = v << 4 | d;
    }
    j->p += 4;
    *cp = v;
    return true;
}

/* A string, j->p on its opening quote. Its value, escapes decoded, goes to
   buf while it fits; *len is the value's whole length. Only ASCII values
   are ever compared, so a character past ASCII is written as the byte 0x80,
   which no ASCII text equals. */
static bool zu_json_string(zu_json *j, char *buf, size_t cap, size_t *len)
{
    size_t n = 0;
    j->p++;
    for (;;) {
        if (j->p == j->end) return false;
        unsigned c = *j->p, out;
        if (c == '"') {
            j->p++;
            *len = n;
            return true;
        }
        if (c < 0x20) return false;
        if (c == '\\') {
            if (j->end - j->p < 2) return false;
            unsigned e = j->p[1];
            j->p += 2;
            switch (e) {
            case '"': case '\\': case '/': out = e; break;
            case 'b': out = '\b'; break;
            case 'f': out = '\f'; break;
            case 'n': out = '\n'; break;
            case 'r': out = '\r'; break;
            case 't': out = '\t'; break;
            case 'u': {
                unsigned cp, lo;
                if (!zu_json_hex4(j, &cp)) return false;
                if (cp >= 0xDC00 && cp <= 0xDFFF) return false;
                if (cp >= 0xD800 && cp <= 0xDBFF) {
                    if (j->end - j->p < 2 || j->p[0] != '\\' || j->p[1] != 'u') return false;
                    j->p += 2;
                    if (!zu_json_hex4(j, &lo) || lo < 0xDC00 || lo > 0xDFFF) return false;
                }
                out = cp < 0x80 ? cp : 0x80;
                break;
            }
            default: return false;
            }
        } else if (c >= 0x80) {
            if (!zu_json_utf8(j)) return false;
            out = 0x80;
        } else {
            j->p++;
            out = c;
        }
        if (n < cap) buf[n] = (char)out;
        n++;
    }
}

static bool zu_json_digits(zu_json *j)
{
    const unsigned char *start = j->p;
    while (j->p < j->end && *j->p >= '0' && *j->p <= '9') j->p++;
    return j->p > start;
}

static bool zu_json_number(zu_json *j)
{
    if (*j->p == '-') j->p++;
    if (j->p == j->end) return false;
    if (*j->p == '0') j->p++;
    else if (!zu_json_digits(j)) return false;
    if (j->p < j->end && *j->p == '.') {
        j->p++;
        if (!zu_json_digits(j)) return false;
    }
    if (j->p < j->end && (*j->p == 'e' || *j->p == 'E')) {
        j->p++;
        if (j->p < j->end && (*j->p == '+' || *j->p == '-')) j->p++;
        if (!zu_json_digits(j)) return false;
    }
    return true;
}

static bool zu_json_word(zu_json *j, const char *w)
{
    size_t n = strlen(w);
    if ((size_t)(j->end - j->p) < n || memcmp(j->p, w, n) != 0) return false;
    j->p += n;
    return true;
}

/* A member's key and its colon, j->p on the key's quote. The key is given
   as written, escapes and all (*key, *len): Arrow finds a key by its
   unescaped bytes, as simdjson does, so "type_name" with an escape in it
   is another key. */
static bool zu_json_key(zu_json *j, const unsigned char **key, size_t *len)
{
    size_t n;
    if (j->p == j->end || *j->p != '"') return false;
    *key = j->p + 1;
    if (!zu_json_string(j, NULL, 0, &n)) return false;
    *len = (size_t)(j->p - 1 - *key);
    zu_json_ws(j);
    if (j->p == j->end || *j->p != ':') return false;
    j->p++;
    return true;
}

/* Any value, checked and passed over; nesting is followed with a stack
   rather than recursion. */
static bool zu_json_value(zu_json *j)
{
    unsigned char open[ZU_JSON_MAX_DEPTH - 1];
    int depth = 0;
    const unsigned char *key;
    size_t len;
    for (;;) {
        zu_json_ws(j);
        if (j->p == j->end) return false;
        unsigned c = *j->p;
        if (c == '{' || c == '[') {
            if (depth == ZU_JSON_MAX_DEPTH - 1) return false;   /* inside the top-level object */
            open[depth++] = (unsigned char)c;
            j->p++;
            zu_json_ws(j);
            if (j->p < j->end && *j->p == (c == '{' ? '}' : ']')) {
                j->p++;
                depth--;
            } else {
                if (c == '{' && !zu_json_key(j, &key, &len)) return false;
                continue;
            }
        } else if (c == '"') {
            if (!zu_json_string(j, NULL, 0, &len)) return false;
        } else if (c == '-' || (c >= '0' && c <= '9')) {
            if (!zu_json_number(j)) return false;
        } else if (!zu_json_word(j, "true") && !zu_json_word(j, "false") && !zu_json_word(j, "null")) {
            return false;
        }
        /* a value ended: close what it ends, or go on to the next one */
        for (;;) {
            if (depth == 0) return true;
            zu_json_ws(j);
            if (j->p == j->end) return false;
            unsigned char close = open[depth - 1] == '{' ? '}' : ']';
            if (*j->p == close) {
                j->p++;
                depth--;
                continue;
            }
            if (*j->p != ',') return false;
            j->p++;
            if (open[depth - 1] == '{') {
                zu_json_ws(j);
                if (!zu_json_key(j, &key, &len)) return false;
            }
            break;
        }
    }
}

/* Does the JSON name DuckDB's hugeint or uhugeint? It must be one valid
   JSON object whose own "vendor_name" is the string "DuckDB" and whose own
   "type_name" is "hugeint" or "uhugeint", the values with their escapes
   decoded and the keys as written; keys inside nested values, and key
   names inside strings, do not count. A repeated key counts once, the
   first time, as Arrow reads it. Arrow's parser looks only at the keys it
   wants, so it reads some invalid documents (a bad escape or number
   elsewhere, a trailing comma); zuint reads none (design 9.1). */
int zu_opaque_duckdb_type(const char *json, size_t len)
{
    zu_json j = {(const unsigned char *)json, (const unsigned char *)json + len};
    const unsigned char *key;
    char type[9], vendor[7];
    size_t klen, tlen = 0, vlen = 0;
    bool seen_t = false, seen_v = false, str_t = false, str_v = false;
    if (json == NULL) return ZU_OPAQUE_OTHER;
    zu_json_ws(&j);
    if (j.p == j.end || *j.p != '{') return ZU_OPAQUE_OTHER;
    j.p++;
    zu_json_ws(&j);
    if (j.p < j.end && *j.p == '}') {
        j.p++;
    } else {
        for (;;) {
            if (!zu_json_key(&j, &key, &klen)) return ZU_OPAQUE_OTHER;
            zu_json_ws(&j);
            bool is_t = !seen_t && klen == 9 && memcmp(key, "type_name", 9) == 0;
            bool is_v = !seen_v && klen == 11 && memcmp(key, "vendor_name", 11) == 0;
            seen_t |= is_t;
            seen_v |= is_v;
            if ((is_t || is_v) && j.p < j.end && *j.p == '"') {
                if (!zu_json_string(&j, is_t ? type : vendor, is_t ? sizeof type : sizeof vendor,
                                    is_t ? &tlen : &vlen))
                    return ZU_OPAQUE_OTHER;
                if (is_t) str_t = true;
                else str_v = true;
            } else if (!zu_json_value(&j)) {
                return ZU_OPAQUE_OTHER;
            }
            zu_json_ws(&j);
            if (j.p == j.end) return ZU_OPAQUE_OTHER;
            if (*j.p == '}') {
                j.p++;
                break;
            }
            if (*j.p != ',') return ZU_OPAQUE_OTHER;
            j.p++;
            zu_json_ws(&j);
        }
    }
    zu_json_ws(&j);
    if (j.p != j.end) return ZU_OPAQUE_OTHER;
    if (!str_v || vlen != 6 || memcmp(vendor, "DuckDB", 6) != 0 || !str_t) return ZU_OPAQUE_OTHER;
    if (tlen == 7 && memcmp(type, "hugeint", 7) == 0) return ZU_OPAQUE_HUGEINT;
    if (tlen == 8 && memcmp(type, "uhugeint", 8) == 0) return ZU_OPAQUE_UHUGEINT;
    return ZU_OPAQUE_OTHER;
}

/* ---- the decimal format string ------------------------------------------ */

/* One or more decimal digits, their value saturating at
   ZU_FORMAT_NUMBER_MAX: no sign, no space. */
static bool zu_format_number(const char **q, int *v)
{
    const char *p = *q;
    long acc = 0;
    while (*p >= '0' && *p <= '9') {
        acc = acc * 10 + (*p - '0');
        if (acc > ZU_FORMAT_NUMBER_MAX) acc = ZU_FORMAT_NUMBER_MAX;
        p++;
    }
    if (p == *q) return false;
    *v = (int)acc;
    *q = p;
    return true;
}

/* The Arrow C Data Interface's decimal format, "d:P,S" or "d:P,S,N": the
   precision, the scale and the bit width, 128 when absent. Only that form,
   with plain digits, is accepted (#156); the caller checks the ranges. */
bool zu_decimal_format(const char *format, int *precision, int *scale, int *bits)
{
    const char *q = format;
    if (q == NULL || q[0] != 'd' || q[1] != ':') return false;
    q += 2;
    if (!zu_format_number(&q, precision) || *q != ',') return false;
    q++;
    if (!zu_format_number(&q, scale)) return false;
    *bits = 128;
    if (*q == ',') {
        q++;
        if (!zu_format_number(&q, bits)) return false;
    }
    return *q == '\0';
}
