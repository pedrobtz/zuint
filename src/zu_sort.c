/*
 * zu_sort.c -- ordering (design 7): a stable LSD radix sort on unsigned keys.
 *
 * The key of a value is its raw words with the sign bit flipped for the
 * signed types, so unsigned key order is numeric order; complementing the
 * key sorts in decreasing order and keeps ties in their original order. A
 * pass whose byte is the same for every key is skipped. NAs are set aside
 * first and placed as `na.last` says.
 */
#include "zu_wide.h"
#include <limits.h>

typedef struct { uint64_t hi, lo; } zu_key;

static zu_key zu_key_of(SEXP x, zu_type t, R_xlen_t i, bool decreasing)
{
    zu_key k;
    if (zu_type_is_128(t)) {
        zuf_u128 v = zu_get128(COMPLEX(x), i);
        k.hi = zuf_u128_high(v) ^ (t == ZU_INT128 ? ZU_SIGN64 : 0);
        k.lo = zuf_u128_low(v);
    } else {
        k.hi = 0;
        k.lo = zu_get64(REAL(x), i) ^ (t == ZU_INT64 ? ZU_SIGN64 : 0);
    }
    if (decreasing) { k.hi = ~k.hi; k.lo = ~k.lo; }
    return k;
}

static unsigned zu_key_byte(zu_key k, unsigned b)
{
    return (unsigned)((b < 8 ? k.lo >> (8 * b) : k.hi >> (8 * (b - 8))) & 0xFF);
}

/* Sort idx[0..n) (0-based positions) by keys, stably; returns the array
   holding the result, which is idx or tmp. */
static R_xlen_t *zu_radix(zu_key *keys, zu_key *ktmp, R_xlen_t *idx, R_xlen_t *tmp, R_xlen_t n, unsigned bytes)
{
    R_xlen_t count[256];
    for (unsigned b = 0; b < bytes; b++) {
        memset(count, 0, sizeof count);
        for (R_xlen_t i = 0; i < n; i++) count[zu_key_byte(keys[i], b)]++;
        if (n == 0 || count[zu_key_byte(keys[0], b)] == n) continue;   /* constant byte */
        R_xlen_t pos = 0;
        for (unsigned v = 0; v < 256; v++) { R_xlen_t c = count[v]; count[v] = pos; pos += c; }
        for (R_xlen_t i = 0; i < n; i++) {
            R_xlen_t d = count[zu_key_byte(keys[i], b)]++;
            tmp[d] = idx[i];
            ktmp[d] = keys[i];
        }
        R_xlen_t *ti = idx; idx = tmp; tmp = ti;
        zu_key *tk = keys; keys = ktmp; ktmp = tk;
    }
    return idx;
}

/* The sorted positions of the non-NA values, and how many there are; the
   NA positions follow in na[] in their original order. */
static R_xlen_t zu_sorted(SEXP x, zu_type t, bool decreasing, R_xlen_t **out, R_xlen_t **na, R_xlen_t *n_na)
{
    R_xlen_t n = XLENGTH(x), m = 0, k = 0;
    zu_key *keys = (zu_key *)R_alloc((size_t)(n ? n : 1), sizeof(zu_key));
    zu_key *ktmp = (zu_key *)R_alloc((size_t)(n ? n : 1), sizeof(zu_key));
    R_xlen_t *idx = (R_xlen_t *)R_alloc((size_t)(n ? n : 1), sizeof(R_xlen_t));
    R_xlen_t *tmp = (R_xlen_t *)R_alloc((size_t)(n ? n : 1), sizeof(R_xlen_t));
    R_xlen_t *nas = (R_xlen_t *)R_alloc((size_t)(n ? n : 1), sizeof(R_xlen_t));
    for (R_xlen_t i = 0; i < n; i++) {
        if (zu_is_na(x, t, i)) { nas[k++] = i; continue; }
        keys[m] = zu_key_of(x, t, i, decreasing);
        idx[m++] = i;
    }
    *out = zu_radix(keys, ktmp, idx, tmp, m, zu_type_is_128(t) ? 16 : 8);
    *na = nas;
    *n_na = k;
    return m;
}

static SEXP zu_positions(R_xlen_t len)
{
    return Rf_allocVector(len > INT_MAX ? REALSXP : INTSXP, len);
}

static void zu_set_pos(SEXP v, R_xlen_t i, R_xlen_t pos1)
{
    if (TYPEOF(v) == INTSXP) INTEGER(v)[i] = (int)pos1;
    else REAL(v)[i] = (double)pos1;
}

/* 1-based order; na_last is TRUE, FALSE or NA (drop the NAs). */
SEXP zu_order_c(SEXP x, SEXP type_, SEXP decreasing_, SEXP na_last_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool decreasing = Rf_asLogical(decreasing_) == TRUE;
    int na_last = Rf_asLogical(na_last_);
    R_xlen_t *sorted, *nas, n_na;
    R_xlen_t m = zu_sorted(x, t, decreasing, &sorted, &nas, &n_na);
    R_xlen_t len = m + (na_last == NA_LOGICAL ? 0 : n_na), j = 0;
    SEXP out = PROTECT(zu_positions(len));
    if (na_last == FALSE) for (R_xlen_t i = 0; i < n_na; i++) zu_set_pos(out, j++, nas[i] + 1);
    for (R_xlen_t i = 0; i < m; i++) zu_set_pos(out, j++, sorted[i] + 1);
    if (na_last == TRUE) for (R_xlen_t i = 0; i < n_na; i++) zu_set_pos(out, j++, nas[i] + 1);
    UNPROTECT(1);
    return out;
}

/* Ranks for xtfrm(): ties share the lowest rank, NA stays NA. */
SEXP zu_rank_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x), *sorted, *nas, n_na;
    R_xlen_t m = zu_sorted(x, t, false, &sorted, &nas, &n_na);
    SEXP out = PROTECT(zu_positions(n));
    for (R_xlen_t i = 0; i < n_na; i++) {
        if (TYPEOF(out) == INTSXP) INTEGER(out)[nas[i]] = NA_INTEGER;
        else REAL(out)[nas[i]] = NA_REAL;
    }
    R_xlen_t rank = 0;
    for (R_xlen_t i = 0; i < m; i++) {
        if (i == 0) rank = 1;
        else {
            zu_key a = zu_key_of(x, t, sorted[i - 1], false), b = zu_key_of(x, t, sorted[i], false);
            if (a.hi != b.hi || a.lo != b.lo) rank = i + 1;
        }
        zu_set_pos(out, sorted[i], rank);
    }
    UNPROTECT(1);
    return out;
}

/* The non-NA values sorted, as a payload; the NAs are left to the caller.
   No positions are kept: the keys are the values. */
SEXP zu_sort_values_c(SEXP x, SEXP type_, SEXP decreasing_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    bool decreasing = Rf_asLogical(decreasing_) == TRUE;
    R_xlen_t n = XLENGTH(x), m = 0;
    if (!zu_type_is_128(t)) {
        const double *p = REAL(x);
        const uint64_t na = zu_na64(t), flip = (t == ZU_INT64 ? ZU_SIGN64 : 0) ^ (decreasing ? ~UINT64_C(0) : 0);
        uint64_t *a = (uint64_t *)R_alloc((size_t)(n ? n : 1), sizeof(uint64_t));
        uint64_t *b = (uint64_t *)R_alloc((size_t)(n ? n : 1), sizeof(uint64_t));
        for (R_xlen_t i = 0; i < n; i++) {
            uint64_t v = zu_get64(p, i);
            if (v != na) a[m++] = v ^ flip;
        }
        /* Long vectors: four 16-bit digits, all histograms in one read pass,
           written out so the loop unrolls. Short ones: eight 8-bit digits,
           without the 2 MB histogram the long path needs. */
        const bool wide = m >= 65536;
        const unsigned bits = wide ? 16 : 8, digits = wide ? 4 : 8;
        const size_t buckets = (size_t)1 << bits;
        const uint64_t mask = buckets - 1;
        R_xlen_t *count = (R_xlen_t *)R_alloc(buckets * digits, sizeof(R_xlen_t));
        memset(count, 0, buckets * digits * sizeof(R_xlen_t));
        if (wide) {
            for (R_xlen_t i = 0; i < m; i++) {
                uint64_t v = a[i];
                count[v & 0xFFFF]++;
                count[65536 + ((v >> 16) & 0xFFFF)]++;
                count[2 * 65536 + ((v >> 32) & 0xFFFF)]++;
                count[3 * 65536 + (v >> 48)]++;
            }
        } else {
            for (R_xlen_t i = 0; i < m; i++)
                for (unsigned d = 0; d < 8; d++) count[d * 256 + ((a[i] >> (8 * d)) & 0xFF)]++;
        }
        for (unsigned d = 0; d < digits; d++) {
            R_xlen_t *c = count + (size_t)d * buckets;
            unsigned sh = bits * d;
            if (m == 0 || c[(a[0] >> sh) & mask] == m) continue;   /* constant digit */
            R_xlen_t pos = 0;
            for (size_t v = 0; v < buckets; v++) { R_xlen_t k = c[v]; c[v] = pos; pos += k; }
            for (R_xlen_t i = 0; i < m; i++) b[c[(a[i] >> sh) & mask]++] = a[i];
            uint64_t *tmp = a; a = b; b = tmp;
        }
        SEXP out = PROTECT(zu_alloc(t, m));
        double *po = REAL(out);
        for (R_xlen_t i = 0; i < m; i++) zu_set64(po, i, a[i] ^ flip);
        UNPROTECT(1);
        return out;
    }
    R_xlen_t *sorted, *nas, n_na;
    m = zu_sorted(x, t, decreasing, &sorted, &nas, &n_na);
    SEXP out = PROTECT(zu_alloc(t, m));
    for (R_xlen_t i = 0; i < m; i++) zu_set128(COMPLEX(out), i, zu_get128(COMPLEX(x), sorted[i]));
    UNPROTECT(1);
    return out;
}
