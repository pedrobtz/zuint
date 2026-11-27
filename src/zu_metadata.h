#ifndef ZUINT_METADATA_H
#define ZUINT_METADATA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* More entries than zuint reads: past it the lookup fails (#166). */
#define ZU_METADATA_MAX_ENTRIES 4096

const char *zu_metadata_get_bounded(const char *md, const char *end, const char *key, int32_t *len,
                                    bool *too_many);

/* What an arrow.opaque extension's JSON metadata names (#154). */
enum { ZU_OPAQUE_OTHER = 0, ZU_OPAQUE_HUGEINT = 1, ZU_OPAQUE_UHUGEINT = 2 };

int zu_opaque_duckdb_type(const char *json, size_t len);

/* A number in a format string above this reads as this (#156). */
#define ZU_FORMAT_NUMBER_MAX 100000

bool zu_decimal_format(const char *format, int *precision, int *scale, int *bits);

#endif /* ZUINT_METADATA_H */
