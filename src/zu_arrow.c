/*
 * zu_arrow.c -- the Arrow C Data Interface bridge (design 9.1).
 *
 * Formats:
 *   int64    "l"
 *   uint64   "L"
 *   int128   "w:16" + arrow.opaque {"type_name":"hugeint"}  (DuckDB's lossless
 *            export), or "d:P,0" with P <= 38 on import / "d:38,0" on request
 *   uint128  "w:16" + arrow.opaque {"type_name":"uhugeint"}
 *
 * A 128-bit value is 16 bytes of native-endian two's complement, low word
 * first on little-endian machines. A decimal128 is read as those bits with
 * no range check: DuckDB's default export writes HUGEINT values beyond 38
 * digits this way.
 *
 * Import copies (zero-copy waits for the ALTREP views) and borrows the
 * caller's structs: it never releases them. Export allocates the structs and
 * their buffers with malloc, because the consumer may call release from any
 * thread and so it must not touch R. The external pointers that carry the
 * exported structs release whatever is still owned when collected; a
 * consumer that moves a struct out (setting its release to NULL) takes that
 * job over.
 *
 * NA and null map to each other both ways. A valid engine value that equals
 * a type's NA bit pattern imports as NA and is counted as lost.
 */
#include "zu_wide.h"
#include "vendor/arrow/abi.h"
#include <stdlib.h>

#define ZU_ARROW_FLAG_NULLABLE 2

static int zu_little_endian(void)
{
    const uint16_t one = 1;
    unsigned char b;
    memcpy(&b, &one, 1);
    return b == 1;
}

static zuf_u128 zu_read16(const unsigned char *p)
{
    uint64_t w0, w1;
    memcpy(&w0, p, 8);
    memcpy(&w1, p + 8, 8);
    return zu_little_endian() ? zuf_u128_make(w1, w0) : zuf_u128_make(w0, w1);
}

static void zu_write16(unsigned char *p, zuf_u128 v)
{
    uint64_t lo = zuf_u128_low(v), hi = zuf_u128_high(v);
    if (zu_little_endian()) { memcpy(p, &lo, 8); memcpy(p + 8, &hi, 8); }
    else { memcpy(p, &hi, 8); memcpy(p + 8, &lo, 8); }
}

/* ---- schema metadata ---------------------------------------------------- */

/* Value of `key` in Arrow's binary metadata (int32 count, then int32-length
   keys and values), or NULL; *len receives its length. */
static const char *zu_metadata_get(const char *md, const char *key, int32_t *len)
{
    int32_t n, klen, vlen;
    size_t want = strlen(key);
    if (md == NULL) return NULL;
    memcpy(&n, md, 4);
    md += 4;
    for (int32_t i = 0; i < n; i++) {
        memcpy(&klen, md, 4);
        md += 4;
        const char *k = md;
        md += klen;
        memcpy(&vlen, md, 4);
        md += 4;
        if ((size_t)klen == want && memcmp(k, key, want) == 0) { *len = vlen; return md; }
        md += vlen;
    }
    return NULL;
}

/* The string value of "type_name" in the extension's JSON metadata. */
static bool zu_json_type_name(const char *js, int32_t len, const char *want)
{
    const char *key = "\"type_name\"", *end = js + len;
    size_t klen = strlen(key), wlen = strlen(want);
    for (const char *p = js; p + klen <= end; p++) {
        if (memcmp(p, key, klen) != 0) continue;
        p += klen;
        while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) p++;
        if (p == end || *p++ != ':') return false;
        while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) p++;
        if (p == end || *p++ != '"') return false;
        return (size_t)(end - p) > wlen && memcmp(p, want, wlen) == 0 && p[wlen] == '"';
    }
    return false;
}

/* The zuint type a schema maps to, or 0 with *why set. */
static int zu_schema_type(const struct ArrowSchema *s, const char **why)
{
    const char *f = s->format;
    *why = NULL;
    if (f == NULL) { *why = "the schema has no format"; return 0; }
    if (strcmp(f, "l") == 0) return ZU_INT64;
    if (strcmp(f, "L") == 0) return ZU_UINT64;
    if (strncmp(f, "d:", 2) == 0) {
        /* "d:P,S" or "d:P,S,128" */
        int p = 0, sc = -1, used = 0;
        bool ok = sscanf(f + 2, "%d,%d%n", &p, &sc, &used) == 2;
        const char *rest = f + 2 + used;
        if (!ok || p < 1 || p > 38 || (*rest != '\0' && strcmp(rest, ",128") != 0)) {
            *why = "only decimal128 with precision up to 38 maps to int128";
            return 0;
        }
        if (sc != 0) { *why = "a decimal with a non-zero scale is not an integer"; return 0; }
        return ZU_INT128;
    }
    if (strcmp(f, "w:16") == 0) {
        int32_t nlen = 0, mlen = 0;
        const char *name = zu_metadata_get(s->metadata, "ARROW:extension:name", &nlen);
        const char *md = zu_metadata_get(s->metadata, "ARROW:extension:metadata", &mlen);
        if (name && nlen == 12 && memcmp(name, "arrow.opaque", 12) == 0 && md) {
            if (zu_json_type_name(md, mlen, "hugeint")) return ZU_INT128;
            if (zu_json_type_name(md, mlen, "uhugeint")) return ZU_UINT128;
        }
        *why = "fixed-size binary maps to a zuint type only as DuckDB's arrow.opaque hugeint or uhugeint";
        return 0;
    }
    *why = "the format is not one zuint imports";
    return 0;
}

static const struct ArrowSchema *zu_schema_arg(SEXP schema)
{
    if (TYPEOF(schema) != EXTPTRSXP || R_ExternalPtrAddr(schema) == NULL)
        Rf_error("zuint: `schema` must be an external pointer to an ArrowSchema");
    const struct ArrowSchema *s = (const struct ArrowSchema *)R_ExternalPtrAddr(schema);
    if (s->release == NULL) Rf_error("zuint: the ArrowSchema has been released");
    return s;
}

static const struct ArrowArray *zu_array_arg(SEXP array)
{
    if (TYPEOF(array) != EXTPTRSXP || R_ExternalPtrAddr(array) == NULL)
        Rf_error("zuint: `array` must be an external pointer to an ArrowArray");
    const struct ArrowArray *a = (const struct ArrowArray *)R_ExternalPtrAddr(array);
    if (a->release == NULL) Rf_error("zuint: the ArrowArray has been released");
    if (a->length < 0 || a->offset < 0) Rf_error("zuint: the ArrowArray has a negative length or offset");
    if (a->n_buffers != 2) Rf_error("zuint: expected an ArrowArray with 2 buffers, not %d", (int)a->n_buffers);
    if (a->length > 0 && a->buffers[1] == NULL) Rf_error("zuint: the ArrowArray has no data buffer");
    return a;
}

/* The type code a schema maps to, or an R error saying why not. */
SEXP zu_arrow_type_c(SEXP schema)
{
    const char *why;
    int t = zu_schema_type(zu_schema_arg(schema), &why);
    return t ? Rf_ScalarInteger(t) : Rf_ScalarString(Rf_mkChar(why));
}

/* ---- import ------------------------------------------------------------- */

static bool zu_valid(const struct ArrowArray *a, int64_t j)
{
    const unsigned char *v = (const unsigned char *)a->buffers[0];
    return a->null_count == 0 || v == NULL || (v[j >> 3] >> (j & 7)) & 1;
}

/* list(payload, n_lost) for an array whose schema maps to `type`; with
   count_only, the payload is NULL and nothing is allocated. */
static SEXP zu_import(const struct ArrowArray *a, zu_type t, bool count_only)
{
    R_xlen_t n = (R_xlen_t)a->length, lost = 0;
    SEXP out = PROTECT(count_only ? R_NilValue : zu_alloc(t, n));
    const unsigned char *data = (const unsigned char *)a->buffers[1];
    for (R_xlen_t i = 0; i < n; i++) {
        int64_t j = a->offset + (int64_t)i;
        bool valid = zu_valid(a, j), sentinel;
        if (zu_type_is_128(t)) {
            zuf_u128 v = valid ? zu_read16(data + 16 * j) : zu_na128(t);
            sentinel = valid && zuf_u128_cmp(v, zu_na128(t)) == 0;
            if (!count_only) zu_set128(COMPLEX(out), i, valid ? v : zu_na128(t));
        } else {
            uint64_t v = 0;
            if (valid) memcpy(&v, data + 8 * j, 8);
            sentinel = valid && v == zu_na64(t);
            if (!count_only) zu_set64(REAL(out), i, valid ? v : zu_na64(t));
        }
        lost += sentinel;
    }
    SEXP res = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(res, 0, out);
    SET_VECTOR_ELT(res, 1, Rf_ScalarReal((double)lost));
    SET_VECTOR_ELT(res, 2, Rf_ScalarInteger(t));
    UNPROTECT(2);
    return res;
}

static zu_type zu_import_type(SEXP schema)
{
    const char *why;
    int t = zu_schema_type(zu_schema_arg(schema), &why);
    if (!t) Rf_error("zuint: cannot import this array: %s", why);
    return (zu_type)t;
}

SEXP zu_from_arrow_c(SEXP array, SEXP schema)
{
    zu_type t = zu_import_type(schema);
    return zu_import(zu_array_arg(array), t, false);
}

SEXP zu_sentinel_check_c(SEXP array, SEXP schema)
{
    zu_type t = zu_import_type(schema);
    return zu_import(zu_array_arg(array), t, true);
}

/* ---- export ------------------------------------------------------------- */

static long zu_arrow_releases = 0;   /* release callbacks run, for the tests */

typedef struct {
    const void *buffers[2];
} zu_array_private;

static void zu_release_array(struct ArrowArray *a)
{
    if (a == NULL || a->release == NULL) return;
    zu_array_private *p = (zu_array_private *)a->private_data;
    if (p) {
        free((void *)p->buffers[0]);
        free((void *)p->buffers[1]);
        free(p);
    }
    a->private_data = NULL;
    a->release = NULL;
    zu_arrow_releases++;
}

static void zu_release_schema(struct ArrowSchema *s)
{
    if (s == NULL || s->release == NULL) return;
    free(s->private_data);   /* the metadata, or NULL */
    s->private_data = NULL;
    s->metadata = NULL;
    s->release = NULL;
}

static void zu_finalize_array(SEXP xp)
{
    struct ArrowArray *a = (struct ArrowArray *)R_ExternalPtrAddr(xp);
    if (a == NULL) return;
    if (a->release) a->release(a);
    free(a);
    R_ClearExternalPtr(xp);
}

static void zu_finalize_schema(SEXP xp)
{
    struct ArrowSchema *s = (struct ArrowSchema *)R_ExternalPtrAddr(xp);
    if (s == NULL) return;
    if (s->release) s->release(s);
    free(s);
    R_ClearExternalPtr(xp);
}

/* An external pointer owning a zeroed struct of `size` bytes. */
static SEXP zu_owned_xptr(size_t size, R_CFinalizer_t fin, const char *tag)
{
    SEXP t = PROTECT(Rf_mkString(tag));
    SEXP xp = PROTECT(R_MakeExternalPtr(NULL, t, R_NilValue));
    R_RegisterCFinalizerEx(xp, fin, TRUE);
    void *p = calloc(1, size);
    if (p == NULL) Rf_error("zuint: out of memory");
    R_SetExternalPtrAddr(xp, p);
    UNPROTECT(2);
    return xp;
}

/* Arrow binary metadata for the arrow.opaque extension. */
static char *zu_opaque_metadata(const char *type_name)
{
    char json[64];
    const char *k1 = "ARROW:extension:name", *v1 = "arrow.opaque", *k2 = "ARROW:extension:metadata";
    int jlen = snprintf(json, sizeof json, "{\"type_name\":\"%s\",\"vendor_name\":\"DuckDB\"}", type_name);
    int32_t parts[5] = {2, (int32_t)strlen(k1), (int32_t)strlen(v1), (int32_t)strlen(k2), (int32_t)jlen};
    size_t size = 4 + 4 + parts[1] + 4 + parts[2] + 4 + parts[3] + 4 + parts[4];
    char *md = malloc(size), *p = md;
    if (md == NULL) return NULL;
    memcpy(p, &parts[0], 4); p += 4;
    memcpy(p, &parts[1], 4); p += 4; memcpy(p, k1, parts[1]); p += parts[1];
    memcpy(p, &parts[2], 4); p += 4; memcpy(p, v1, parts[2]); p += parts[2];
    memcpy(p, &parts[3], 4); p += 4; memcpy(p, k2, parts[3]); p += parts[3];
    memcpy(p, &parts[4], 4); p += 4; memcpy(p, json, parts[4]);
    return md;
}

/* Does |v| have at most 38 decimal digits? */
static bool zu_fits_decimal38(zu_val v)
{
    zuf_u128 limit = zuf_u128_from_u64(1), ten = zuf_u128_from_u64(10);
    for (int k = 0; k < 38; k++) zuf_u128_mul(limit, ten, &limit);
    return zuf_u128_cmp(v.mag, limit) < 0;
}

/* list(array, schema) external pointers holding x exported. */
SEXP zu_to_arrow_c(SEXP x, SEXP type_, SEXP decimal_)
{
    zu_type t = zu_type_arg(type_);
    bool decimal = Rf_asLogical(decimal_) == TRUE;
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), nulls = 0;
    size_t width = zu_type_is_128(t) ? 16 : 8;

    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) { nulls++; continue; }
        if (decimal && t == ZU_INT128 && !zu_fits_decimal38(zu_val_get(x, t, i)))
            Rf_error("zuint: a value has more than 38 digits and does not fit decimal128(38, 0)");
    }
    if (decimal && t != ZU_INT128) Rf_error("zuint: `decimal = TRUE` is for int128 only");

    SEXP res = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP sxp = zu_owned_xptr(sizeof(struct ArrowSchema), zu_finalize_schema, "zuint_arrow_schema");
    SET_VECTOR_ELT(res, 1, sxp);
    SEXP axp = zu_owned_xptr(sizeof(struct ArrowArray), zu_finalize_array, "zuint_arrow_array");
    SET_VECTOR_ELT(res, 0, axp);

    struct ArrowSchema *s = (struct ArrowSchema *)R_ExternalPtrAddr(sxp);
    char *md = NULL;
    if (zu_type_is_128(t) && !decimal) {
        md = zu_opaque_metadata(t == ZU_INT128 ? "hugeint" : "uhugeint");
        if (md == NULL) Rf_error("zuint: out of memory");
    }
    s->format = t == ZU_INT64 ? "l" : t == ZU_UINT64 ? "L" : decimal ? "d:38,0" : "w:16";
    s->name = "";
    s->metadata = md;
    s->flags = ZU_ARROW_FLAG_NULLABLE;
    s->private_data = md;
    s->release = zu_release_schema;

    struct ArrowArray *a = (struct ArrowArray *)R_ExternalPtrAddr(axp);
    zu_array_private *p = calloc(1, sizeof *p);
    unsigned char *data = malloc(n > 0 ? (size_t)n * width : 1);
    unsigned char *validity = nulls > 0 ? calloc(((size_t)n + 7) / 8, 1) : NULL;
    if (p == NULL || data == NULL || (nulls > 0 && validity == NULL)) {
        free(p); free(data); free(validity);
        Rf_error("zuint: out of memory");
    }
    for (R_xlen_t i = 0; i < n; i++) {
        bool na = zu_is_na(x, t, i);
        if (!na && validity) validity[i >> 3] |= (unsigned char)(1u << (i & 7));
        if (zu_type_is_128(t)) {
            zu_write16(data + 16 * i, na ? zuf_u128_make(0, 0) : zu_get128(COMPLEX(x), i));
        } else {
            uint64_t v = na ? 0 : zu_get64(REAL(x), i);
            memcpy(data + 8 * i, &v, 8);
        }
    }
    p->buffers[0] = validity;
    p->buffers[1] = data;
    a->length = (int64_t)n;
    a->null_count = (int64_t)nulls;
    a->offset = 0;
    a->n_buffers = 2;
    a->n_children = 0;
    a->buffers = p->buffers;
    a->private_data = p;
    a->release = zu_release_array;

    UNPROTECT(1);
    return res;
}

SEXP zu_arrow_releases_c(void) { return Rf_ScalarReal((double)zu_arrow_releases); }
