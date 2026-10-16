# The acceptance test (design 12): for each engine type and each path, the
# schema and every value survive the trip into R and back.

test_that("DuckDB -> R -> DuckDB keeps every type and value", {
  src <- duckdb_matrix_source()
  con <- src$con
  df <- zu_duckdb_query(con, "SELECT * FROM src ORDER BY i")
  for (t in names(engine_types)) {
    type <- engine_types[[t]]
    expect_identical(df[[tolower(t)]], zu_ctor(type)(src$values[[type]]), label = t)
  }
  zu_duckdb_register(con, "back", df)
  types <- function(tbl) DBI::dbGetQuery(con, sprintf("SELECT column_name, column_type FROM (DESCRIBE %s)", tbl))
  expect_identical(types("back"), types("src"))
  diff <- DBI::dbGetQuery(con, "
    SELECT count(*) AS n FROM src s JOIN back b USING (i)
    WHERE s.bigint IS DISTINCT FROM b.bigint OR s.ubigint IS DISTINCT FROM b.ubigint
       OR s.hugeint IS DISTINCT FROM b.hugeint OR s.uhugeint IS DISTINCT FROM b.uhugeint")
  expect_identical(diff$n, 0)
  expect_identical(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM back")$n, as.numeric(nrow(df)))
})

test_that("Arrow -> R -> Arrow keeps the schema and every value", {
  src <- duckdb_matrix_source()
  DBI::dbExecute(src$con, "SET arrow_lossless_conversion = true")
  res <- DBI::dbSendQuery(src$con, "SELECT * EXCLUDE (i) FROM src ORDER BY i", arrow = TRUE)
  t0 <- arrow::as_arrow_table(duckdb::duckdb_fetch_arrow(res))
  DBI::dbClearResult(res)
  df <- zu_from_arrow_table(t0)
  t1 <- zu_arrow_table(df)
  expect_true(t1$schema$Equals(t0$schema))
  expect_true(t1$Equals(t0))
})

test_that("Parquet -> R -> Parquet keeps the schema and every value", {
  skip_without_engines()
  df <- as.data.frame(lapply(engine_types, function(type) zu_ctor(type)(matrix_values(type))))
  f1 <- withr::local_tempfile(fileext = ".parquet")
  f2 <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(zu_arrow_table(df), f1)
  t1 <- arrow::read_parquet(f1, as_data_frame = FALSE)
  back <- zu_from_arrow_table(t1)
  expect_identical(back, df)
  arrow::write_parquet(zu_arrow_table(back), f2)
  t2 <- arrow::read_parquet(f2, as_data_frame = FALSE)
  expect_true(t2$schema$Equals(t1$schema))
  expect_true(t2$Equals(t1))
})

test_that("the largest unsigned values read exactly through zu_duckdb_query()", {
  skip_without_engines()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  df <- zu_duckdb_query(con, "
    SELECT 18446744073709551614::UBIGINT AS u64,
           340282366920938463463374607431768211454::UHUGEINT AS u128")
  expect_identical(df$u64, uint64("18446744073709551614"))
  expect_identical(df$u128, uint128("340282366920938463463374607431768211454"))
})

test_that("an engine value on the NA pattern reads as NA with a warning", {
  skip_without_engines()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_warning(df <- zu_duckdb_query(con, "SELECT (-9223372036854775807 - 1)::BIGINT AS m"), class = "zuint_cast_warning")
  expect_identical(df$m, NA_int64_)
})

test_that("zu_duckdb_query() handles empty results and other column types", {
  skip_without_engines()
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  df <- zu_duckdb_query(con, "SELECT 1::BIGINT AS x, 'a' AS s, 2.5 AS d WHERE false")
  expect_identical(nrow(df), 0L)
  expect_identical(df$x, int64())
  df <- zu_duckdb_query(con, "SELECT 1::BIGINT AS x, 'a' AS s, 2.5::DOUBLE AS d")
  expect_identical(df$s, "a")
  expect_identical(df$d, 2.5)
  expect_error(zu_duckdb_register(con, "x", 1:3), class = "zuint_type_error")
})

test_that("arrow converts int64 and uint64, and refuses the 128-bit types", {
  skip_if_not_installed("arrow")
  a <- arrow::as_arrow_array(uint64(c("18446744073709551614", NA)))
  expect_identical(a$type$ToString(), "uint64")
  expect_identical(arrow::infer_type(int64(1))$ToString(), "int64")
  expect_error(arrow::as_arrow_array(int128(1)), class = "zuint_unsupported_error")
  expect_error(arrow::infer_type(uint128(1)), class = "zuint_unsupported_error")
})

test_that("as_integer64() and int64() swap only the class", {
  x <- int64(c(a = "9007199254740993", b = NA))
  y <- as_integer64(x)
  expect_identical(class(y), "integer64")
  expect_identical(zu_storage(int64(y)), zu_storage(x))
  expect_identical(names(y), c("a", "b"))
  expect_identical(int64(y), x)
  expect_warning(z <- as_integer64(uint64("18446744073709551614")), class = "zuint_cast_warning")
  expect_identical(z, structure(NA_int64_, class = "integer64"))
})

test_that("zu_from_arrow_table warns once for sentinel values across batches", {
  skip_without_engines()
  # two batches, each holding a valid UINT64_MAX
  mk <- function() arrow::arrow_table(x = arrow::Array$create("18446744073709551615")$cast(arrow::uint64()))
  rdr <- arrow::RecordBatchReader$create(batches = list(arrow::as_record_batch(mk()), arrow::as_record_batch(mk())))
  w <- 0L
  df <- withCallingHandlers(zu_from_arrow_table(rdr), zuint_cast_warning = function(cnd) {
    w <<- w + 1L
    invokeRestart("muffleWarning")
  })
  expect_identical(w, 1L)
  expect_identical(sum(is.na(df$x)), 2L)
})
