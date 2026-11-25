/*
 * zu_metadata.c -- Arrow's binary schema metadata, read without R, so the
 * fuzz target (tools/fuzz/harness.c) can build it alone.
 */
#include "zu_metadata.h"
#include <string.h>

/* Value of `key` in Arrow's binary metadata (int32 count, then int32-length
   keys and values), or NULL; *len receives its length. The format carries no
   total length, so an ArrowSchema's metadata cannot be bounded; `end`, when
   not NULL, bounds it (the tests pass one). A negative count or length, or
   too many entries, is corrupt and reads as no metadata. */
const char *zu_metadata_get_bounded(const char *md, const char *end, const char *key, int32_t *len)
{
    int32_t n, klen, vlen;
    size_t want = strlen(key);
#define ZU_HAVE(k) (end == NULL || (size_t)(end - md) >= (size_t)(k))
    if (md == NULL || !ZU_HAVE(4)) return NULL;
    memcpy(&n, md, 4);
    md += 4;
    if (n < 0 || n > ZU_METADATA_MAX_ENTRIES) return NULL;
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
