#ifndef ZUINT_METADATA_H
#define ZUINT_METADATA_H

#include <stdint.h>

/* More entries than any real schema carries: the metadata is corrupt. */
#define ZU_METADATA_MAX_ENTRIES 4096

const char *zu_metadata_get_bounded(const char *md, const char *end, const char *key, int32_t *len);

#endif /* ZUINT_METADATA_H */
