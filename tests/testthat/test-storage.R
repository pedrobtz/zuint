test_that("int64 subclasses integer64 and has bit64's storage", {
  x <- int64(c(-5, 0, 2^62, NA))
  expect_true(inherits(x, "integer64"))
  expect_identical(class(x), c("zu_int64", "integer64"))
  expect_identical(typeof(x), "double")
  # INT64_MIN, bit64's NA, is the bits of -0.0
  bits <- zu_storage(int64(NA))
  expect_identical(bits, -0)
  expect_identical(1 / bits, -Inf)
})

test_that("bit64 reads int64 bit for bit", {
  skip_if_not_installed("bit64")
  x <- int64(c("-9223372036854775807", "-1", "0", "9007199254740993", NA))
  y <- bit64::as.integer64(x)
  expect_identical(zu_storage(y), zu_storage(x))
  expect_identical(
    as.character(unclass(bit64::as.integer64(as.character(x)))),
    as.character(unclass(y))
  )
})

test_that("int64() on a bit64 integer64 swaps only the class", {
  skip_if_not_installed("bit64")
  y <- bit64::as.integer64(c("123456789012345678", NA, "-7"))
  x <- int64(y)
  expect_identical(class(x), c("zu_int64", "integer64"))
  expect_identical(
    zu_storage(x),
    zu_storage(int64(c("123456789012345678", NA, "-7")))
  )
})

test_that("the 128-bit types store the low and high words in a complex", {
  p <- zu_storage(int128(-1))
  expect_identical(typeof(p), "complex")
  # -1 is all ones in both words; a uint64 of all ones is UINT64_MAX's bits
  ones <- zu_storage(uint64(NA))
  expect_identical(Re(p), ones)
  expect_identical(Im(p), ones)
  p <- zu_storage(uint128("18446744073709551616"))
  expect_identical(Re(p), 0)
  expect_identical(Im(p), zu_storage(uint64(1)))
})

test_that("zu_storage and zu_from_storage are inverses and keep names", {
  for (type in zu_all_types) {
    x <- zu_ctor(type)(c(a = 0, b = 1, c = NA))
    p <- zu_storage(x)
    expect_null(oldClass(p))
    expect_identical(names(p), c("a", "b", "c"), label = type)
    expect_identical(zu_from_storage(p, type), x, label = type)
  }
})

test_that("zu_storage and zu_from_storage reject what they cannot read", {
  expect_error(zu_storage(1), class = "zuint_type_error")
  expect_error(zu_from_storage(1i, "int64"), class = "zuint_type_error")
  expect_error(zu_from_storage(1, "uint128"), class = "zuint_type_error")
  expect_error(zu_from_storage(1, "int32"), class = "zuint_type_error")
  expect_error(zu_from_storage(int64(1), "int64"), class = "zuint_type_error")
})

test_that("the build uses the 128-bit path CI asked for", {
  expected <- Sys.getenv("ZUINT_EXPECT_INT128")
  skip_if(expected == "", "ZUINT_EXPECT_INT128 is not set")
  expect_identical(.Call(zu_have_int128_c), as.logical(expected))
})
