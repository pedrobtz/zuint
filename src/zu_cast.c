/*
 * zu_cast.c -- construction and conversion (design 8).
 *
 * Every entry point that can lose a value returns list(result, n_lost) and
 * leaves the warning to R, which knows the condition classes and the
 * calling function. A lost value becomes NA; it is never clamped.
 */
#include "zu_wide.h"
#include "zu_parse.h"
#include <math.h>

/* Source kinds for zu_cast_c(); positive values are zu_type codes. */
#define ZU_FROM_INT  0     /* logical or integer */
#define ZU_FROM_DBL (-1)
#define ZU_FROM_CHR (-2)

SEXP zu_alloc(zu_type t, R_xlen_t n) { return Rf_allocVector(zu_sexptype(t), n); }

static SEXP zu_pair(SEXP value, R_xlen_t lost)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(out, 0, value);
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)lost));
    UNPROTECT(1);
    return out;
}

static zu_val zu_val_from_double(double d, bool *lost)
{
    zuf_u128 mag;
    zuf_i128 s;
    *lost = false;
    if (ISNAN(d)) return zu_val_na();
    if (d >= 0) {
        if (zuf_u128_from_f64(d, &mag)) return zu_val_make(false, mag);
    } else if (zuf_i128_from_f64(d, &s)) {
        return zu_val_make(true, zu_negate_bits(zuf_u128_from_i128(s)));
    }
    *lost = true;   /* a fraction, an infinity, or beyond 128 bits */
    return zu_val_na();
}

/* Text through zu_parse(); "NA" and blanks are NA without a loss. */
static zu_val zu_val_from_string(SEXP s, bool *lost)
{
    zu_val v = zu_val_na();
    *lost = false;
    if (s == NA_STRING) return v;
    switch (zu_parse(CHAR(s), (size_t)LENGTH(s), &v)) {
    case ZU_PARSE_OK:
        return v;
    case ZU_PARSE_NA:
        return zu_val_na();
    default:
        *lost = true;
        return zu_val_na();
    }
}

SEXP zu_cast_c(SEXP x, SEXP from_, SEXP to_)
{
    int from = Rf_asInteger(from_);
    zu_type to = zu_type_arg(to_);
    R_xlen_t n = XLENGTH(x), lost = 0;
    SEXP out = PROTECT(zu_alloc(to, n));

    if (from == ZU_FROM_INT) {
        if (TYPEOF(x) != INTSXP && TYPEOF(x) != LGLSXP) Rf_error("zuint: expected an integer vector");
        const int *p = TYPEOF(x) == INTSXP ? INTEGER(x) : LOGICAL(x);
        for (R_xlen_t i = 0; i < n; i++) {
            zu_val v = p[i] == NA_INTEGER ? zu_val_na()
                : zu_val_make(p[i] < 0, zuf_u128_from_u64(p[i] < 0 ? UINT64_C(0) - (uint64_t)(int64_t)p[i]
                                                                    : (uint64_t)p[i]));
            if (!zu_val_put(out, to, i, v)) lost++;
        }
    } else if (from == ZU_FROM_DBL) {
        if (TYPEOF(x) != REALSXP) Rf_error("zuint: expected a double vector");
        const double *p = REAL(x);
        for (R_xlen_t i = 0; i < n; i++) {
            bool bad;
            zu_val v = zu_val_from_double(p[i], &bad);
            if (bad) lost++;
            if (!zu_val_put(out, to, i, v)) lost++;
        }
    } else if (from == ZU_FROM_CHR) {
        if (TYPEOF(x) != STRSXP) Rf_error("zuint: expected a character vector");
        for (R_xlen_t i = 0; i < n; i++) {
            bool bad;
            zu_val v = zu_val_from_string(STRING_ELT(x, i), &bad);
            if (bad) lost++;
            if (!zu_val_put(out, to, i, v)) lost++;
        }
    } else {
        zu_type ft = zu_type_arg(from_);
        zu_check_payload(x, ft);
        for (R_xlen_t i = 0; i < n; i++)
            if (!zu_val_put(out, to, i, zu_val_get(x, ft, i))) lost++;
    }
    out = zu_pair(out, lost);
    UNPROTECT(1);
    return out;
}

/* The magnitude rounded to the nearest double, ties to even. */
double zu_mag_to_double(zuf_u128 m)
{
    uint64_t high = zuf_u128_high(m), low = zuf_u128_low(m);
    unsigned k;
    uint64_t top;
    if (high == 0) return (double)low;
    /* keep the top 64 bits and fold the rest into a sticky bit, which sits
       far below the rounding position and so only breaks ties correctly */
    k = zuf_int_bit_width64(high);   /* 1..64: m >> k has exactly 64 bits */
    top = zuf_u128_low(zuf_int_u128_shr(m, k));
    if (k == 64 ? low != 0 : (low & ((UINT64_C(1) << k) - 1)) != 0) top |= 1;
    return ldexp((double)top, (int)k);
}

SEXP zu_to_double_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), inexact = 0;
    SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
    double *p = REAL(out);
    for (R_xlen_t i = 0; i < n; i++) {
        zu_val v = zu_val_get(x, t, i);
        double d;
        if (v.na) { p[i] = NA_REAL; continue; }
        if (!zuf_u128_to_f64(v.mag, &d)) { inexact++; d = zu_mag_to_double(v.mag); }
        p[i] = v.neg ? -d : d;
    }
    out = zu_pair(out, inexact);
    UNPROTECT(1);
    return out;
}

SEXP zu_to_integer_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), lost = 0;
    SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
    int *p = INTEGER(out);
    for (R_xlen_t i = 0; i < n; i++) {
        zu_val v = zu_val_get(x, t, i);
        if (v.na) { p[i] = NA_INTEGER; continue; }
        /* |v| <= 2^31 - 1; INT_MIN is R's NA */
        if (zuf_u128_high(v.mag) != 0 || zuf_u128_low(v.mag) > INT32_MAX) { p[i] = NA_INTEGER; lost++; continue; }
        p[i] = v.neg ? -(int)zuf_u128_low(v.mag) : (int)zuf_u128_low(v.mag);
    }
    out = zu_pair(out, lost);
    UNPROTECT(1);
    return out;
}

SEXP zu_is_na_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(Rf_allocVector(LGLSXP, n));
    int *p = LOGICAL(out);
    for (R_xlen_t i = 0; i < n; i++) p[i] = zu_is_na(x, t, i);
    UNPROTECT(1);
    return out;
}

/* A copy of x with the positions where `where` is TRUE set to NA. */
SEXP zu_fill_na_c(SEXP x, SEXP type_, SEXP where)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x);
    if (TYPEOF(where) != LGLSXP || XLENGTH(where) != n) Rf_error("zuint: bad NA mask");
    SEXP out = PROTECT(Rf_duplicate(x));
    const int *w = LOGICAL(where);
    for (R_xlen_t i = 0; i < n; i++)
        if (w[i] == TRUE) zu_set_na(out, t, i);
    UNPROTECT(1);
    return out;
}

/* c(min, max) of the non-NA values, as a payload of the same type; both NA
   when there are none, or when na_rm is FALSE and there is an NA. */
SEXP zu_range_c(SEXP x, SEXP type_, SEXP na_rm_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool na_rm = Rf_asLogical(na_rm_) == TRUE, seen = false, has_na = false;
    R_xlen_t n = XLENGTH(x);
    zu_val lo = zu_val_na(), hi = zu_val_na();
    for (R_xlen_t i = 0; i < n; i++) {
        zu_val v = zu_val_get(x, t, i);
        if (v.na) { has_na = true; continue; }
        if (!seen) { lo = hi = v; seen = true; continue; }
        if (zu_val_cmp(v, lo) < 0) lo = v;
        if (zu_val_cmp(v, hi) > 0) hi = v;
    }
    if (has_na && !na_rm) lo = hi = zu_val_na();
    SEXP out = PROTECT(zu_alloc(t, 2));
    zu_val_put(out, t, 0, lo);
    zu_val_put(out, t, 1, hi);
    UNPROTECT(1);
    return out;
}

SEXP zu_have_int128_c(void) { return Rf_ScalarLogical(ZUF_INT_HAVE_INT128); }
