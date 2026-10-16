/*
 * zu_format.c -- wide integers to text (design 8): exact decimal through
 * zufast's writers, and hex or binary with a "0x" or "0b" prefix. Negative
 * values are written as a sign and a magnitude, "-0x1", so that every
 * string reads back through zu_parse() as the same value.
 */
#include "zu_wide.h"

SEXP zu_to_character_c(SEXP x, SEXP type_)
{
    zu_type t = zu_type_arg(type_);
    zu_check_payload(x, t);
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
    char buf[ZUF_I128_MAX_CHARS + 1];
    for (R_xlen_t i = 0; i < n; i++) {
        zu_val v = zu_val_get(x, t, i);
        char *p = buf;
        if (v.na) { SET_STRING_ELT(out, i, NA_STRING); continue; }
        if (v.neg) *p++ = '-';
        p = zuf_write_u128(p, v.mag);
        SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int)(p - buf), CE_UTF8));
    }
    UNPROTECT(1);
    return out;
}

/* base 16 or 2; with `pad`, every digit of the type's width is written. */
SEXP zu_format_base_c(SEXP x, SEXP type_, SEXP base_, SEXP pad_)
{
    zu_type t = zu_type_arg(type_);
    int base = Rf_asInteger(base_);
    bool pad = Rf_asLogical(pad_) == TRUE;
    if (base != 16 && base != 2) Rf_error("zuint: base must be 16 or 2");
    zu_check_payload(x, t);
    unsigned bits_per_digit = base == 16 ? 4 : 1, width = zu_type_is_128(t) ? 128 : 64;
    unsigned max_digits = width / bits_per_digit;
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
    char buf[1 + 2 + 128 + 1];
    static const char hex[] = "0123456789abcdef";
    for (R_xlen_t i = 0; i < n; i++) {
        zu_val v = zu_val_get(x, t, i);
        char *p = buf;
        if (v.na) { SET_STRING_ELT(out, i, NA_STRING); continue; }
        if (v.neg) *p++ = '-';
        *p++ = '0';
        *p++ = base == 16 ? 'x' : 'b';
        unsigned digits = pad ? max_digits : (zuf_int_u128_bit_width(v.mag) + bits_per_digit - 1) / bits_per_digit;
        if (digits == 0) digits = 1;
        for (unsigned k = digits; k-- > 0;) {
            zuf_u128 s = zuf_int_u128_shr(v.mag, k * bits_per_digit);
            *p++ = hex[zuf_u128_low(s) & (base == 16 ? 0xF : 0x1)];
        }
        SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int)(p - buf), CE_UTF8));
    }
    UNPROTECT(1);
    return out;
}
