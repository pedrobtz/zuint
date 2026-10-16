#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

SEXP zu_cast_c(SEXP x, SEXP from, SEXP to);
SEXP zu_arith_c(SEXP op, SEXP x, SEXP kx, SEXP y, SEXP ky, SEXP type, SEXP policy);
SEXP zu_neg_c(SEXP x, SEXP type, SEXP policy);
SEXP zu_abs_sign_c(SEXP x, SEXP type, SEXP sign);
SEXP zu_pow_c(SEXP x, SEXP kx, SEXP e, SEXP type, SEXP policy);
SEXP zu_compare_c(SEXP op, SEXP x, SEXP kx, SEXP y, SEXP ky);
SEXP zu_to_double_c(SEXP x, SEXP type);
SEXP zu_to_integer_c(SEXP x, SEXP type);
SEXP zu_to_character_c(SEXP x, SEXP type);
SEXP zu_is_na_c(SEXP x, SEXP type);
SEXP zu_fill_na_c(SEXP x, SEXP type, SEXP where);
SEXP zu_range_c(SEXP x, SEXP type, SEXP na_rm);
SEXP zu_have_int128_c(void);
SEXP zu_format_base_c(SEXP x, SEXP type, SEXP base, SEXP pad);
SEXP zu_bitop_c(SEXP op, SEXP x, SEXP y, SEXP type);
SEXP zu_bitcount_c(SEXP x, SEXP type, SEXP what);
SEXP zu_arrow_type_c(SEXP schema);
SEXP zu_from_arrow_c(SEXP array, SEXP schema);
SEXP zu_sentinel_check_c(SEXP array, SEXP schema);
SEXP zu_to_arrow_c(SEXP x, SEXP type, SEXP decimal);
SEXP zu_arrow_releases_c(void);
SEXP zu_arrow_released_c(SEXP xp);
SEXP zu_arrow_release_c(SEXP xp);
SEXP zu_order_c(SEXP x, SEXP type, SEXP decreasing, SEXP na_last);
SEXP zu_rank_c(SEXP x, SEXP type);
SEXP zu_duplicated_c(SEXP x, SEXP type, SEXP from_last);
SEXP zu_match_c(SEXP x, SEXP table, SEXP type, SEXP nomatch);
SEXP zu_sum_c(SEXP x, SEXP type, SEXP na_rm);
SEXP zu_prod_c(SEXP x, SEXP type, SEXP na_rm);
SEXP zu_cum_c(SEXP x, SEXP type, SEXP what);
SEXP zu_mean_c(SEXP x, SEXP type, SEXP na_rm);

static const R_CallMethodDef call_methods[] = {
  {"zu_cast_c", (DL_FUNC) &zu_cast_c, 3},
  {"zu_arith_c", (DL_FUNC) &zu_arith_c, 7},
  {"zu_neg_c", (DL_FUNC) &zu_neg_c, 3},
  {"zu_abs_sign_c", (DL_FUNC) &zu_abs_sign_c, 3},
  {"zu_pow_c", (DL_FUNC) &zu_pow_c, 5},
  {"zu_compare_c", (DL_FUNC) &zu_compare_c, 5},
  {"zu_to_double_c", (DL_FUNC) &zu_to_double_c, 2},
  {"zu_to_integer_c", (DL_FUNC) &zu_to_integer_c, 2},
  {"zu_to_character_c", (DL_FUNC) &zu_to_character_c, 2},
  {"zu_is_na_c", (DL_FUNC) &zu_is_na_c, 2},
  {"zu_fill_na_c", (DL_FUNC) &zu_fill_na_c, 3},
  {"zu_range_c", (DL_FUNC) &zu_range_c, 3},
  {"zu_have_int128_c", (DL_FUNC) &zu_have_int128_c, 0},
  {"zu_format_base_c", (DL_FUNC) &zu_format_base_c, 4},
  {"zu_bitop_c", (DL_FUNC) &zu_bitop_c, 4},
  {"zu_bitcount_c", (DL_FUNC) &zu_bitcount_c, 3},
  {"zu_arrow_type_c", (DL_FUNC) &zu_arrow_type_c, 1},
  {"zu_from_arrow_c", (DL_FUNC) &zu_from_arrow_c, 2},
  {"zu_sentinel_check_c", (DL_FUNC) &zu_sentinel_check_c, 2},
  {"zu_to_arrow_c", (DL_FUNC) &zu_to_arrow_c, 3},
  {"zu_arrow_releases_c", (DL_FUNC) &zu_arrow_releases_c, 0},
  {"zu_arrow_released_c", (DL_FUNC) &zu_arrow_released_c, 1},
  {"zu_arrow_release_c", (DL_FUNC) &zu_arrow_release_c, 1},
  {"zu_order_c", (DL_FUNC) &zu_order_c, 4},
  {"zu_rank_c", (DL_FUNC) &zu_rank_c, 2},
  {"zu_duplicated_c", (DL_FUNC) &zu_duplicated_c, 3},
  {"zu_match_c", (DL_FUNC) &zu_match_c, 4},
  {"zu_sum_c", (DL_FUNC) &zu_sum_c, 3},
  {"zu_prod_c", (DL_FUNC) &zu_prod_c, 3},
  {"zu_cum_c", (DL_FUNC) &zu_cum_c, 3},
  {"zu_mean_c", (DL_FUNC) &zu_mean_c, 3},
  {NULL, NULL, 0}
};

void R_init_zuint(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
