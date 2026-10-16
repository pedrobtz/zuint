test_that("every type round-trips through the C Data Interface, nulls included", {
  for (type in zu_all_types) {
    vals <- c(oracle_edges(type), NA, oracle_random(type, 50, seed = 4), NA)
    x <- zu_ctor(type)(vals)
    a <- zu_to_arrow(x)
    expect_identical(zu_from_arrow(a$array, a$schema), x, label = type)
    expect_identical(zu_from_arrow(a$array, a$schema), x)
  }
  for (type in zu_all_types) {
    x <- zu_ctor(type)()
    a <- zu_to_arrow(x)
    expect_identical(zu_from_arrow(a$array, a$schema), x)
  }
})

test_that("int128 round-trips as decimal128(38, 0), and a 39-digit value is an error", {
  x <- int128(c("-99999999999999999999999999999999999999", "0", NA, "99999999999999999999999999999999999999"))
  a <- zu_to_arrow(x, decimal = TRUE)
  expect_identical(zu_from_arrow(a$array, a$schema), x)
  expect_error(zu_to_arrow(int128("100000000000000000000000000000000000000"), decimal = TRUE), class = "zuint_arrow_error")
  expect_error(zu_to_arrow(uint128(1), decimal = TRUE), class = "zuint_type_error")
  expect_error(zu_to_arrow(1L), class = "zuint_type_error")
})

test_that("the formats are the ones engines expect", {
  skip_if_not_installed("nanoarrow")
  fmt <- function(x, ...) nanoarrow::infer_nanoarrow_schema(nanoarrow::as_nanoarrow_array(x))$format
  expect_identical(fmt(int64(1)), "l")
  expect_identical(fmt(uint64(1)), "L")
  s <- nanoarrow::infer_nanoarrow_schema(uint128(1))
  expect_identical(s$format, "w:16")
  expect_identical(s$metadata[["ARROW:extension:name"]], "arrow.opaque")
  expect_match(s$metadata[["ARROW:extension:metadata"]], '"type_name":"uhugeint"', fixed = TRUE)
  expect_match(nanoarrow::infer_nanoarrow_schema(int128(1))$metadata[[2L]], '"type_name":"hugeint"', fixed = TRUE)
})

test_that("decimal128 bits import as they are, beyond 38 digits too", {
  skip_if_not_installed("nanoarrow")
  # DuckDB's default export writes HUGEINT max as decimal128(38, 0) bits
  x <- int128(c("170141183460469231731687303715884105727", "-1", NA))
  a <- zu_to_arrow(x)
  expect_identical(zu_from_arrow(a$array, nanoarrow::na_decimal128(38, 0)), x)
  expect_identical(zu_from_arrow(a$array, nanoarrow::na_decimal128(10, 0)), x)
  expect_error(zu_from_arrow(a$array, nanoarrow::na_decimal128(38, 2)), class = "zuint_arrow_error")
})

test_that("DuckDB's HUGEINT and UHUGEINT exports import exactly", {
  h <- duckdb_column("SELECT 170141183460469231731687303715884105727::HUGEINT AS h")
  expect_identical(h$schema$format, "d:38,0")
  expect_identical(zu_from_arrow(h$array, h$schema), int128("170141183460469231731687303715884105727"))
  u <- duckdb_column(
    "SELECT * FROM (VALUES (340282366920938463463374607431768211454::UHUGEINT), (NULL)) t(u)",
    lossless = TRUE
  )
  expect_identical(u$schema$format, "w:16")
  expect_identical(zu_from_arrow(u$array, u$schema), uint128(c("340282366920938463463374607431768211454", NA)))
})

test_that("a valid value on the NA pattern imports as NA with a warning", {
  m <- duckdb_column("SELECT * FROM (VALUES (18446744073709551615::UBIGINT), (1::UBIGINT)) t(m)")
  expect_identical(zu_sentinel_check(m$array, m$schema), 1L)
  expect_warning(x <- zu_from_arrow(m$array, m$schema), class = "zuint_cast_warning")
  expect_identical(sum(is.na(x)), 1L)
  a <- zu_to_arrow(uint64(c(1, NA)))
  expect_identical(zu_sentinel_check(a$array, a$schema), 0L)
})

test_that("an array with an offset imports from the offset", {
  skip_if_not_installed("nanoarrow")
  x <- int128(c(1, NA, 3, 4))
  arr <- nanoarrow::as_nanoarrow_array(x)
  sliced <- nanoarrow::nanoarrow_array_modify(arr, list(offset = 1L, length = 2L))
  expect_identical(zu_from_arrow(sliced, nanoarrow::infer_nanoarrow_schema(sliced)), x[2:3])
})

test_that("import borrows the structs and the release callback runs once", {
  a <- zu_to_arrow(uint128(1:3))
  zu_from_arrow(a$array, a$schema)
  zu_from_arrow(a$array, a$schema)
  expect_false(.Call(zu_arrow_released_c, a$array))
  # the hook counts inside C, so no collection can add to the count
  expect_identical(.Call(zu_arrow_release_c, a$array), 1L)
  expect_true(.Call(zu_arrow_released_c, a$array))
  expect_identical(.Call(zu_arrow_release_c, a$array), 0L)
})

test_that("an exported array is released when collected", {
  before <- settled_releases()
  a <- zu_to_arrow(int64(1:3))
  rm(a)
  expect_gte(settled_releases() - before, 1)
})

test_that("a struct moved out is released by its new owner, not twice", {
  skip_if_not_installed("nanoarrow")
  na <- nanoarrow::as_nanoarrow_array(int64(1:3))
  # the struct nanoarrow now owns still has zuint's callback, once
  expect_identical(.Call(zu_arrow_release_c, na), 1L)
  expect_identical(.Call(zu_arrow_release_c, na), 0L)
  expect_false(nanoarrow::nanoarrow_pointer_is_valid(na))
})

test_that("unsupported or released structs are arrow errors", {
  skip_if_not_installed("nanoarrow")
  i32 <- nanoarrow::as_nanoarrow_array(1:3)
  expect_error(zu_from_arrow(i32, nanoarrow::infer_nanoarrow_schema(i32)), class = "zuint_arrow_error")
  fsb <- nanoarrow::na_fixed_size_binary(16)
  a <- zu_to_arrow(uint128(1))
  expect_error(zu_from_arrow(a$array, fsb), class = "zuint_arrow_error")
  # moved out, the struct left behind is released
  nanoarrow::nanoarrow_pointer_move(a$array, nanoarrow::nanoarrow_allocate_array())
  expect_error(zu_from_arrow(a$array, a$schema), class = "zuint_arrow_error")
  expect_error(zu_from_arrow(1, 2), class = "zuint_type_error")
})

test_that("nanoarrow converts to and from every type", {
  skip_if_not_installed("nanoarrow")
  for (type in zu_all_types) {
    x <- zu_ctor(type)(c(oracle_edges(type), NA))
    arr <- nanoarrow::as_nanoarrow_array(x)
    expect_identical(nanoarrow::convert_array(arr, zu_ctor(type)()), x, label = type)
  }
  # to another type, with the usual conversion rules
  arr <- nanoarrow::as_nanoarrow_array(uint64(c(1, 5)))
  expect_identical(nanoarrow::convert_array(arr, int128()), int128(c(1, 5)))
  arr <- nanoarrow::as_nanoarrow_array(int64(-1))
  expect_warning(nanoarrow::convert_array(arr, uint64()), class = "zuint_cast_warning")
  # and from formats zuint does not import itself, through nanoarrow
  expect_identical(nanoarrow::convert_array(nanoarrow::as_nanoarrow_array(c(1L, NA)), int64()), int64(c(1, NA)))
})
