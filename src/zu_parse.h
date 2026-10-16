#ifndef ZUINT_PARSE_H
#define ZUINT_PARSE_H

#include "zu_wide.h"

typedef enum {
    ZU_PARSE_OK = 0,       /* *out holds the value; it may still not fit a type */
    ZU_PARSE_NA = 1,       /* "NA" or blank: NA, silently */
    ZU_PARSE_INVALID = 2,  /* not an integer */
    ZU_PARSE_RANGE = 3     /* an integer beyond 128 bits */
} zu_parse_status;

zu_parse_status zu_parse(const char *s, size_t len, zu_val *out);

#endif /* ZUINT_PARSE_H */
