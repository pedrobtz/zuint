# zuint's registrations with zuarrow (design 9): what the registry lists,
# what the handlers read and write, the sentinel edge under each policy
# (review X4), and the lifetime of the structs zuint exports.

test_that("zuarrow's registry lists zuint's entries once zuarrow loads", {
  skip_without_zuarrow()
  reg <- zuarrow::arrow_registry()
  reg <- reg[reg$package %in% "zuint", ]
  expect_setequal(reg$key, c("l", "L", "arrow.opaque"))
  expect_true(all(reg$exact))
  classes <- stats::setNames(reg$class, reg$key)
  expect_identical(classes[["arrow.opaque"]], "zu_int128/zu_uint128")
  expect_identical(classes[["l"]], "zu_int64")
  expect_identical(classes[["L"]], "zu_uint64")
  # no registration claims decimal128 (review X5)
  expect_false(any(startsWith(reg$key, "d:")))
})

test_that("every type round-trips through zuarrow, nulls included", {
  skip_without_zuarrow()
  for (type in zu_all_types) {
    vals <- c(oracle_edges(type), NA, oracle_random(type, 50, seed = 4), NA)
    x <- zu_ctor(type)(vals)
    a <- zuarrow::arrow_array(x)
    expect_identical(zuarrow::arrow_to_r(a), x, label = type)
    expect_identical(zuarrow::arrow_to_r(a), x, label = type)
    e <- zuarrow::arrow_array(zu_ctor(type)())
    expect_identical(zuarrow::arrow_to_r(e), zu_ctor(type)(), label = type)
  }
})

test_that("a data frame round-trips through a stream of several batches", {
  skip_without_zuarrow()
  df <- data.frame(
    a = int64(c(1, NA, "9223372036854775807", -4, 5)),
    b = uint128(c("340282366920938463463374607431768211454", 2, NA, 4, 0)),
    s = letters[1:5]
  )
  stream <- zuarrow::arrow_stream(df, batch = 2)
  expect_identical(zuarrow::arrow_to_r(stream), df)
  raw <- zuarrow::arrow_write(df, NULL, format = "stream", batch = 2)
  expect_identical(zuarrow::arrow_read(raw), df)
})

test_that("the formats written are the ones DuckDB reads as its types", {
  con <- local_duckdb()
  df <- data.frame(
    a = int64(1),
    b = uint64(2),
    c = int128(3),
    d = uint128(4)
  )
  duckdb_register_df(con, "t", df)
  types <- DBI::dbGetQuery(
    con,
    "SELECT column_name, column_type FROM (DESCRIBE t)"
  )
  expect_identical(
    types$column_type,
    c("BIGINT", "UBIGINT", "HUGEINT", "UHUGEINT")
  )
})

test_that("DuckDB's HUGEINT and UHUGEINT read exactly at their ends", {
  con <- local_duckdb()
  df <- duckdb_to_r(
    con,
    "
    SELECT 170141183460469231731687303715884105727::HUGEINT AS h,
           (-170141183460469231731687303715884105727)::HUGEINT AS l,
           340282366920938463463374607431768211454::UHUGEINT AS u,
           18446744073709551614::UBIGINT AS u64,
           NULL::UHUGEINT AS n"
  )
  expect_identical(df$h, int128("170141183460469231731687303715884105727"))
  expect_identical(df$l, int128("-170141183460469231731687303715884105727"))
  expect_identical(df$u, uint128("340282366920938463463374607431768211454"))
  expect_identical(df$u64, uint64("18446744073709551614"))
  expect_identical(df$n, NA_uint128_)
})

test_that("a value on a type's NA pattern follows zuarrow's lossy policy", {
  con <- local_duckdb()
  for (q in c(
    "SELECT * FROM (VALUES (18446744073709551615::UBIGINT), (1)) t(m)",
    "SELECT * FROM (VALUES ((-9223372036854775807 - 1)::BIGINT), (1)) t(m)",
    "SELECT * FROM (VALUES (340282366920938463463374607431768211455::UHUGEINT), (1)) t(m)",
    "SELECT * FROM (VALUES ((-170141183460469231731687303715884105727 - 1)::HUGEINT), (1)) t(m)"
  )) {
    expect_error(duckdb_to_r(con, q), class = "zuarrow_lossy_error")
    expect_error(
      duckdb_to_r(con, q, lossy = "character"),
      class = "zuarrow_lossy_error"
    )
    expect_warning(
      w <- duckdb_to_r(con, q, lossy = "warn"),
      class = "zuarrow_lossy_warning"
    )
    expect_identical(is.na(w$m), c(TRUE, FALSE))
    expect_no_condition(a <- duckdb_to_r(con, q, lossy = "allow"))
    expect_identical(a, w)
  }
})

test_that("the sentinel error is raised once, with zuarrow's fields", {
  con <- local_duckdb()
  err <- expect_error(
    duckdb_to_r(con, "SELECT 18446744073709551615::UBIGINT AS m"),
    class = "zuarrow_error"
  )
  expect_identical(err$arrow_type, "L")
  expect_identical(err$package, "zuint")
  expect_snapshot(conditionMessage(err))
})

test_that("int128() as the prototype reads DuckDB's default decimal export", {
  con <- local_duckdb(lossless = FALSE)
  sql <- "
    SELECT 170141183460469231731687303715884105727::HUGEINT AS h
    UNION ALL SELECT -1 UNION ALL SELECT NULL"
  df <- duckdb_to_r(con, sql, to = list(h = int128()))
  expect_identical(
    df$h,
    int128(c("170141183460469231731687303715884105727", "-1", NA))
  )
  # a decimal with a scale is not an integer: zuarrow's own conversion
  # refuses it
  expect_error(
    duckdb_to_r(
      con,
      "SELECT 1.5::DECIMAL(38, 1) AS d",
      to = list(d = int128())
    ),
    class = "zuarrow_lossy_error"
  )
})

test_that("a zuint prototype casts a column of another format", {
  skip_without_zuarrow()
  a <- zuarrow::arrow_array(uint64(c(1, 5, NA)))
  expect_identical(
    zuarrow::arrow_to_r(a, to = int64()),
    int64(c(1, 5, NA))
  )
  b <- zuarrow::arrow_array(int64(-1))
  expect_warning(
    zuarrow::arrow_to_r(b, to = uint64()),
    class = "zuint_cast_warning"
  )
  # a format zuint does not read goes through zuarrow, then the cast
  expect_identical(
    zuarrow::arrow_to_r(zuarrow::arrow_array(c(1L, NA)), to = int64()),
    int64(c(1, NA))
  )
})

test_that("other arrow.opaque types keep zuarrow's own conversion", {
  skip_without_zuarrow()
  x <- list(as.raw(1:16))
  attr(x, "arrow_width") <- 16L
  attr(x, "arrow_extension") <- "arrow.opaque"
  attr(x, "arrow_extension_metadata") <-
    '{"type_name":"varint","vendor_name":"DuckDB"}'
  expect_identical(zuarrow::arrow_to_r(zuarrow::arrow_array(x)), x)
})

test_that("import borrows the structs and the release callback runs once", {
  skip_without_zuarrow()
  a <- zu_arrow_from(uint128(1:3))
  expect_s3_class(a, "nanoarrow_array")
  expect_identical(zuarrow::arrow_to_r(a), uint128(1:3))
  expect_identical(zuarrow::arrow_to_r(a), uint128(1:3))
  expect_false(.Call(zu_arrow_released_c, a))
  # the hook counts inside C, so no collection can add to the count
  expect_identical(.Call(zu_arrow_release_c, a), 1L)
  expect_true(.Call(zu_arrow_released_c, a))
  expect_identical(.Call(zu_arrow_release_c, a), 0L)
})

test_that("an exported array is released when collected", {
  before <- settled_releases()
  a <- zu_arrow_from(int64(1:3))
  rm(a)
  expect_gte(settled_releases() - before, 1)
})

test_that("an exported array carries its schema in the r.h layout", {
  a <- zu_arrow_from(int128(1))
  s <- attr(a, "class")
  expect_identical(s, "nanoarrow_array")
  expect_identical(.Call(zu_arrow_format_c, zu_arrow_tag(a)), "w:16")
  expect_identical(zu_arrow_type(zu_arrow_tag(a)), 3L)
})

test_that("a released or unreadable struct is a zuint_arrow_error", {
  to <- zu_arrow_to(1L)
  a <- zu_arrow_from(int64(1:3))
  schema <- zu_arrow_tag(a)
  .Call(zu_arrow_release_c, a)
  expect_error(to(a, schema, "error"), class = "zuint_arrow_error")
  expect_error(zu_arrow_from(1L), class = "zuint_arrow_error")
})

test_that("corrupt schema metadata reads as no metadata", {
  i32 <- function(v) {
    writeBin(as.integer(v), raw(), size = 4, endian = .Platform$endian)
  }
  entry <- function(k, v) {
    c(i32(nchar(k)), charToRaw(k), i32(nchar(v)), charToRaw(v))
  }
  good <- c(i32(1), entry("ARROW:extension:name", "arrow.opaque"))
  get <- function(md, key = "ARROW:extension:name") {
    .Call(zu_metadata_get_c, md, key)
  }
  expect_identical(get(good), "arrow.opaque")
  expect_null(get(good, "missing"))
  # a negative count, a negative key length, a negative value length
  expect_null(get(c(i32(-1), entry("ARROW:extension:name", "x"))))
  expect_null(get(c(
    i32(1),
    i32(-5),
    charToRaw("ARROW:extension:name"),
    i32(1),
    charToRaw("x")
  )))
  expect_null(get(c(
    i32(1),
    i32(20),
    charToRaw("ARROW:extension:name"),
    i32(-3),
    charToRaw("x")
  )))
  # too many entries, and lengths that run past the end
  expect_null(get(c(i32(1e6), entry("ARROW:extension:name", "x"))))
  expect_null(get(c(i32(1), i32(400), charToRaw("ARROW"))))
  expect_null(get(good[1:10]))
  expect_null(get(raw(2)))
})
