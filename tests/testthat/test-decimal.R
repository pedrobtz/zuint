# The decimal128 class (design 2.2, Stage 9.2). DuckDB 2.0.1 is the oracle
# for types and values, compared as text; gmp for exact orders and sums.

# ---- construction -------------------------------------------------------------

test_that("decimal128() reads text as the core does, and NA quietly", {
  for (k in c(1L, 8L, 20L, 40L)) {
    type <- fx_types()[k, ]
    p <- type$p
    s <- type$s
    texts <- fx_texts(60L, p, s)$text
    core <- fx_parse(texts, p, s)
    x <- suppressWarnings(decimal128(texts, p, s))
    expect_identical(
      as.character(x),
      ifelse(core$status == fx_ok, fx_format(core$coef, p, s), NA),
      label = sprintf("DECIMAL(%d, %d)", p, s)
    )
  }
  expect_no_warning(x <- decimal128(c("NA", "", "  ", NA), 5, 2))
  expect_identical(as.character(x), rep(NA_character_, 4))
  expect_warning(
    x <- decimal128(c(a = "1.5", b = "abc", c = "1234.5"), 5, 2),
    class = "zuint_cast_warning"
  )
  expect_identical(as.character(x), c("1.50", NA, NA))
  expect_identical(names(x), c("a", "b", "c"))
})

test_that("decimal128() casts integers, doubles and decimals as DuckDB does", {
  con <- local_duckdb_plain()
  for (type in list(
    c(5L, 2L),
    c(10L, 0L),
    c(19L, 4L),
    c(38L, 0L),
    c(38L, 37L)
  )) {
    p <- type[[1L]]
    s <- type[[2L]]
    label <- sprintf("DECIMAL(%d, %d)", p, s)
    # every integer kind, from text so the values are exact
    for (it in list(
      list("int64", int64, "BIGINT"),
      list("uint64", uint64, "UBIGINT"),
      list("int128", int128, "HUGEINT"),
      list("uint128", uint128, "UHUGEINT")
    )) {
      v <- oracle_edges(it[[1L]])
      x <- suppressWarnings(decimal128(it[[2L]](v), p, s))
      duck <- duck_df(
        con,
        data.frame(x = v),
        sprintf(
          "TRY_CAST(CAST(x AS %s) AS DECIMAL(%d, %d))::VARCHAR",
          it[[3L]],
          p,
          s
        )
      )
      expect_identical(as.character(x), duck, label = paste(label, it[[1L]]))
    }
    v <- c(-.Machine$integer.max, -1L, 0L, 1L, 99L, .Machine$integer.max, NA)
    x <- suppressWarnings(decimal128(v, p, s))
    duck <- duck_df(
      con,
      data.frame(x = v),
      sprintf("TRY_CAST(x AS DECIMAL(%d, %d))::VARCHAR", p, s)
    )
    expect_identical(as.character(x), duck, label = paste(label, "integer"))
    d <- c(
      0,
      -0.5,
      2.675,
      1.005,
      0.125,
      123.456,
      -99.995,
      1e10,
      1e30,
      -1e37,
      NA
    )
    x <- suppressWarnings(decimal128(d, p, s))
    duck <- duck_df(
      con,
      data.frame(x = d),
      sprintf("TRY_CAST(x AS DECIMAL(%d, %d))::VARCHAR", p, s)
    )
    expect_identical(as.character(x), duck, label = paste(label, "double"))
    # from another decimal type: rescaled, half away from zero
    texts <- dec_texts(30L, 20L, 6L, seed = p + s)
    x <- suppressWarnings(decimal128(decimal128(texts, 20L, 6L), p, s))
    duck <- duck_df(
      con,
      data.frame(x = texts),
      sprintf(
        "TRY_CAST(CAST(x AS DECIMAL(20, 6)) AS DECIMAL(%d, %d))::VARCHAR",
        p,
        s
      )
    )
    expect_identical(as.character(x), duck, label = paste(label, "decimal"))
  }
  expect_warning(decimal128(NaN, 5, 2), class = "zuint_cast_warning")
  expect_warning(decimal128(int64(1000), 4, 2), class = "zuint_cast_warning")
  x <- decimal128("1.5", 5, 2)
  expect_identical(decimal128(x), x)
})

test_that("decimal128() checks its type and what it converts", {
  for (bad in list(
    list(0, 0),
    list(39, 0),
    list(5, 6),
    list(5, -1),
    list(5.5, 0),
    list(NA, 0),
    list(c(5, 6), 0),
    list("5", 0)
  )) {
    expect_error(
      decimal128("1", bad[[1L]], bad[[2L]]),
      class = "zuint_type_error"
    )
  }
  expect_error(decimal128(list(1)), class = "zuint_type_error")
  expect_error(decimal128(factor("1")), class = "zuint_type_error")
  expect_identical(decimal_precision(decimal128("1", 7, 3)), 7L)
  expect_identical(decimal_scale(decimal128("1", 7, 3)), 3L)
  expect_error(decimal_scale(1.5), class = "zuint_type_error")
  expect_true(is_decimal128(decimal128()))
  expect_false(is_decimal128(int128(1)))
})

# ---- arithmetic -----------------------------------------------------------------

test_that("+, - and * give DuckDB's type and value", {
  con <- local_duckdb_plain()
  pairs <- dec_type_pairs()
  for (k in seq_along(pairs)) {
    ta <- pairs[[k]]$a
    tb <- pairs[[k]]$b
    va <- dec_texts(12L, ta[[1L]], ta[[2L]], seed = k)
    vb <- dec_texts(12L, tb[[1L]], tb[[2L]], seed = 500L + k)
    n <- min(length(va), length(vb))
    va <- va[seq_len(n)]
    vb <- vb[seq_len(n)]
    a <- decimal128(va, ta[[1L]], ta[[2L]])
    b <- decimal128(vb, tb[[1L]], tb[[2L]])
    for (op in c("+", "-", "*")) {
      label <- sprintf(
        "DECIMAL(%d, %d) %s DECIMAL(%d, %d)",
        ta[[1L]],
        ta[[2L]],
        op,
        tb[[1L]],
        tb[[2L]]
      )
      expr <- sprintf(
        "%s %s %s",
        dec_sql("a", ta[[1L]], ta[[2L]]),
        op,
        dec_sql("b", tb[[1L]], tb[[2L]])
      )
      duck_type <- duck_typeof(
        con,
        sprintf(
          "%s %s %s",
          dec_sql("'0'", ta[[1L]], ta[[2L]]),
          op,
          dec_sql("'0'", tb[[1L]], tb[[2L]])
        )
      )
      if (duck_type == "ERROR") {
        # DuckDB refuses a product needing more than scale 38
        expect_error(get(op)(a, b), class = "zuint_incompatible_error")
        next
      }
      r <- suppressWarnings(get(op)(a, b))
      expect_identical(dec_typeof(r), duck_type, label = label)
      duck <- duck_df(
        con,
        data.frame(a = va, b = vb),
        sprintf("TRY(%s)::VARCHAR", expr)
      )
      expect_identical(as.character(r), duck, label = label)
    }
  }
})

test_that("an overflow is NA with a warning, where DuckDB raises", {
  big <- decimal128(c("9999999999999999999.9", "1"), 20, 1)
  expect_warning(r <- big * big, class = "zuint_overflow_warning")
  expect_identical(as.character(r), c(NA, "1.00"))
  top <- decimal128(strrep("9", 38), 38, 0)
  expect_warning(r <- top + 1L, class = "zuint_overflow_warning")
  expect_identical(dec_typeof(r), "DECIMAL(38,0)")
  expect_true(is.na(r))
  # rescaling an operand to the result's scale can be what overflows
  expect_warning(
    r <- top + decimal128("0.5", 1, 1),
    class = "zuint_overflow_warning"
  )
  expect_identical(dec_typeof(r), "DECIMAL(38,1)")
})

test_that("integer operands take DuckDB's implicit casts", {
  con <- local_duckdb_plain()
  a <- decimal128(c("-12.34", "0.05", "999.99", NA), 5, 2)
  va <- as.character(a)
  ints <- list(
    list(c(7L, -3L, 0L, NA), "INTEGER"),
    list(int64(c("9223372036854775807", "-2", "0", NA)), "BIGINT"),
    list(uint64(c("18446744073709551614", "2", "0", NA)), "UBIGINT"),
    list(int128(c("12345678901234567890123", "-1", "0", NA)), "HUGEINT"),
    list(uint128(c("12345678901234567890123", "1", "0", NA)), "UHUGEINT")
  )
  for (it in ints) {
    vb <- as.character(it[[1L]])
    for (op in c("+", "-", "*")) {
      for (left in c(TRUE, FALSE)) {
        r <- suppressWarnings(
          if (left) get(op)(a, it[[1L]]) else get(op)(it[[1L]], a)
        )
        sql_a <- dec_sql("a", 5L, 2L)
        sql_b <- sprintf("CAST(b AS %s)", it[[2L]])
        expr <- if (left) {
          paste(sql_a, op, sql_b)
        } else {
          paste(sql_b, op, sql_a)
        }
        label <- paste(it[[2L]], op, if (left) "right" else "left")
        type <- duck_typeof(
          con,
          gsub("\\bb\\b", "'0'", gsub("\\ba\\b", "'0'", expr))
        )
        expect_identical(dec_typeof(r), type, label = label)
        duck <- duck_df(
          con,
          data.frame(a = va, b = vb),
          sprintf("TRY(%s)::VARCHAR", expr)
        )
        expect_identical(as.character(r), duck, label = label)
      }
    }
  }
  # a uint128 past 38 digits has no DECIMAL to go to
  expect_warning(
    a + uint128("340282366920938463463374607431768211454"),
    class = "zuint_cast_warning"
  )
})

test_that("a whole double is an integer operand; any other follows zuint.double", {
  a <- decimal128(c("1.25", "-2.50"), 5, 2)
  # as DuckDB types an integer literal: INTEGER, so DECIMAL(10, 0)
  expect_identical(dec_typeof(a * 2), "DECIMAL(15,2)")
  expect_identical(as.character(a * 2), c("2.50", "-5.00"))
  expect_identical(dec_typeof(a + 2^40), "DECIMAL(22,2)")
  expect_identical(a * 2, a * 2L)
  expect_error(a * 1.5, class = "zuint_double_error")
  expect_error(a == 0.1, class = "zuint_double_error")
  expect_error(c(a, 0.5), class = "zuint_double_error")
  withr::local_options(zuint.double = "allow")
  expect_warning(r <- a * 1.5, class = "zuint_double_warning")
  expect_identical(r, as.double(a) * 1.5)
  expect_warning(r <- c(a, 0.5), class = "zuint_double_warning")
  expect_identical(r, c(1.25, -2.5, 0.5))
})

test_that("comparison is exact across scales", {
  skip_if_not_installed("gmp")
  withr::local_seed(9)
  for (k in 1:20) {
    sa <- sample(0:38, 1L)
    sb <- sample(0:38, 1L)
    ca <- fx_coefs(30L, 38L, seed = k)
    cb <- fx_coefs(30L, 38L, seed = 100L + k)
    n <- min(length(ca), length(cb))
    ca <- ca[seq_len(n)]
    cb <- cb[seq_len(n)]
    # every fifth pair is equal across the scales, where that fits
    a <- decimal128(fx_format(ca, 38L, sa), 38L, sa)
    b <- decimal128(fx_format(cb, 38L, sb), 38L, sb)
    s <- max(sa, sb)
    x <- gmp::as.bigz(ca) * gmp::as.bigz(10)^(s - sa)
    y <- gmp::as.bigz(cb) * gmp::as.bigz(10)^(s - sb)
    want <- as.integer(x > y) - as.integer(x < y)
    label <- sprintf("scales %d and %d", sa, sb)
    expect_identical(a < b, want < 0, label = label)
    expect_identical(a == b, want == 0, label = label)
    expect_identical(a >= b, want >= 0, label = label)
  }
  a <- decimal128(c("1.5", NA), 5, 2)
  expect_identical(a == decimal128("1.500", 10, 3), c(TRUE, NA))
  expect_identical(a > 1L, c(TRUE, NA))
  expect_identical(int64(2) > a, c(TRUE, NA))
  expect_identical(a != 2, c(TRUE, NA))
})

test_that("/, %%, %/%, ^ and Math are computed in double; abs and - keep the type", {
  a <- decimal128(c(x = "7.50", y = "-0.05", z = NA), 5, 2)
  b <- decimal128("2.0", 3, 1)
  for (op in c("/", "%%", "%/%", "^")) {
    expect_identical(
      get(op)(a, b),
      get(op)(as.double(a), as.double(b)) |> stats::setNames(names(a)),
      label = op
    )
  }
  expect_identical(exp(a), stats::setNames(exp(as.double(a)), names(a)))
  expect_identical(floor(a), stats::setNames(floor(as.double(a)), names(a)))
  expect_identical(abs(a), decimal128(c(x = "7.50", y = "0.05", z = NA), 5, 2))
  expect_identical(-a, decimal128(c(x = "-7.50", y = "0.05", z = NA), 5, 2))
  expect_identical(+a, a)
  expect_identical(!a, c(x = FALSE, y = FALSE, z = NA))
  expect_identical(a & TRUE, c(TRUE, TRUE, NA))
  expect_error(a + "1", class = "zuint_type_error")
})

# ---- combining ------------------------------------------------------------------

test_that("c() takes DuckDB's common type", {
  con <- local_duckdb_plain()
  types <- list(
    c(5L, 2L),
    c(7L, 3L),
    c(30L, 20L),
    c(30L, 2L),
    c(38L, 2L),
    c(10L, 5L),
    c(38L, 38L)
  )
  for (ta in types) {
    for (tb in types) {
      # values every type holds, even one with no integer digits
      a <- decimal128(c("0", "0.5"), ta[[1L]], ta[[2L]])
      b <- decimal128(c("0", "-0.5"), tb[[1L]], tb[[2L]])
      r <- c(a, b)
      type <- duck_typeof(
        con,
        sprintf(
          "[%s, %s]",
          dec_sql("'0'", ta[[1L]], ta[[2L]]),
          dec_sql("'0'", tb[[1L]], tb[[2L]])
        )
      )
      expect_identical(paste0(dec_typeof(r), "[]"), type)
      duck <- DBI::dbGetQuery(
        con,
        sprintf(
          "SELECT unnest([%s, %s])::VARCHAR AS r",
          paste(
            sprintf(
              "CAST('%s' AS DECIMAL(%d, %d))",
              as.character(a),
              ta[[1L]],
              ta[[2L]]
            ),
            collapse = ", "
          ),
          paste(
            sprintf(
              "CAST('%s' AS DECIMAL(%d, %d))",
              as.character(b),
              tb[[1L]],
              tb[[2L]]
            ),
            collapse = ", "
          )
        )
      )$r
      expect_identical(as.character(r), duck)
    }
  }
  a <- decimal128(c(p = "1.25"), 5, 2)
  for (it in list(
    list(2L, "INTEGER"),
    list(int64(2), "BIGINT"),
    list(uint64(2), "UBIGINT"),
    list(int128(2), "HUGEINT"),
    list(uint128(2), "UHUGEINT")
  )) {
    type <- duck_typeof(
      con,
      sprintf("[%s, CAST(2 AS %s)]", dec_sql("'0'", 5L, 2L), it[[2L]])
    )
    expect_identical(paste0(dec_typeof(c(a, it[[1L]])), "[]"), type)
    if (is.object(it[[1L]])) {
      # a bare integer first is base c(), which no package can change
      expect_identical(
        c(a, it[[1L]]),
        stats::setNames(c(it[[1L]], a)[c(2, 1)], c("p", ""))
      )
    }
  }
  expect_identical(
    as.character(c(a, "3.5", NA, b = 4L)),
    c("1.25", "3.50", NA, "4.00")
  )
  expect_identical(names(c(a, b = 4L)), c("p", "b"))
  expect_identical(c(a), a)
  expect_identical(c(a, NULL), a)
})

test_that("c() of a scale it must cut is exact or NA with a warning", {
  a <- decimal128(c("1.2345600000", "1.23456789012345"), 30, 20)
  b <- decimal128("12345678901234567890123456.78", 30, 2)
  expect_warning(r <- c(a, b), class = "zuint_cast_warning")
  expect_identical(dec_typeof(r), "DECIMAL(38,10)")
  expect_identical(
    as.character(r),
    c("1.2345600000", NA, "12345678901234567890123456.7800000000")
  )
})

# ---- conversion -----------------------------------------------------------------

test_that("to double is DuckDB's cast; to the integer types is exact or NA", {
  con <- local_duckdb_plain()
  texts <- dec_texts(40L, 30L, 7L, seed = 4L)
  x <- decimal128(texts, 30L, 7L)
  duck <- duck_df(
    con,
    data.frame(x = texts),
    "CAST(CAST(x AS DECIMAL(30, 7)) AS DOUBLE)"
  )
  expect_identical(as.double(x), duck)
  expect_no_warning(as.double(x))

  x <- decimal128(c(a = "12.00", b = "-3.00", c = "12.50", d = NA), 5, 2)
  expect_warning(i <- as.integer(x), class = "zuint_cast_warning")
  expect_identical(i, c(12L, -3L, NA, NA))
  expect_warning(y <- int64(x), class = "zuint_cast_warning")
  expect_identical(y, int64(c(a = 12, b = -3, c = NA, d = NA)))
  expect_warning(u <- uint64(x), class = "zuint_cast_warning")
  expect_identical(as.character(u), c("12", NA, NA, NA))
  top <- decimal128(c(strrep("9", 38), paste0("-", strrep("9", 38))), 38, 0)
  expect_identical(as.character(int128(top)), as.character(top))
  expect_warning(int64(top), class = "zuint_cast_warning")
  expect_identical(as_integer64(decimal128("7", 5, 0)), as_integer64(int64(7)))
  expect_identical(as.logical(x), c(TRUE, TRUE, TRUE, NA))
  expect_identical(as.character(x), c("12.00", "-3.00", "12.50", NA))
})

test_that("format, print and str show every digit of the scale", {
  x <- decimal128(c(a = "1.5", b = "-0.05", c = NA, d = "1234.5"), 7, 2)
  expect_identical(
    format(x),
    c(a = "   1.50", b = "  -0.05", c = "     NA", d = "1234.50")
  )
  expect_identical(format(x, big.mark = ",")[["d"]], "1,234.50")
  out <- capture.output(print(x))
  expect_identical(out[[1L]], "<decimal128(7, 2)[4]>")
  expect_match(out[[3L]], "1.50 +-0.05 +NA +1234.50")
  expect_identical(
    capture.output(print(decimal128(character(), 5, 2))),
    "<decimal128(5, 2)[0]>"
  )
  expect_identical(
    capture.output(str(x)),
    " decimal128(7, 2) [1:4] 1.50 -0.05 NA 1234.50"
  )
  expect_identical(format(decimal128(".05", 2, 2)), ".05")
  expect_identical(
    unclass(summary(x)),
    c(
      "Min." = "-0.05",
      Mean = "411.983333333333",
      "Max." = "1234.50",
      "NA's" = "1"
    )
  )
})

# ---- ordering, hashing, summaries -----------------------------------------------

test_that("sorting and hashing order and match the values", {
  coefs <- fx_coefs(60L, 20L, seed = 11L)
  coefs <- c(coefs, coefs[1:10], NA)
  x <- decimal128(fx_format(coefs, 20L, 4L), 20L, 4L)
  key <- dec_sort_key(coefs)
  want <- fx_format(coefs[!is.na(coefs)][order(key[!is.na(coefs)])], 20L, 4L)
  expect_identical(as.character(sort(x)), want)
  expect_identical(as.character(sort(x, decreasing = TRUE)), rev(want))
  expect_identical(
    as.character(sort(x, na.last = TRUE)),
    c(want, NA)
  )
  expect_identical(order(x), order(key, na.last = TRUE))
  expect_identical(duplicated(x), duplicated(coefs))
  expect_identical(anyDuplicated(x), anyDuplicated(coefs))
  expect_identical(as.character(unique(x)), fx_format(unique(coefs), 20L, 4L))
  expect_identical(match(x, rev(x)), match(coefs, rev(coefs)))
  expect_identical(x %in% x[1:5], coefs %in% coefs[1:5])
  r <- xtfrm(x)
  expect_identical(is.na(r), is.na(coefs))
  expect_identical(order(r), order(key))
})

test_that("sum is DECIMAL(38, s); min, max and range keep the type; mean is DuckDB's avg", {
  skip_if_not_installed("gmp")
  con <- local_duckdb_plain()
  for (type in list(c(5L, 2L), c(18L, 9L), c(38L, 0L), c(38L, 30L))) {
    p <- type[[1L]]
    s <- type[[2L]]
    coefs <- fx_coefs(40L, p, seed = p)
    # keep the sum in range at 38 digits
    coefs <- coefs[abs(as.numeric(coefs)) < 1e36 | p < 38L]
    texts <- fx_format(coefs, p, s)
    x <- decimal128(texts, p, s)
    label <- sprintf("DECIMAL(%d, %d)", p, s)
    duck <- DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT sum(v)::VARCHAR AS s, min(v)::VARCHAR AS lo, max(v)::VARCHAR AS hi, avg(v) AS m, typeof(sum(v)) AS t FROM (SELECT CAST(x AS DECIMAL(%d, %d)) AS v FROM (SELECT unnest([%s]) AS x))",
        p,
        s,
        paste0("'", texts, "'", collapse = ", ")
      )
    )
    expect_identical(as.character(sum(x)), duck$s, label = label)
    expect_identical(dec_typeof(sum(x)), duck$t, label = label)
    expect_identical(
      as.character(sum(x)),
      fx_format(as.character(sum(gmp::as.bigz(coefs))), 38L, s),
      label = label
    )
    expect_identical(as.character(min(x)), duck$lo, label = label)
    expect_identical(as.character(max(x)), duck$hi, label = label)
    expect_identical(range(x), c(min(x), max(x)), label = label)
    expect_identical(dec_typeof(min(x)), sprintf("DECIMAL(%d,%d)", p, s))
    # DuckDB divides a long double, so its last bit depends on the platform
    expect_equal(
      mean(x),
      duck$m,
      tolerance = 4 * .Machine$double.eps,
      label = label
    )
  }
  x <- decimal128(c("1.5", NA), 5, 2)
  expect_true(is.na(sum(x)))
  expect_identical(as.character(sum(x, na.rm = TRUE)), "1.50")
  expect_true(is.na(min(x)))
  expect_warning(m <- min(x[0]), class = "zuint_empty_warning")
  expect_identical(m, Inf)
  top <- decimal128(rep(strrep("9", 38), 2), 38, 0)
  expect_warning(r <- sum(top), class = "zuint_overflow_warning")
  expect_true(is.na(r))
  expect_identical(prod(x, na.rm = TRUE), 1.5)
  expect_true(any(x, na.rm = TRUE))
  expect_identical(as.character(min(decimal128("2.5", 5, 1), 1L)), "1.0")
  expect_identical(as.character(max(int64(3), decimal128("2.5", 5, 1))), "3.0")
  expect_identical(median(decimal128(c("1.00", "2.00", "4.00"), 5, 2)), 2)
})

# ---- vctrs and pillar ------------------------------------------------------------

test_that("vctrs combines and casts with DuckDB's common type", {
  skip_if_not_installed("vctrs")
  a <- decimal128(c("1.25", NA), 5, 2)
  b <- decimal128("1.500", 7, 3)
  expect_identical(vctrs::vec_ptype2(a, b), decimal128(character(), 7, 3))
  expect_identical(vctrs::vec_ptype2(a, 1L), decimal128(character(), 12, 2))
  expect_identical(
    vctrs::vec_ptype2(int64(1), a),
    decimal128(character(), 21, 2)
  )
  expect_identical(vctrs::vec_c(a, b), c(a, b))
  expect_identical(vctrs::vec_c(a, 2L), c(a, 2L))
  expect_identical(vctrs::vec_cast(b, a), decimal128("1.50", 5, 2))
  expect_error(
    vctrs::vec_cast(decimal128("1.255", 7, 3), a),
    class = "vctrs_error_cast_lossy"
  )
  expect_identical(vctrs::vec_cast(2L, a), decimal128("2", 5, 2))
  expect_identical(vctrs::vec_cast(2.5, a), decimal128("2.5", 5, 2))
  expect_error(vctrs::vec_cast(2.555, a), class = "vctrs_error_cast_lossy")
  expect_identical(vctrs::vec_cast(decimal128("3.00", 5, 2), int64()), int64(3))
  expect_error(vctrs::vec_cast(a[1], int64()), class = "vctrs_error_cast_lossy")
  expect_identical(vctrs::vec_cast(a, double()), c(1.25, NA))
  # vctrs fills its own slots: the type's NA, not a value
  expect_identical(is.na(vctrs::vec_init(a, 2)), c(TRUE, TRUE))
  expect_identical(vctrs::vec_slice(a, c(2, 1, NA)), a[c(2, 1, NA)])
  x <- decimal128(c("2.00", "-1.00", "2.00", NA), 5, 2)
  expect_identical(vctrs::vec_unique(x), unique(x))
  expect_identical(vctrs::vec_order(x), order(x))
  expect_identical(vctrs::vec_ptype_abbr(x), "dec")
  expect_identical(vctrs::vec_ptype_full(x), "decimal128(5, 2)")
})

test_that("decimal128 columns work in data frames and tibbles", {
  x <- decimal128(c("1.25", "-3.50", NA), 5, 2)
  df <- data.frame(x = x)
  expect_identical(df$x, x)
  expect_identical(df[2:3, "x"], x[2:3])
  skip_if_not_installed("tibble")
  skip_if_not_installed("pillar")
  tb <- tibble::tibble(x = x)
  out <- capture.output(print(tb))
  expect_true(any(grepl("<dec(5,2)>", out, fixed = TRUE)))
  expect_true(any(grepl("-3.50", out, fixed = TRUE)))
})
