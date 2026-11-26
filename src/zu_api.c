/*
 * zu_api.c -- zuint_api_v1, the table of inst/include/zuint.h (design 2.2).
 *
 * R-free, like zu_fixed.c: the C test binary in tools/fixed/ links this
 * file and calls through the table with no R in the process. Each member
 * converts zuint_i128 to zufast's word pair and calls zu_fixed.c; init.c
 * registers zuint_get_api() as the "zuint_get_api" callable.
 */
#include "zu_fixed.h"
#include "zu_api.h"

#include <string.h>

/* zu_fixed.c's statuses are zuint.h's numbers. */
typedef char zu_api_status_check[(ZU_FX_OK == ZUINT_OK && ZU_FX_OVERFLOW == ZUINT_ERR_OVERFLOW &&
                                   ZU_FX_INVALID == ZUINT_ERR_INVALID && ZU_FX_TYPE == ZUINT_ERR_TYPE &&
                                   ZU_FX_BUFFER == ZUINT_ERR_BUFFER &&
                                   ZU_FX_ARGUMENT == ZUINT_ERR_ARGUMENT && ZU_FX_MAX_CHARS == ZUINT_DECIMAL_MAX_CHARS)
                                      ? 1
                                      : -1];

static zuf_i128 api_in(zuint_i128 v) { return zuf_int_i128_make(v.hi, v.lo); }

static zuint_i128 api_out(zuf_i128 v)
{
    zuint_i128 r;
    r.lo = v.low;
    r.hi = v.high;
    return r;
}

static int api_dec_fits(zuint_i128 c, int p) { return zu_fx_fits(api_in(c), p); }

static int api_dec_rescale(zuint_i128 c, int s, int p_to, int s_to, zuint_i128 *out)
{
    zuf_i128 r;
    int st;
    if (!out) return ZUINT_ERR_ARGUMENT;
    st = zu_fx_rescale(api_in(c), s, p_to, s_to, &r);
    if (st == ZU_FX_OK) *out = api_out(r);
    return st;
}

static int api_dec_parse(const char *text, size_t len, int p, int s, zuint_i128 *out)
{
    zuf_i128 r;
    int st;
    if (!out) return ZUINT_ERR_ARGUMENT;
    st = zu_fx_parse(text, len, p, s, &r);
    if (st == ZU_FX_OK) *out = api_out(r);
    return st;
}

static int api_dec_format(zuint_i128 c, int p, int s, char *buf, size_t cap, size_t *len)
{
    return zu_fx_format(api_in(c), p, s, buf, cap, len);
}

static int api_dec_to_double(zuint_i128 c, int p, int s, double *out)
{
    return zu_fx_to_double(api_in(c), p, s, out);
}

static int api_dec_from_double(double x, int p, int s, zuint_i128 *out)
{
    zuf_i128 r;
    int st;
    if (!out) return ZUINT_ERR_ARGUMENT;
    st = zu_fx_from_double(x, p, s, &r);
    if (st == ZU_FX_OK) *out = api_out(r);
    return st;
}

static int api_dec_compare(zuint_i128 a, int sa, zuint_i128 b, int sb, int *out)
{
    return zu_fx_compare(api_in(a), sa, api_in(b), sb, out);
}

typedef int (*fx_binop)(zuf_i128, zuf_i128, zuf_i128 *);

static int api_binop(fx_binop f, zuint_i128 a, zuint_i128 b, zuint_i128 *out)
{
    zuf_i128 r;
    int st;
    if (!out) return ZUINT_ERR_ARGUMENT;
    st = f(api_in(a), api_in(b), &r);
    if (st == ZU_FX_OK) *out = api_out(r);
    return st;
}

static int api_i128_add(zuint_i128 a, zuint_i128 b, zuint_i128 *out) { return api_binop(zu_fx_add, a, b, out); }
static int api_i128_sub(zuint_i128 a, zuint_i128 b, zuint_i128 *out) { return api_binop(zu_fx_sub, a, b, out); }
static int api_i128_mul(zuint_i128 a, zuint_i128 b, zuint_i128 *out) { return api_binop(zu_fx_mul, a, b, out); }

static const zuint_api_v1 zu_api_table = {
    ZUINT_ABI_VERSION,
    (uint32_t)sizeof(zuint_api_v1),
    api_dec_fits,
    api_dec_rescale,
    api_dec_parse,
    api_dec_format,
    api_dec_to_double,
    api_dec_from_double,
    api_dec_compare,
    api_i128_add,
    api_i128_sub,
    api_i128_mul,
    zu_fx_strerror,
};

const zuint_api_v1 *zuint_get_api(uint32_t version)
{
    return version == ZUINT_ABI_VERSION ? &zu_api_table : NULL;
}
