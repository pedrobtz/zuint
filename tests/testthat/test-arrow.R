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
  got <- duck_receive(
    con,
    list(t = df),
    list(types = "SELECT column_name, column_type FROM (DESCRIBE t)")
  )
  expect_identical(
    got$types$column_type,
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
  # too many entries is an error (#166); lengths that run past the end
  expect_error(
    get(c(i32(1e6), entry("ARROW:extension:name", "x"))),
    "more than 4096 entries"
  )
  expect_null(get(c(i32(1), i32(400), charToRaw("ARROW"))))
  expect_null(get(good[1:10]))
  expect_null(get(raw(2)))
})

test_that("the metadata entry cap is 4096, straddled", {
  i32 <- function(v) {
    writeBin(as.integer(v), raw(), size = 4, endian = .Platform$endian)
  }
  # n entries, the wanted key last
  md <- function(n) {
    filler <- c(i32(1), charToRaw("k"), i32(1), charToRaw("v"))
    key <- "ARROW:extension:name"
    c(
      i32(n),
      rep(filler, n - 1),
      i32(nchar(key)),
      charToRaw(key),
      i32(12),
      charToRaw("arrow.opaque")
    )
  }
  get <- function(n) .Call(zu_metadata_get_c, md(n), "ARROW:extension:name")
  expect_identical(get(4095), "arrow.opaque")
  expect_identical(get(4096), "arrow.opaque")
  # past the cap the lookup fails rather than finding nothing (#166)
  expect_error(get(4097), "more than 4096 entries")
  # a key that is not one string (#166)
  expect_error(.Call(zu_metadata_get_c, md(1), character(0)), "expected")
  expect_error(.Call(zu_metadata_get_c, md(1), NA_character_), "expected")
})

test_that("past the metadata cap the import fails rather than change type (#166)", {
  i32 <- function(v) {
    writeBin(as.integer(v), raw(), size = 4, endian = .Platform$endian)
  }
  entry <- function(k, v) {
    c(i32(nchar(k)), charToRaw(k), i32(nchar(v)), charToRaw(v))
  }
  # `extra` filler entries, then DuckDB's hugeint extension
  md <- function(extra) {
    c(
      i32(extra + 2),
      rep(entry("k", "v"), extra),
      entry("ARROW:extension:name", "arrow.opaque"),
      entry(
        "ARROW:extension:metadata",
        '{"type_name":"hugeint","vendor_name":"DuckDB"}'
      )
    )
  }
  to <- zu_arrow_to(NA_integer_)
  read <- function(extra) {
    a <- zu_arrow_from(int128(c(1, -2)))
    .Call(zu_arrow_metadata_c, a, md(extra))
    to(a, zu_arrow_tag(a), "error")
  }
  expect_identical(read(0), int128(c(1, -2)))
  expect_identical(read(4094), int128(c(1, -2)))
  expect_error(read(4095), class = "zuint_arrow_error")
  expect_error(read(4095), "more than 4096 entries")
  # the cap applies wherever the metadata decides the type
  expect_error(
    .Call(zu_arrow_format_type_c, "d:38,0", md(4095)),
    "more than 4096 entries"
  )
  expect_identical(.Call(zu_arrow_format_type_c, "l", md(4095)), 1L)
})

test_that("the handler's schema errors are zuint_arrow_error (#166)", {
  for (target in list(1L, NA_integer_)) {
    to <- zu_arrow_to(target)
    expect_error(to(1, 2, "error"), class = "zuint_arrow_error")
    a <- zu_arrow_from(int64(1:3))
    .Call(zu_arrow_corrupt_c, a, 5L)
    expect_error(to(a, zu_arrow_tag(a), "error"), class = "zuint_arrow_error")
    expect_error(to(a, zu_arrow_tag(a), "error"), "released")
  }
})

test_that("decimal128 imports up to precision 38, straddled", {
  type_of <- function(format) {
    t <- .Call(zu_arrow_format_type_c, format, NULL)
    if (is.integer(t)) t else NA_integer_
  }
  for (f in c("d:37,0", "d:38,0", "d:37,0,128", "d:38,0,128")) {
    expect_identical(type_of(f), 3L, label = f)
  }
  # no Arrow library builds precision 39, so only the format is given
  for (f in c("d:39,0", "d:39,0,128", "d:0,0", "d:38,0,256")) {
    expect_identical(type_of(f), NA_integer_, label = f)
  }
  # the values at both precisions zuint reads, as nanoarrow wrote them
  skip_without_zuarrow()
  for (p in c(37L, 38L)) {
    bytes <- arrow_bytes("decimal_bytes", values = c(1, -2, NA), p = p)
    expect_identical(
      zuarrow::arrow_read(bytes, to = list(x = int128()))$x,
      int128(c(1, -2, NA)),
      label = p
    )
  }
})

test_that("the import refuses a schema that is not the array's own (#61)", {
  to <- zu_arrow_to(NA_integer_)
  a <- zu_arrow_from(uint64(c(1, 2)))
  wide <- zu_arrow_from(int128(1))
  # reading 16-byte values from an 8-byte buffer would over-read it
  expect_error(to(a, zu_arrow_tag(wide), "error"), class = "zuint_arrow_error")
  expect_error(to(wide, zu_arrow_tag(a), "error"), class = "zuint_arrow_error")
  # the array's own schema, and a copy with the same format, read
  expect_identical(to(a, zu_arrow_tag(a), "error"), uint64(c(1, 2)))
  skip_without_zuarrow()
  expect_identical(
    zuarrow::arrow_to_r(zuarrow::arrow_array(int128(c(1, NA)))),
    int128(c(1, NA))
  )
})

test_that("the decimal format is read in the spec's form only (#156)", {
  type_of <- function(format) {
    t <- .Call(zu_arrow_format_type_c, format, NULL)
    if (is.integer(t)) t else NA_integer_
  }
  for (f in c("d:1,0", "d:5,0", "d:38,0", "d:38,0,128", "d:038,00")) {
    expect_identical(type_of(f), 3L, label = f)
  }
  # numbers past INT_MAX wrapped under sscanf("%d"); signs, spaces and
  # missing or extra parts were accepted
  for (f in c(
    "d:5,4294967296",
    "d:4294967301,0",
    "d:4294967334,0",
    "d:5,18446744073709551616",
    "d:99999999999999999999999,0",
    "d:5,0,4294967424",
    "d: 5,0",
    "d:5, 0",
    "d:5,0 ",
    "d:+5,+0",
    "d:5,+0",
    "d:5,-0",
    "d:-5,0",
    "d:5",
    "d:5,",
    "d:,0",
    "d:5,0,",
    "d:5,0,128x",
    "d:5,0,64",
    "d:5,0,256",
    "d:5;0",
    "d:",
    "d:0x5,0"
  )) {
    expect_identical(type_of(f), NA_integer_, label = f)
  }
})

test_that("DuckDB's extension is read when DuckDB reads it, from its JSON (#154)", {
  con <- local_duckdb()
  hugeint <- '{"type_name":"hugeint","vendor_name":"DuckDB"}'
  cases <- list(
    c(hugeint, "w:16"),
    c('{"vendor_name":"DuckDB","type_name":"hugeint"}', "w:16"),
    c('{"type_name":"uhugeint","vendor_name":"DuckDB"}', "w:16"),
    c(' {\t"type_name" :\n"hugeint" ,\r"vendor_name": "DuckDB" } ', "w:16"),
    c('{"type_name":"hugeint","vendor_name":"Other"}', "w:16"),
    c('{"type_name":"hugeint"}', "w:16"),
    c('{"type_name":"HUGEINT","vendor_name":"DuckDB"}', "w:16"),
    c('{"type_name":"hugeint128","vendor_name":"DuckDB"}', "w:16"),
    c('{"type_name":"uuid","vendor_name":"DuckDB"}', "w:16"),
    c(
      '{"extra":{"type_name":"hugeint"},"type_name":"uuid","vendor_name":"DuckDB"}',
      "w:16"
    ),
    c(
      '{"vendor_name":"DuckDB","note":"type_name","type_name":"hugeint"}',
      "w:16"
    ),
    c(
      '{"note":"a \\"type_name\\":\\"hugeint\\" b","type_name":"uuid","vendor_name":"DuckDB"}',
      "w:16"
    ),
    c('{"type_name":"huge\\u0069nt","vendor_name":"Duck\\u0044B"}', "w:16"),
    c('{"type\\u005fname":"hugeint","vendor_name":"DuckDB"}', "w:16"),
    c(
      '{"type_name":"hugeint","type_name":"uhugeint","vendor_name":"DuckDB"}',
      "w:16"
    ),
    c(
      '{"a":[1,-2.5e3,{"b":null},[]],"type_name":"hugeint","c":true,"vendor_name":"DuckDB","d":{}}',
      "w:16"
    ),
    c(
      '{"type_name":"hugeint","vendor_name":"DuckDB","n":"caf\u00e9 \\ud83d\\ude00"}',
      "w:16"
    ),
    c('{"type_name":7,"vendor_name":"DuckDB"}', "w:16"),
    c('{"type_name":"hugeint","vendor_name":"DuckDB"} x', "w:16"),
    c('{"type_name":"hugeint', "w:16"),
    c('{"type_name":"hugeint"', "w:16"),
    c("", "w:16"),
    c('["type_name","hugeint"]', "w:16"),
    # a decimal's storage: DuckDB's two types read as their bits, any
    # other opaque type is not an integer
    c(hugeint, "d:38,0"),
    c('{"type_name":"uhugeint","vendor_name":"DuckDB"}', "d:38,0"),
    c('{"type_name":"uuid","vendor_name":"DuckDB"}', "d:38,0")
  )
  for (case in cases) {
    bytes <- arrow_bytes(
      "opaque_bytes",
      json = case[[1L]],
      storage = case[[2L]]
    )
    duck <- duck_ipc(con, bytes, "typeof(x)")[[1L]]
    # "character" gives a decimal zuint does not read as its text
    x <- zuarrow::arrow_read(bytes, lossy = "character")$x
    label <- paste(case, collapse = " on ")
    if (duck == "HUGEINT") {
      expect_identical(x, int128(c(1, -2)), label = label)
    } else if (duck == "UHUGEINT") {
      expect_identical(
        x,
        uint128(c("1", "340282366920938463463374607431768211454")),
        label = label
      )
    } else {
      expect_false(
        inherits(x, c("zu_int128", "zu_uint128")),
        label = paste(label, "read by DuckDB as", duck)
      )
    }
  }
})

test_that("the extension's JSON must be valid JSON throughout (#154)", {
  i32 <- function(v) {
    writeBin(as.integer(v), raw(), size = 4, endian = .Platform$endian)
  }
  entry <- function(k, v) {
    v <- charToRaw(enc2utf8(v))
    c(i32(nchar(k)), charToRaw(k), i32(length(v)), v)
  }
  type_of <- function(json, format = "w:16") {
    md <- c(
      i32(2),
      entry("ARROW:extension:name", "arrow.opaque"),
      entry("ARROW:extension:metadata", json)
    )
    t <- .Call(zu_arrow_format_type_c, format, md)
    if (is.integer(t)) t else NA_integer_
  }
  ok <- '{"type_name":"hugeint","vendor_name":"DuckDB"'
  expect_identical(type_of(paste0(ok, "}")), 3L)
  expect_identical(type_of(paste0(ok, ',"n":[1,{"a":"\\u00e9"}]}')), 3L)
  # Arrow's parser reads these, as it looks only at the keys it wants, and
  # DuckDB then reads HUGEINT; zuint reads no invalid document
  for (rest in c(
    ',"n":"\\q"}',
    ',"n":01}',
    ",}",
    ',"n":tru}',
    ',"n":[1,]}',
    ',"n":"\\ud800"}',
    ',"n":"\\udc00"}',
    ',"n":"a\tb"}',
    ',"n":1.}',
    ',"n":-}',
    ',"n":1e}',
    ',"n":{"a"}}',
    ',"n":{1:2}}',
    ',"n":[}',
    ',"n":"\\u12"}',
    "}}"
  )) {
    expect_identical(type_of(paste0(ok, rest)), NA_integer_, label = rest)
  }
  # nesting deeper than 1024, the top-level object counted, is refused, as
  # by simdjson
  deep <- function(n) {
    paste0(ok, ',"n":', strrep("[", n), strrep("]", n), "}")
  }
  expect_identical(type_of(deep(1023)), 3L)
  expect_identical(type_of(deep(1024)), NA_integer_)
  # invalid UTF-8 in a string
  bad <- c(charToRaw(paste0(ok, ',"n":"')), as.raw(0xc3), charToRaw('"}'))
  md <- c(
    i32(2),
    entry("ARROW:extension:name", "arrow.opaque"),
    i32(nchar("ARROW:extension:metadata")),
    charToRaw("ARROW:extension:metadata"),
    i32(length(bad)),
    bad
  )
  expect_false(is.integer(.Call(zu_arrow_format_type_c, "w:16", md)))
  # the extension decides before the decimal format does
  expect_identical(
    type_of('{"type_name":"uuid","vendor_name":"DuckDB"}', "d:38,0"),
    NA_integer_
  )
  expect_identical(type_of(paste0(ok, "}"), "d:5,2"), 3L)
  expect_identical(type_of(paste0(ok, "}"), "d:38,0,256"), NA_integer_)
  expect_identical(type_of(paste0(ok, "}"), "w:8"), NA_integer_)
})
