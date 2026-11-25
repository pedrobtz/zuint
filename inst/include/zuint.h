/* zuint.h -- zuint's public C ABI: fixed-point DECIMAL(p, s) on a 128-bit
 * coefficient, and checked 128-bit arithmetic (zuint design 2.2).
 *
 * Plain C99. It includes <stddef.h> and <stdint.h> only, and names no R:
 * code that is handed a zuint_api_v1 pointer (a database engine built
 * without R, say) needs this header alone. Resolving the table from an R
 * package needs zuint-r.h, which includes this one.
 *
 * Values. A DECIMAL(p, s) is a coefficient c with 1 <= p <= 38 and
 * 0 <= s <= p, meaning c / 10^s, with |c| < 10^p: DuckDB's DECIMAL. A
 * coefficient crosses this header as zuint_i128, two's complement in two
 * 64-bit words, low word first: the layout of DuckDB's hugeint_t.
 *
 * Every function gives DuckDB 2.0.0's answer, with two exceptions where
 * DuckDB's is wrong (zuint design 2.2): a text DuckDB reads as a value with
 * more than p digits is refused, and the digits DuckDB drops past its
 * storage width are kept.
 *
 * The rules for every member:
 *   - It may be called from any number of threads at once. It reads only
 *     its arguments and constant tables, and keeps no state.
 *   - It never calls R, allocates, prints, exits, throws, unwinds or
 *     longjmps. It returns ZUINT_OK or a negative ZUINT_ERR_* status;
 *     strerror() names each one.
 *   - Results go through out-pointers, which are left as they were when
 *     the status is not ZUINT_OK.
 *   - Text is a pointer and a length in bytes, never NUL-terminated.
 *
 * Versions. The table starts with abi_version and struct_size. Members are
 * appended and never reordered or removed: an append grows struct_size and
 * keeps ZUINT_ABI_VERSION; any other change bumps the version. A consumer
 * built against this header uses a table only when abi_version matches and
 * struct_size is at least sizeof(zuint_api_v1), as zuint_api() checks.
 */
#ifndef ZUINT_H
#define ZUINT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ZUINT_ABI_VERSION 1u

/* ---- statuses ----------------------------------------------------------- */

#define ZUINT_OK 0
#define ZUINT_ERR_OVERFLOW (-1) /* beyond 128 bits, or beyond the precision */
#define ZUINT_ERR_INVALID (-2)  /* text DuckDB does not read as a number, or a NaN or infinite double */
#define ZUINT_ERR_TYPE (-3)     /* a precision outside 1..38, or a scale outside 0..precision */
#define ZUINT_ERR_BUFFER (-4)   /* the output buffer is too small */
#define ZUINT_ERR_ARGUMENT (-5) /* a NULL pointer */

/* The longest text dec_format() writes: "-" and 37 digits, "." and one. */
#define ZUINT_DECIMAL_MAX_CHARS 40

/* ---- values ------------------------------------------------------------- */

typedef struct {
    uint64_t lo; /* bits 0..63 */
    uint64_t hi; /* bits 64..127; bit 127 is the sign */
} zuint_i128;

/* ---- the table ---------------------------------------------------------- */

typedef struct {
    uint32_t abi_version; /* ZUINT_ABI_VERSION */
    uint32_t struct_size; /* sizeof the table zuint built */

    /* ZUINT_OK when |c| < 10^p, ZUINT_ERR_OVERFLOW when not. */
    int (*dec_fits)(zuint_i128 c, int p);

    /* Casts DECIMAL(_, s) to DECIMAL(p_to, s_to): multiplies by a power of
     * ten, or divides rounding half away from zero, then checks p_to. */
    int (*dec_rescale)(zuint_i128 c, int s, int p_to, int s_to, zuint_i128 *out);

    /* Casts `len` bytes of text to DECIMAL(p, s), as DuckDB's VARCHAR cast
     * reads it: surrounding whitespace, a sign, '_' between digits, an
     * exponent; digits past s round half away from zero.
     * ZUINT_ERR_INVALID for text that is not such a number,
     * ZUINT_ERR_OVERFLOW for one that does not fit. */
    int (*dec_parse)(const char *text, size_t len, int p, int s, zuint_i128 *out);

    /* Writes DECIMAL(p, s) as DuckDB does ("1.50", "-0.05", and ".50" when
     * p == s) to `buf`, at most `cap` bytes and no NUL, and sets *len.
     * ZUINT_ERR_BUFFER when cap is too small; ZUINT_DECIMAL_MAX_CHARS is
     * always enough. */
    int (*dec_format)(zuint_i128 c, int p, int s, char *buf, size_t cap, size_t *len);

    /* Casts DECIMAL(p, s) to double: c / 10^s correctly rounded, except at
     * scale 0 with p > 18, where DuckDB sums the two words as doubles. */
    int (*dec_to_double)(zuint_i128 c, int p, int s, double *out);

    /* Casts a double to DECIMAL(p, s) as DuckDB does: round(x * 1e<s>) in
     * double arithmetic, half away from zero. */
    int (*dec_from_double)(double x, int p, int s, zuint_i128 *out);

    /* *out = -1, 0 or 1 as a / 10^sa <, == or > b / 10^sb, exactly. */
    int (*dec_compare)(zuint_i128 a, int sa, zuint_i128 b, int sb, int *out);

    /* Checked two's complement arithmetic on 128 bits. A decimal sum's
     * operands share a scale; a product's scale is the sum of theirs. They
     * check 128 bits only: dec_fits() checks a precision. */
    int (*i128_add)(zuint_i128 a, zuint_i128 b, zuint_i128 *out);
    int (*i128_sub)(zuint_i128 a, zuint_i128 b, zuint_i128 *out);
    int (*i128_mul)(zuint_i128 a, zuint_i128 b, zuint_i128 *out);

    /* A static message for a status, or NULL for one it does not know. */
    const char *(*strerror)(int status);
} zuint_api_v1;

/* The callable zuint registers as "zuint_get_api": the table of version
 * `version`, or NULL for a version it does not serve. */
typedef const zuint_api_v1 *(*zuint_get_api_fn)(uint32_t version);

#ifdef __cplusplus
}
#endif

#endif /* ZUINT_H */
