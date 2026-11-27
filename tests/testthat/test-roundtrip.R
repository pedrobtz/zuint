# The acceptance test (design 0, 12): for each engine type and each path,
# the schema and every value survive the trip into R and back. Since Stage 9
# every path goes through zuarrow, which reads zuint's registrations.

# The engines' side of each path is replayed (helper-engines.R): what DuckDB
# and arrow exported, as IPC, and what they answered about what zuint wrote,
# keyed by the fingerprint of zuint's export.

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
  types <- "SELECT column_name, column_type FROM (DESCRIBE %s)"
  got <- duck_receive(
    con,
    list(back = df),
    list(
      back = sprintf(types, "back"),
      src = sprintf(types, "src"),
      diff = "
    SELECT count(*) AS n FROM src s JOIN back b USING (i)
    WHERE s.bigint IS DISTINCT FROM b.bigint OR s.ubigint IS DISTINCT FROM b.ubigint
       OR s.hugeint IS DISTINCT FROM b.hugeint OR s.uhugeint IS DISTINCT FROM b.uhugeint",
      n = "SELECT count(*) AS n FROM back"
    )
  )
  expect_identical(got$back, got$src)
  expect_identical(got$diff$n, 0)
  expect_identical(got$n$n, as.numeric(nrow(df)))
})

test_that("Arrow -> R -> Arrow keeps the schema and every value", {
  src <- duckdb_matrix_source()
  bytes <- arrow_bytes(
    "matrix_arrow_bytes",
    setup = src$con$setup,
    sql = "SELECT * EXCLUDE (i) FROM src ORDER BY i"
  )
  df <- zuarrow::arrow_read(bytes)
  for (t in names(engine_types)) {
    type <- engine_types[[t]]
    expect_identical(
      df[[tolower(t)]],
      zu_ctor(type)(src$values[[type]]),
      label = t
    )
  }
  same <- arrow_check("arrow_same_table", df, bytes = bytes)
  expect_true(same$schema)
  expect_true(same$values)
})

test_that("Parquet -> R -> Parquet keeps the schema and every value", {
  skip_without_zuarrow()
  df <- as.data.frame(lapply(engine_types, function(type) {
    zu_ctor(type)(matrix_values(type))
  }))
  bytes <- arrow_check("parquet_bytes", df)
  back <- zuarrow::arrow_read(bytes)
  expect_identical(back, df)
  same <- arrow_check("parquet_same_table", back, bytes = bytes)
  expect_true(same$schema)
  expect_true(same$values)
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
