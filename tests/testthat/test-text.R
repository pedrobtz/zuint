test_that("every type round-trips through decimal, hex and binary text", {
  for (type in zu_all_types) {
    vals <- c(oracle_edges(type), oracle_random(type, 300, seed = 3))
    big <- gmp::as.bigz(vals)
    x <- zu_ctor(type)(vals)
    hex <- oracle_base(big, 16)
    bin <- oracle_base(big, 2)
    expect_identical(format_hex(x), hex, label = type)
    expect_identical(format_bin(x), bin, label = type)
    expect_identical(zu_ctor(type)(hex), x, label = type)
    expect_identical(zu_ctor(type)(bin), x, label = type)
    expect_identical(
      zu_ctor(type)(toupper(sub("0x", "0X", hex))),
      x,
      label = type
    )
    expect_identical(zu_ctor(type)(format(x)), x, label = type)
    expect_identical(zu_ctor(type)(format(x, big.mark = "_")), x, label = type)
  }
})

test_that("format_hex and format_bin pad to the full width on request", {
  expect_identical(format_hex(uint64(255), pad = TRUE), "0x00000000000000ff")
  expect_identical(
    format_hex(int128(-1), pad = TRUE),
    paste0("-0x", strrep("0", 31), "1")
  )
  expect_identical(nchar(format_bin(uint128(1), pad = TRUE)), 130L)
  expect_identical(format_hex(uint64(c(a = 0, b = NA))), c(a = "0x0", b = NA))
  expect_error(format_hex(1L), class = "zuint_type_error")
  expect_error(format_hex(int64(1), pad = NA), class = "zuint_type_error")
})

test_that("the parser takes signs, separators and surrounding whitespace", {
  expect_identical(
    as.character(int64(c("+5", "-5", "-0", "007", " 12 ", "\t1_000_000\n"))),
    c("5", "-5", "0", "7", "12", "1000000")
  )
  expect_identical(
    as.character(uint128(c("0xFF", "0Xff", "0b1_0_1", "0xdead_beef", "-0x0"))),
    c("255", "255", "5", "3735928559", "0")
  )
  expect_identical(
    as.character(int128("-0x7fffffffffffffffffffffffffffffff")),
    "-170141183460469231731687303715884105727"
  )
})

test_that("NA, empty and blank strings are NA without a warning", {
  for (type in zu_all_types) {
    expect_no_warning(x <- zu_ctor(type)(c("NA", "", "   ", " NA ", NA)))
    expect_identical(x, zu_na(type, 5), label = type)
  }
})

test_that("every malformed string is NA with a warning, never a wrong value", {
  corpus <- c(
    "1e3",
    "1E3",
    "1.0",
    "1.",
    ".5",
    "0x",
    "0b",
    "+",
    "-",
    "--1",
    "+-1",
    "-+1",
    "1__0",
    "_1",
    "1_",
    "0x_1",
    "0_x1",
    "0xg",
    "0b2",
    "0b_1",
    "- 1",
    "1 2",
    "abc",
    "1L",
    "0x1p3",
    "Inf",
    "NaN",
    "na",
    "N A",
    "1,000",
    "١٢",
    " 1",
    "0o17",
    "0x-1",
    "1-",
    "#1",
    "1i",
    "TRUE"
  )
  for (type in zu_all_types) {
    expect_warning(x <- zu_ctor(type)(corpus), class = "zuint_cast_warning")
    expect_identical(sum(is.na(x)), length(corpus), label = type)
  }
})

test_that("text beyond 128 bits or beyond the type's range is NA with a warning", {
  expect_warning(
    x <- uint128(paste0("0x1", strrep("0", 32))),
    class = "zuint_cast_warning"
  )
  expect_identical(x, NA_uint128_)
  expect_warning(x <- uint128(strrep("9", 60)), class = "zuint_cast_warning")
  expect_identical(x, NA_uint128_)
  expect_warning(
    x <- uint64("0x1_0000_0000_0000_0000"),
    class = "zuint_cast_warning"
  )
  expect_identical(x, NA_uint64_)
  expect_warning(x <- int64("0x8000000000000000"), class = "zuint_cast_warning")
  expect_identical(x, NA_int64_)
})

test_that("format() groups digits and pads to a width", {
  expect_identical(
    format(int64(c(1234567, -1000, 5, NA)), big.mark = ","),
    c("1,234,567", "   -1,000", "        5", "       NA")
  )
  expect_identical(
    format(uint128("340282366920938463463374607431768211454"), big.mark = "'"),
    "340'282'366'920'938'463'463'374'607'431'768'211'454"
  )
  expect_identical(format(uint64(5), width = 4), "   5")
  expect_identical(format(int64(c(a = 1))), c(a = "1"))
})

test_that("print shows exact values and stops at max.print", {
  expect_snapshot({
    print(int128(c("-170141183460469231731687303715884105727", "0", NA)))
    print(uint64(1:30), max = 4)
    withr::with_options(list(max.print = 3), print(int64(1:10)))
    print(format(int64(1234567), big.mark = ","))
  })
})
