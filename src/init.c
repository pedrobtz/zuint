#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

SEXP zu_cast_c(SEXP x, SEXP from, SEXP to);
SEXP zu_to_double_c(SEXP x, SEXP type);
SEXP zu_to_integer_c(SEXP x, SEXP type);
SEXP zu_to_character_c(SEXP x, SEXP type);
SEXP zu_is_na_c(SEXP x, SEXP type);
SEXP zu_fill_na_c(SEXP x, SEXP type, SEXP where);
SEXP zu_range_c(SEXP x, SEXP type, SEXP na_rm);
SEXP zu_have_int128_c(void);

static const R_CallMethodDef call_methods[] = {
  {"zu_cast_c", (DL_FUNC) &zu_cast_c, 3},
  {"zu_to_double_c", (DL_FUNC) &zu_to_double_c, 2},
  {"zu_to_integer_c", (DL_FUNC) &zu_to_integer_c, 2},
  {"zu_to_character_c", (DL_FUNC) &zu_to_character_c, 2},
  {"zu_is_na_c", (DL_FUNC) &zu_is_na_c, 2},
  {"zu_fill_na_c", (DL_FUNC) &zu_fill_na_c, 3},
  {"zu_range_c", (DL_FUNC) &zu_range_c, 3},
  {"zu_have_int128_c", (DL_FUNC) &zu_have_int128_c, 0},
  {NULL, NULL, 0}
};

void R_init_zuint(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
