# The acceptance test (design 0, 12): for each engine type and each path,
# the schema and every value survive the trip into R and back. Since Stage 9
# every path goes through zuarrow, which reads zuint's registrations.

test_that("DuckDB -> R -> DuckDB keeps every type and value", {
  src <- duckdb_matrix_source()
  con <- src$con
  df <- duckdb_to_r(con, "SELECT * FROM src ORDER BY i")
  for (t in names(engine_types)) {
    type <- engine_types[[t]]
    expect_identical(
      df[[tolower(t)]],
      zu_ctor(type)(src$values[[type]]),
      label = t
    )
  }
  duckdb_register_df(con, "back", df)
  types <- function(tbl) {
    DBI::dbGetQuery(
      con,
      sprintf("SELECT column_name, column_type FROM (DESCRIBE %s)", tbl)
    )
  }
  expect_identical(types("back"), types("src"))
  diff <- DBI::dbGetQuery(
    con,
    "
    SELECT count(*) AS n FROM src s JOIN back b USING (i)
    WHERE s.bigint IS DISTINCT FROM b.bigint OR s.ubigint IS DISTINCT FROM b.ubigint
       OR s.hugeint IS DISTINCT FROM b.hugeint OR s.uhugeint IS DISTINCT FROM b.uhugeint"
  )
  expect_identical(diff$n, 0)
  expect_identical(
    DBI::dbGetQuery(con, "SELECT count(*) AS n FROM back")$n,
    as.numeric(nrow(df))
  )
})

test_that("Arrow -> R -> Arrow keeps the schema and every value", {
  src <- duckdb_matrix_source()
  skip_if_not_installed("arrow")
  t0 <- arrow::as_arrow_table(DBI::dbGetQueryArrow(
    src$con,
    "SELECT * EXCLUDE (i) FROM src ORDER BY i"
  ))
  df <- arrow_table_to_r(t0)
  t1 <- arrow_table_of(df)
  expect_true(t1$schema$Equals(t0$schema))
  expect_true(t1$Equals(t0))
})

test_that("Parquet -> R -> Parquet keeps the schema and every value", {
  skip_without_zuarrow()
  skip_if_not_installed("arrow")
  df <- as.data.frame(lapply(engine_types, function(type) {
    zu_ctor(type)(matrix_values(type))
  }))
  f1 <- withr::local_tempfile(fileext = ".parquet")
  f2 <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(arrow_table_of(df), f1)
  t1 <- arrow::read_parquet(f1, as_data_frame = FALSE)
  back <- arrow_table_to_r(t1)
  expect_identical(back, df)
  arrow::write_parquet(arrow_table_of(back), f2)
  t2 <- arrow::read_parquet(f2, as_data_frame = FALSE)
  expect_true(t2$schema$Equals(t1$schema))
  expect_true(t2$Equals(t1))
})

test_that("empty results and other column types read through zuarrow", {
  con <- local_duckdb()
  df <- duckdb_to_r(
    con,
    "SELECT 1::BIGINT AS x, 2::UHUGEINT AS u, 'a' AS s, 2.5 AS d WHERE false"
  )
  expect_identical(nrow(df), 0L)
  expect_identical(df$x, int64())
  expect_identical(df$u, uint128())
  df <- duckdb_to_r(con, "SELECT 1::BIGINT AS x, 'a' AS s, 2.5::DOUBLE AS d")
  expect_identical(df$x, int64(1))
  expect_identical(df$s, "a")
  expect_identical(df$d, 2.5)
})

test_that("as_integer64() and int64() swap only the class", {
  x <- int64(c(a = "9007199254740993", b = NA))
  y <- as_integer64(x)
  expect_identical(class(y), "integer64")
  expect_identical(zu_storage(int64(y)), zu_storage(x))
  expect_identical(names(y), c("a", "b"))
  expect_identical(int64(y), x)
  expect_warning(
    z <- as_integer64(uint64("18446744073709551614")),
    class = "zuint_cast_warning"
  )
  expect_identical(z, structure(NA_int64_, class = "integer64"))
})
