# The decimal128 class (Stage 9.2) against DuckDB 2.0.1, whose casts,
# operators and typeof() are the oracle, and gmp for exact values.

# expr over a data frame registered as a table, one row per row of df, in
# order.
duck_df <- function(con, df, expr) {
  df$i <- seq_len(nrow(df))
  name <- paste0("dc_", paste(sample(letters, 12L, TRUE), collapse = ""))
  duckdb::duckdb_register(con, name, df)
  on.exit(duckdb::duckdb_unregister(con, name), add = TRUE)
  sql <- sprintf("SELECT %s AS r FROM %s ORDER BY i", expr, name)
  DBI::dbGetQuery(con, sql)$r
}

# DuckDB's type of an expression, as "DECIMAL(p,s)", or "ERROR" when it
# refuses to bind the types.
duck_typeof <- function(con, expr) {
  tryCatch(
    DBI::dbGetQuery(con, sprintf("SELECT typeof(%s) AS t", expr))$t,
    error = function(e) {
      # only DuckDB refusing the types (a scale past 38 is out of range); a
      # broken query is the test's own bug (#136)
      if (!grepl("^(Binder|Out of Range) Error", conditionMessage(e))) {
        stop(e)
      }
      "ERROR"
    }
  )
}

dec_typeof <- function(x) {
  sprintf("DECIMAL(%d,%d)", decimal_precision(x), decimal_scale(x))
}

dec_sql <- function(col, p, s) sprintf("CAST(%s AS DECIMAL(%d, %d))", col, p, s)

# n texts of DECIMAL(p, s) values, edges first, as DuckDB writes them.
dec_texts <- function(n, p, s, seed) {
  fx_format(fx_coefs(n, p, seed), p, s)
}

# Pairs of types the operator tests cross: small, mid, the 38-digit edge,
# scale 0 and scale p.
dec_type_pairs <- function() {
  types <- list(
    c(1L, 0L),
    c(4L, 4L),
    c(5L, 2L),
    c(9L, 3L),
    c(18L, 6L),
    c(19L, 0L),
    c(30L, 20L),
    c(37L, 2L),
    c(38L, 0L),
    c(38L, 10L),
    c(38L, 38L)
  )
  grid <- expand.grid(a = seq_along(types), b = seq_along(types))
  lapply(seq_len(nrow(grid)), function(k) {
    list(a = types[[grid$a[[k]]]], b = types[[grid$b[[k]]]])
  })
}

# A coefficient's sort key: text that sorts as the values do.
dec_sort_key <- function(coef) {
  neg <- startsWith(coef, "-")
  mag <- sub("^-", "", coef)
  mag <- paste0(strrep("0", 39L - nchar(mag)), mag)
  ifelse(
    is.na(coef),
    NA_character_,
    ifelse(
      neg,
      paste0("0", chartr("0123456789", "9876543210", mag)),
      paste0("1", mag)
    )
  )
}
