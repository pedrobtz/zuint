/*
 * zu_hash.c -- duplicate detection (design 7): an open-addressing hash on
 * the exact raw words, never through double. NA is a value like any other
 * here, so the first NA is not a duplicate and later ones are, as in base R.
 */
#include "zu_wide.h"
#include <limits.h>

static uint64_t zu_mix(uint64_t z)
{
    /* splitmix64's finaliser */
    z ^= z >> 30;
    z *= UINT64_C(0xbf58476d1ce4e5b9);
    z ^= z >> 27;
    z *= UINT64_C(0x94d049bb133111eb);
    z ^= z >> 31;
    return z;
}

static void zu_words(SEXP x, zu_type t, R_xlen_t i, uint64_t *hi, uint64_t *lo)
{
    if (zu_type_is_128(t)) {
        zuf_u128 v = zu_get128(COMPLEX(x), i);
        *hi = zuf_u128_high(v);
        *lo = zuf_u128_low(v);
    } else {
        *hi = 0;
        *lo = zu_get64(REAL(x), i);
    }
}

/* TRUE where the value occurred earlier (or later, with from_last). */
SEXP zu_duplicated_c(SEXP x, SEXP type_, SEXP from_last_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool from_last = Rf_asLogical(from_last_) == TRUE;
    R_xlen_t n = XLENGTH(x);
    size_t size = 16;
    while (size < 2 * (size_t)n) size <<= 1;
    /* slot holds position + 1; 0 is empty */
    R_xlen_t *slots = (R_xlen_t *)R_alloc(size, sizeof(R_xlen_t));
    memset(slots, 0, size * sizeof(R_xlen_t));
    SEXP out = PROTECT(Rf_allocVector(LGLSXP, n));
    int *po = LOGICAL(out);
    for (R_xlen_t k = 0; k < n; k++) {
        R_xlen_t i = from_last ? n - 1 - k : k;
        uint64_t hi, lo;
        zu_words(x, t, i, &hi, &lo);
        size_t h = (size_t)(zu_mix(lo ^ zu_mix(hi + UINT64_C(0x9e3779b97f4a7c15))) & (size - 1));
        po[i] = FALSE;
        while (slots[h]) {
            uint64_t h2, l2;
            zu_words(x, t, slots[h] - 1, &h2, &l2);
            if (h2 == hi && l2 == lo) { po[i] = TRUE; break; }
            h = (h + 1) & (size - 1);
        }
        if (!po[i]) slots[h] = i + 1;
    }
    UNPROTECT(1);
    return out;
}

/* 1-based position of each x in table (both payloads of type t), or
   nomatch; the first occurrence in table wins, and NA matches NA. */
SEXP zu_match_c(SEXP x, SEXP table, SEXP type_, SEXP nomatch_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    zu_check_payload(table, t);
    int nomatch = Rf_asInteger(nomatch_);
    R_xlen_t n = XLENGTH(x), m = XLENGTH(table);
    if (m > INT_MAX) Rf_error("zuint: the table is too long to match against");
    size_t size = 16;
    while (size < 2 * (size_t)m) size <<= 1;
    R_xlen_t *slots = (R_xlen_t *)R_alloc(size, sizeof(R_xlen_t));
    memset(slots, 0, size * sizeof(R_xlen_t));
    for (R_xlen_t j = 0; j < m; j++) {
        uint64_t hi, lo;
        zu_words(table, t, j, &hi, &lo);
        size_t h = (size_t)(zu_mix(lo ^ zu_mix(hi + UINT64_C(0x9e3779b97f4a7c15))) & (size - 1));
        bool seen = false;
        while (slots[h]) {
            uint64_t h2, l2;
            zu_words(table, t, slots[h] - 1, &h2, &l2);
            if (h2 == hi && l2 == lo) { seen = true; break; }
            h = (h + 1) & (size - 1);
        }
        if (!seen) slots[h] = j + 1;
    }
    SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
    int *po = INTEGER(out);
    for (R_xlen_t i = 0; i < n; i++) {
        uint64_t hi, lo;
        zu_words(x, t, i, &hi, &lo);
        size_t h = (size_t)(zu_mix(lo ^ zu_mix(hi + UINT64_C(0x9e3779b97f4a7c15))) & (size - 1));
        po[i] = nomatch;
        while (slots[h]) {
            uint64_t h2, l2;
            zu_words(table, t, slots[h] - 1, &h2, &l2);
            if (h2 == hi && l2 == lo) { po[i] = (int)slots[h]; break; }
            h = (h + 1) & (size - 1);
        }
    }
    UNPROTECT(1);
    return out;
}
