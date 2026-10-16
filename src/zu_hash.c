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

/* A payload's words, read once: 64-bit values have hi 0. */
typedef struct {
    const double *p64;
    const Rcomplex *p128;
} zu_words_src;

static zu_words_src zu_src(SEXP x, zu_type t)
{
    zu_words_src s;
    s.p64 = zu_type_is_128(t) ? NULL : REAL(x);
    s.p128 = zu_type_is_128(t) ? COMPLEX(x) : NULL;
    return s;
}

static inline void zu_word_at(zu_words_src s, R_xlen_t i, uint64_t *hi, uint64_t *lo)
{
    if (s.p64) { *hi = 0; *lo = zu_get64(s.p64, i); return; }
    zuf_u128 v = zu_get128(s.p128, i);
    *hi = zuf_u128_high(v);
    *lo = zuf_u128_low(v);
}

static inline size_t zu_slot(uint64_t hi, uint64_t lo, size_t mask)
{
    return (size_t)(zu_mix(lo ^ (hi * UINT64_C(0x9e3779b97f4a7c15))) & mask);
}

/* An open-addressing set of positions into one payload. */
typedef struct {
    R_xlen_t *slots;   /* position + 1; 0 is empty */
    size_t mask;
    zu_words_src src;
} zu_set;

static zu_set zu_set_new(SEXP x, zu_type t, R_xlen_t n)
{
    zu_set h;
    size_t size = 16;
    while (size < 2 * (size_t)n) size <<= 1;
    h.slots = (R_xlen_t *)R_alloc(size, sizeof(R_xlen_t));
    memset(h.slots, 0, size * sizeof(R_xlen_t));
    h.mask = size - 1;
    h.src = zu_src(x, t);
    return h;
}

/* The slot holding (hi, lo), or the empty slot where it would go. */
static inline size_t zu_set_find(const zu_set *h, uint64_t hi, uint64_t lo)
{
    size_t k = zu_slot(hi, lo, h->mask);
    while (h->slots[k]) {
        uint64_t h2, l2;
        zu_word_at(h->src, h->slots[k] - 1, &h2, &l2);
        if (h2 == hi && l2 == lo) break;
        k = (k + 1) & h->mask;
    }
    return k;
}

/* TRUE where the value occurred earlier (or later, with from_last). */
SEXP zu_duplicated_c(SEXP x, SEXP type_, SEXP from_last_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool from_last = Rf_asLogical(from_last_) == TRUE;
    R_xlen_t n = XLENGTH(x);
    zu_set h = zu_set_new(x, t, n);
    SEXP out = PROTECT(Rf_allocVector(LGLSXP, n));
    int *po = LOGICAL(out);
    for (R_xlen_t k = 0; k < n; k++) {
        R_xlen_t i = from_last ? n - 1 - k : k;
        uint64_t hi, lo;
        zu_word_at(h.src, i, &hi, &lo);
        size_t slot = zu_set_find(&h, hi, lo);
        po[i] = h.slots[slot] != 0;
        if (!po[i]) h.slots[slot] = i + 1;
    }
    UNPROTECT(1);
    return out;
}

/* The distinct values in order of first appearance, as a payload. For
   64-bit values the table holds the keys themselves, so a probe reads one
   cache line instead of following a position back into x. */
SEXP zu_unique_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), m = 0;
    if (!zu_type_is_128(t)) {
        size_t size = 16;
        unsigned bits = 4;
        while (size < 2 * (size_t)n) { size <<= 1; bits++; }
        uint64_t *keys = (uint64_t *)R_alloc(size, sizeof(uint64_t));
        unsigned char *used = (unsigned char *)R_alloc(size, 1);   /* cheap to clear */
        memset(used, 0, size);
        const double *p = REAL(x);
        SEXP out = PROTECT(zu_alloc(t, n));
        double *po = REAL(out);
        for (R_xlen_t i = 0; i < n; i++) {
            uint64_t v = zu_get64(p, i);
            size_t k = (size_t)((v * UINT64_C(0x9e3779b97f4a7c15)) >> (64 - bits));
            while (used[k] && keys[k] != v) k = (k + 1) & (size - 1);
            if (!used[k]) { used[k] = 1; keys[k] = v; zu_set64(po, m++, v); }
        }
        out = Rf_lengthgets(out, m);
        UNPROTECT(1);
        return out;
    }
    zu_set h = zu_set_new(x, t, n);
    R_xlen_t *keep = (R_xlen_t *)R_alloc((size_t)(n ? n : 1), sizeof(R_xlen_t));
    for (R_xlen_t i = 0; i < n; i++) {
        uint64_t hi, lo;
        zu_word_at(h.src, i, &hi, &lo);
        size_t slot = zu_set_find(&h, hi, lo);
        if (!h.slots[slot]) { h.slots[slot] = i + 1; keep[m++] = i; }
    }
    SEXP out = PROTECT(zu_alloc(t, m));
    for (R_xlen_t j = 0; j < m; j++) {
        if (zu_type_is_128(t)) zu_set128(COMPLEX(out), j, zu_get128(COMPLEX(x), keep[j]));
        else zu_set64(REAL(out), j, zu_get64(REAL(x), keep[j]));
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
    if (!zu_type_is_128(t)) {
        /* 64-bit: the keys inline, positions beside them */
        size_t size = 16;
        unsigned bits = 4;
        while (size < 2 * (size_t)m) { size <<= 1; bits++; }
        uint64_t *keys = (uint64_t *)R_alloc(size, sizeof(uint64_t));
        int *pos = (int *)R_alloc(size, sizeof(int));   /* position + 1; 0 is empty */
        memset(pos, 0, size * sizeof(int));
        const double *pt = REAL(table), *px = REAL(x);
        for (R_xlen_t j = 0; j < m; j++) {
            uint64_t v = zu_get64(pt, j);
            size_t k = (size_t)((v * UINT64_C(0x9e3779b97f4a7c15)) >> (64 - bits));
            while (pos[k] && keys[k] != v) k = (k + 1) & (size - 1);
            if (!pos[k]) { pos[k] = (int)j + 1; keys[k] = v; }
        }
        SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
        int *po = INTEGER(out);
        for (R_xlen_t i = 0; i < n; i++) {
            uint64_t v = zu_get64(px, i);
            size_t k = (size_t)((v * UINT64_C(0x9e3779b97f4a7c15)) >> (64 - bits));
            while (pos[k] && keys[k] != v) k = (k + 1) & (size - 1);
            po[i] = pos[k] ? pos[k] : nomatch;
        }
        UNPROTECT(1);
        return out;
    }
    zu_set h = zu_set_new(table, t, m);
    for (R_xlen_t j = 0; j < m; j++) {
        uint64_t hi, lo;
        zu_word_at(h.src, j, &hi, &lo);
        size_t slot = zu_set_find(&h, hi, lo);
        if (!h.slots[slot]) h.slots[slot] = j + 1;
    }
    zu_words_src xs = zu_src(x, t);
    SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
    int *po = INTEGER(out);
    for (R_xlen_t i = 0; i < n; i++) {
        uint64_t hi, lo;
        zu_word_at(xs, i, &hi, &lo);
        size_t slot = zu_set_find(&h, hi, lo);
        po[i] = h.slots[slot] ? (int)h.slots[slot] : nomatch;
    }
    UNPROTECT(1);
    return out;
}

/* The value as 2 (64-bit) or 4 (128-bit) 32-bit pieces in doubles, most
   significant first, the first signed for the signed types: rows compare
   and order as the values do, and never hold a NaN. NA is NA in every
   piece. The vctrs equality and ordering proxy. */
SEXP zu_pieces_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    int k = zu_type_is_128(t) ? 4 : 2;
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, k));
    for (int j = 0; j < k; j++) SET_VECTOR_ELT(out, j, Rf_allocVector(REALSXP, n));
    for (R_xlen_t i = 0; i < n; i++) {
        bool na = zu_is_na(x, t, i);
        uint64_t hi, lo;
        zu_words(x, t, i, &hi, &lo);
        uint64_t w[4] = {hi >> 32, hi & 0xFFFFFFFFu, lo >> 32, lo & 0xFFFFFFFFu};
        const uint64_t *p = k == 4 ? w : w + 2;
        for (int j = 0; j < k; j++) {
            double d = (double)p[j];
            if (j == 0 && zu_type_is_signed(t) && p[0] >= 0x80000000u) d -= 4294967296.0;
            REAL(VECTOR_ELT(out, j))[i] = na ? NA_REAL : d;
        }
    }
    UNPROTECT(1);
    return out;
}
