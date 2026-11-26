/*
 * zu_fixed_r.c -- R entry points over the fixed-point core (design 2.2).
 *
 * Vectorised over an int128 payload (a CPLXSXP whose words are the
 * coefficients) or a character or double vector. NA is int128's sentinel,
 * which no coefficient of 38 digits or fewer equals. Every routine that can
 * lose a value returns list(result, status), an integer status per element
 * (NA where the input was NA), and R decides what to warn.
 *
 * zu_api_c() resolves the table through zuint-r.h from this translation
 * unit, as another package would, so the tests exercise the resolver.
 */
#include "zu_wide.h"
#include "zu_fixed.h"
#include "zuint-r.h"
#include "zu_api.h"

static void dec_type_arg(SEXP p, SEXP s, int *pp, int *ss)
{
    *pp = Rf_asInteger(p);
    *ss = Rf_asInteger(s);
    if (*pp == NA_INTEGER || *ss == NA_INTEGER || zu_fx_type_check(*pp, *ss) != ZU_FX_OK)
        Rf_error("zuint: precision must be 1 to 38 and scale 0 to the precision");
}

static int scale_arg(SEXP s)
{
    int v = Rf_asInteger(s);
    if (v == NA_INTEGER || v < 0 || v > ZU_FX_MAX_PRECISION) Rf_error("zuint: scale must be 0 to 38");
    return v;
}

static bool dec_get(SEXP x, R_xlen_t i, zuf_i128 *c)
{
    zuf_u128 b;
    if (zu_is_na(x, ZU_INT128, i)) return false;
    b = zu_get128(COMPLEX(x), i);
    *c = zuf_i128_from_u128(b);
    return true;
}

static void dec_set(SEXP x, R_xlen_t i, zuf_i128 c) { zu_set128(COMPLEX(x), i, zuf_u128_from_i128(c)); }

static SEXP dec_pair(SEXP value, SEXP status)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, status);
    UNPROTECT(1);
    return out;
}

static void dec_payload(SEXP x)
{
    if (TYPEOF(x) != CPLXSXP) Rf_error("zuint: a decimal payload must be complex");
}

SEXP zu_dec_parse_c(SEXP x, SEXP p, SEXP s)
{
    int pp, ss;
    R_xlen_t n, i;
    SEXP val, st;
    if (TYPEOF(x) != STRSXP) Rf_error("zuint: text must be a character vector");
    dec_type_arg(p, s, &pp, &ss);
    n = XLENGTH(x);
    val = PROTECT(Rf_allocVector(CPLXSXP, n));
    st = PROTECT(Rf_allocVector(INTSXP, n));
    for (i = 0; i < n; i++) {
        SEXP e = STRING_ELT(x, i);
        zuf_i128 c;
        int r;
        if (e == NA_STRING) {
            zu_set_na(val, ZU_INT128, i);
            INTEGER(st)[i] = NA_INTEGER;
            continue;
        }
        r = zu_fx_parse(CHAR(e), (size_t)LENGTH(e), pp, ss, &c);
        if (r == ZU_FX_OK) dec_set(val, i, c);
        else zu_set_na(val, ZU_INT128, i);
        INTEGER(st)[i] = r;
    }
    val = dec_pair(val, st);
    UNPROTECT(2);
    return val;
}

SEXP zu_dec_format_c(SEXP x, SEXP p, SEXP s)
{
    int pp, ss;
    R_xlen_t n, i;
    SEXP out;
    dec_payload(x);
    dec_type_arg(p, s, &pp, &ss);
    n = XLENGTH(x);
    out = PROTECT(Rf_allocVector(STRSXP, n));
    for (i = 0; i < n; i++) {
        char buf[ZU_FX_MAX_CHARS];
        size_t len;
        zuf_i128 c;
        if (!dec_get(x, i, &c) || zu_fx_format(c, pp, ss, buf, sizeof buf, &len) != ZU_FX_OK) {
            SET_STRING_ELT(out, i, NA_STRING);
            continue;
        }
        SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int)len, CE_UTF8));
    }
    UNPROTECT(1);
    return out;
}

SEXP zu_dec_rescale_c(SEXP x, SEXP s, SEXP p_to, SEXP s_to)
{
    int ss = scale_arg(s), pp, st_to;
    R_xlen_t n, i;
    SEXP val, st;
    dec_payload(x);
    dec_type_arg(p_to, s_to, &pp, &st_to);
    n = XLENGTH(x);
    val = PROTECT(Rf_allocVector(CPLXSXP, n));
    st = PROTECT(Rf_allocVector(INTSXP, n));
    for (i = 0; i < n; i++) {
        zuf_i128 c, r;
        int k;
        if (!dec_get(x, i, &c)) {
            zu_set_na(val, ZU_INT128, i);
            INTEGER(st)[i] = NA_INTEGER;
            continue;
        }
        k = zu_fx_rescale(c, ss, pp, st_to, &r);
        if (k == ZU_FX_OK) dec_set(val, i, r);
        else zu_set_na(val, ZU_INT128, i);
        INTEGER(st)[i] = k;
    }
    val = dec_pair(val, st);
    UNPROTECT(2);
    return val;
}

SEXP zu_dec_to_double_c(SEXP x, SEXP p, SEXP s)
{
    int pp, ss;
    R_xlen_t n, i;
    SEXP out;
    dec_payload(x);
    dec_type_arg(p, s, &pp, &ss);
    n = XLENGTH(x);
    out = PROTECT(Rf_allocVector(REALSXP, n));
    for (i = 0; i < n; i++) {
        zuf_i128 c;
        double v;
        if (!dec_get(x, i, &c) || zu_fx_to_double(c, pp, ss, &v) != ZU_FX_OK) v = NA_REAL;
        REAL(out)[i] = v;
    }
    UNPROTECT(1);
    return out;
}

SEXP zu_dec_from_double_c(SEXP x, SEXP p, SEXP s)
{
    int pp, ss;
    R_xlen_t n, i;
    SEXP val, st;
    if (TYPEOF(x) != REALSXP) Rf_error("zuint: a double vector is required");
    dec_type_arg(p, s, &pp, &ss);
    n = XLENGTH(x);
    val = PROTECT(Rf_allocVector(CPLXSXP, n));
    st = PROTECT(Rf_allocVector(INTSXP, n));
    for (i = 0; i < n; i++) {
        double v = REAL(x)[i];
        zuf_i128 c;
        int k;
        /* NaN is NA, as in the integer types' casts */
        if (ISNAN(v)) {
            zu_set_na(val, ZU_INT128, i);
            INTEGER(st)[i] = NA_INTEGER;
            continue;
        }
        k = zu_fx_from_double(v, pp, ss, &c);
        if (k == ZU_FX_OK) dec_set(val, i, c);
        else zu_set_na(val, ZU_INT128, i);
        INTEGER(st)[i] = k;
    }
    val = dec_pair(val, st);
    UNPROTECT(2);
    return val;
}

/* Elementwise over equal lengths; NA where either side is NA. */
SEXP zu_dec_compare_c(SEXP a, SEXP sa, SEXP b, SEXP sb)
{
    int s1 = scale_arg(sa), s2 = scale_arg(sb);
    R_xlen_t n, i;
    SEXP out;
    dec_payload(a);
    dec_payload(b);
    n = XLENGTH(a);
    if (XLENGTH(b) != n) Rf_error("zuint: lengths differ");
    out = PROTECT(Rf_allocVector(INTSXP, n));
    for (i = 0; i < n; i++) {
        zuf_i128 x, y;
        int r = NA_INTEGER;
        if (dec_get(a, i, &x) && dec_get(b, i, &y)) (void)zu_fx_compare(x, s1, y, s2, &r);
        INTEGER(out)[i] = r;
    }
    UNPROTECT(1);
    return out;
}

/* op 1, 2, 3: checked +, -, * on the coefficients. */
SEXP zu_dec_arith_c(SEXP op, SEXP a, SEXP b)
{
    int o = Rf_asInteger(op);
    R_xlen_t n, i;
    SEXP val, st;
    if (o < 1 || o > 3) Rf_error("zuint: invalid operator code %d", o);
    dec_payload(a);
    dec_payload(b);
    n = XLENGTH(a);
    if (XLENGTH(b) != n) Rf_error("zuint: lengths differ");
    val = PROTECT(Rf_allocVector(CPLXSXP, n));
    st = PROTECT(Rf_allocVector(INTSXP, n));
    for (i = 0; i < n; i++) {
        zuf_i128 x, y, r;
        int k;
        if (!dec_get(a, i, &x) || !dec_get(b, i, &y)) {
            zu_set_na(val, ZU_INT128, i);
            INTEGER(st)[i] = NA_INTEGER;
            continue;
        }
        k = o == 1 ? zu_fx_add(x, y, &r) : o == 2 ? zu_fx_sub(x, y, &r) : zu_fx_mul(x, y, &r);
        /* -2^127 is a valid int128 to the table, but here it is the NA
           pattern: an exact result on it is an overflow (design 6) */
        if (k == ZU_FX_OK && r.high == ZU_SIGN64 && r.low == 0) k = ZU_FX_OVERFLOW;
        if (k == ZU_FX_OK) dec_set(val, i, r);
        else zu_set_na(val, ZU_INT128, i);
        INTEGER(st)[i] = k;
    }
    val = dec_pair(val, st);
    UNPROTECT(2);
    return val;
}

/* The table as another package sees it, through zuint-r.h: list(abi
   version, struct size, whether each member is set), or NULL. */
SEXP zu_api_c(void)
{
    const zuint_api_v1 *api = zuint_api();
    static const char *names[] = {"dec_fits", "dec_rescale", "dec_parse", "dec_format",
                                  "dec_to_double", "dec_from_double", "dec_compare",
                                  "i128_add", "i128_sub", "i128_mul", "strerror"};
    SEXP out, filled, nm;
    int i, n = (int)(sizeof names / sizeof names[0]);
    if (api == NULL) return R_NilValue;
    out = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(out, 0, Rf_ScalarInteger((int)api->abi_version));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger((int)api->struct_size));
    filled = PROTECT(Rf_allocVector(LGLSXP, n));
    LOGICAL(filled)[0] = api->dec_fits != NULL;
    LOGICAL(filled)[1] = api->dec_rescale != NULL;
    LOGICAL(filled)[2] = api->dec_parse != NULL;
    LOGICAL(filled)[3] = api->dec_format != NULL;
    LOGICAL(filled)[4] = api->dec_to_double != NULL;
    LOGICAL(filled)[5] = api->dec_from_double != NULL;
    LOGICAL(filled)[6] = api->dec_compare != NULL;
    LOGICAL(filled)[7] = api->i128_add != NULL;
    LOGICAL(filled)[8] = api->i128_sub != NULL;
    LOGICAL(filled)[9] = api->i128_mul != NULL;
    LOGICAL(filled)[10] = api->strerror != NULL;
    nm = PROTECT(Rf_allocVector(STRSXP, n));
    for (i = 0; i < n; i++) SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(filled, R_NamesSymbol, nm);
    SET_VECTOR_ELT(out, 2, filled);
    UNPROTECT(3);
    return out;
}

/* The bytes of the table's members, so a test can tell the table grew
   without this list growing. */
SEXP zu_api_sizes_c(void)
{
    return Rf_ScalarInteger((int)(sizeof(zuint_api_v1) - 2 * sizeof(uint32_t)));
}

/* zuint_get_api() for a version, as the callable answers it. */
SEXP zu_api_version_c(SEXP version)
{
    int v = Rf_asInteger(version);
    if (v == NA_INTEGER || v < 0) return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(zuint_get_api((uint32_t)v) != NULL);
}

/* The message for a status. */
SEXP zu_dec_strerror_c(SEXP status)
{
    const char *m = zu_fx_strerror(Rf_asInteger(status));
    return m ? Rf_mkString(m) : Rf_ScalarString(NA_STRING);
}
