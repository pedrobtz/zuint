# A data frame that prints through pillar as a tibble does. pillar defines
# the print method for every `tbl`, so the tests need no tibble; the class is
# not `tbl_df`, so the header is the same whether tibble is loaded or not.
pillar_tbl <- function(df) {
  testthat::skip_if_not_installed("pillar")
  loadNamespace("pillar")
  class(df) <- c("tbl", "data.frame")
  df
}
