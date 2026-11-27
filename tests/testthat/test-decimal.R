# The decimal128 class (design 2.2, Stage 9.2). DuckDB 2.0.1 is the oracle
# for types and values, compared as text; gmp for exact orders and sums.

# ---- construction -------------------------------------------------------------

test_that("decimal128() reads text as the core does, and NA quietly", {
  withr::local_seed(6)
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
    # In hex, so that every platform has the same doubles: R on macOS arm64
    # has no long double, and its parser rounds a decimal like 1e30 to a
    # neighbouring double.
    d <- c(
      0,
      -0.5,
      0x1.5666666666666p+1, # 2.675
      0x1.0147ae147ae14p+0, # 1.005
      0.125,
      0x1.edd2f1a9fbe77p+6, # 123.456
      -0x1.8ffae147ae148p+6, # -99.995
      1e10,
      0x1.93e5939a08ceap+99, # 1e30
      -0x1.e17b84357691bp+122, # -1e37
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
  # NaN is NA quietly, as int128(NaN) is; Inf does not convert
  expect_no_warning(x <- decimal128(c(NaN, 1), 5, 2))
  expect_identical(is.na(x), is.na(int128(c(NaN, 1))))
  expect_warning(decimal128(Inf, 5, 2), class = "zuint_cast_warning")
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
  # comparison is exact with any double instead (design 5)
  expect_identical(a == 1.25, c(TRUE, FALSE))
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
    for (i in seq(1L, n, by = 5L)) {
      lo <- if (sa <= sb) ca[[i]] else cb[[i]]
      same <- as.character(gmp::as.bigz(lo) * gmp::as.bigz(10)^abs(sb - sa))
      if (nchar(sub("^-", "", same)) <= 38L) {
        if (sa <= sb) cb[[i]] <- same else ca[[i]] <- same
      }
    }
    a <- decimal128(fx_format(ca, 38L, sa), 38L, sa)
    b <- decimal128(fx_format(cb, 38L, sb), 38L, sb)
    s <- max(sa, sb)
    x <- gmp::as.bigz(ca) * gmp::as.bigz(10)^(s - sa)
    y <- gmp::as.bigz(cb) * gmp::as.bigz(10)^(s - sb)
    want <- as.integer(x > y) - as.integer(x < y)
    label <- sprintf("scales %d and %d", sa, sb)
    expect_true(any(want == 0), label = label)
    expect_identical(a < b, want < 0, label = label)
    expect_identical(a <= b, want <= 0, label = label)
    expect_identical(a == b, want == 0, label = label)
    expect_identical(a >= b, want >= 0, label = label)
  }
  a <- decimal128(c("1.5", NA), 5, 2)
  expect_identical(a == decimal128("1.500", 10, 3), c(TRUE, NA))
  expect_identical(a > 1L, c(TRUE, NA))
  expect_identical(int64(2) > a, c(TRUE, NA))
  expect_identical(a != 2, c(TRUE, NA))
})

test_that("/, %%, %/%, ^ and most of Math are computed in double; abs and - keep the type", {
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
  expect_identical(
    signif(a, 1),
    stats::setNames(signif(as.double(a), 1), names(a))
  )
  expect_identical(cumprod(a), stats::setNames(cumprod(as.double(a)), names(a)))
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
      duck <- duck_query(
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
      Median = "1.5",
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
    duck <- duck_query(
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
  out <- capture.output(print(pillar_tbl(data.frame(x = x))))
  expect_true(any(grepl("<dec(5,2)>", out, fixed = TRUE)))
  expect_true(any(grepl("-3.50", out, fixed = TRUE)))
})

# ---- the review of 625e4a4 ------------------------------------------------------

test_that("match(), %in%, table() and zu_match() find equal values across scales (#108, #126)", {
  withr::local_seed(108)
  # == is the oracle; it is checked against gmp above
  for (k in 1:10) {
    sa <- sample(0:6, 1L)
    sb <- sample(0:6, 1L)
    whole <- sample(-30:30, 40L, TRUE)
    frac <- sample(0:9, 40L, TRUE)
    texts <- sprintf("%d.%d", whole, frac)
    texts[c(3L, 17L)] <- c("0", "-0.00")
    x <- decimal128(texts, 20L, max(sa, 1L))
    tab <- decimal128(texts[sample(40L, 25L)], 20L, max(sb, 1L))
    want <- vapply(
      seq_along(x),
      function(i) match(TRUE, (x[i] == tab) %in% TRUE),
      integer(1)
    )
    label <- sprintf("scales %d and %d", max(sa, 1L), max(sb, 1L))
    expect_identical(match(x, tab), want, label = label)
    expect_identical(x %in% tab, !is.na(want), label = label)
    expect_identical(zu_match(x, tab), want, label = label)
    expect_identical(x %zin% tab, !is.na(want), label = label)
  }
  expect_identical(decimal128("2.0", 3, 1) %in% 1:3, TRUE)
  expect_identical(match(decimal128("2.0", 3, 1), int64(c(1, 2))), 2L)
  expect_identical(match(decimal128(".50", 2, 2), decimal128("0.5", 2, 1)), 1L)
  expect_identical(zu_match(1L, decimal128(c("2.00", "1.00"), 5, 2)), 2L)
  expect_identical(zu_match(decimal128(c("1.50", NA), 5, 2), 1.5), c(1L, NA))
  t2 <- table(c(decimal128("1.0", 5, 1), decimal128(c("1.00", "2.50"), 5, 2)))
  expect_identical(as.vector(t2), c(2L, 1L))
  # a value beyond 38 digits matches nothing, quietly (#58)
  expect_no_warning(
    r <- zu_match(
      uint128(paste0("2", strrep("0", 38))),
      decimal128(c("1", NA), 5, 0)
    )
  )
  expect_identical(r, NA_integer_)
  # nor does a table value lost that way match x's NA: the real NA does
  big <- uint128(c(paste0("2", strrep("0", 38)), NA))
  expect_identical(zu_match(decimal128(NA, 5, 0), big), 2L)
})

test_that("x[i] <- value is exact and follows zuint.double, as c() does (#109)", {
  x <- decimal128(c("1.25", "2.50"), 10, 2)
  y <- x
  expect_warning(
    y[1] <- decimal128("1.255", 10, 3),
    class = "zuint_cast_warning"
  )
  expect_identical(as.character(y), c(NA, "2.50"))
  y <- x
  y[[2]] <- decimal128("7.5", 3, 1)
  expect_identical(as.character(y), c("1.25", "7.50"))
  expect_error(y[1] <- 1.255, class = "zuint_double_error")
  expect_error(y[[1]] <- 1.255, class = "zuint_double_error")
  y[1] <- 3
  expect_identical(as.character(y), c("3.00", "7.50"))
  # text rounds, as decimal128() and c() read it
  y[2] <- "7.777"
  expect_identical(as.character(y), c("3.00", "7.78"))
  expect_identical(c(x, "7.777")[3], decimal128("7.78", 10, 2))
  # past the end: the type's NA in the padding, the value at the end
  y <- x
  y[4] <- 1L
  expect_identical(as.character(y), c("1.25", "2.50", NA, "1.00"))
  # a value the type can't hold is NA with a warning, never wrapped
  y <- x
  expect_warning(y[1] <- int64("100000000000"), class = "zuint_cast_warning")
  expect_true(is.na(y[1]))
  # the same value by every route: c(), [<- and vec_assign() agree
  v <- decimal128("1.555", 10, 3)
  expect_warning(r <- c(decimal128("0", 10, 2), v), NA)
  expect_identical(decimal_scale(r), 3L)
  skip_if_not_installed("vctrs")
  expect_error(vctrs::vec_assign(x, 1L, v), class = "vctrs_error_cast_lossy")
  withr::local_options(zuint.double = "allow")
  y <- x
  expect_warning(y[1] <- 1.375, class = "zuint_double_warning")
  expect_identical(as.character(y), c("1.38", "2.50"))
})

test_that("blank and \"NA\" text is missing, not lost (#110)", {
  d <- decimal128("1.25", 10, 2)
  blank <- c("NA", "", " ", " NA ", "\t\v\f\r\n", NA)
  expect_no_warning(r <- c(d, blank))
  expect_identical(as.character(r), c("1.25", rep(NA, length(blank))))
  expect_no_warning(r <- decimal128(blank, 5, 2))
  expect_true(all(is.na(r)))
  y <- d
  expect_no_warning(y[2] <- "NA")
  expect_identical(is.na(y), c(FALSE, TRUE))
  # text that is not a number still warns
  expect_warning(c(d, "1.2.3"), class = "zuint_cast_warning")
})

test_that("a warning counts each result an operand lost after recycling (#111)", {
  big <- decimal128(strrep("9", 38), 38, 0)
  expect_snapshot(r <- big + decimal128(rep("0.1", 5), 10, 1))
  expect_identical(sum(is.na(r)), 5L)
})

test_that("NaN is NA quietly, as for the integer types (#112)", {
  expect_no_warning(r <- decimal128(c(NaN, 2), 5, 2))
  expect_identical(as.character(r), c(NA, "2.00"))
  expect_no_warning(r <- decimal128("1.5", 5, 2) + NaN)
  expect_true(is.na(r))
})

test_that("comparison with a double is exact, whatever the double (#113)", {
  d <- decimal128(c("1.50", "-2.25", NA, "0.00", "0.10", "0.30"), 5, 2)
  expect_identical(d == 1.5, c(TRUE, FALSE, NA, FALSE, FALSE, FALSE))
  expect_identical(d < 1.75, c(TRUE, TRUE, NA, TRUE, TRUE, TRUE))
  expect_identical(d <= -2.25, c(FALSE, TRUE, NA, FALSE, FALSE, FALSE))
  expect_identical(1.5 == d, d == 1.5)
  expect_identical(d < Inf, c(TRUE, TRUE, NA, TRUE, TRUE, TRUE))
  expect_identical(d > -Inf, d < Inf)
  expect_identical(d < 1e300, d < Inf)
  expect_identical(d == NaN, rep(NA, 6))
  # 0.1 as a double is 0.1000000000000000055..., and 0.1 + 0.2 is
  # 0.3000000000000000444...: no decimal of scale 2 equals either
  expect_identical(d[5] == 0.1, FALSE)
  expect_identical(d[5] < 0.1, TRUE)
  expect_identical(d[6] < 0.1 + 0.2, TRUE)
  expect_identical(d[6] > 0.3, TRUE) # 0.29999999999999998889...
  # every double that is a decimal of the scale compares equal
  skip_if_not_installed("gmp")
  withr::local_seed(113)
  for (s in c(0L, 1L, 5L, 20L, 38L)) {
    p <- 38L
    k <- sample(-2^20:2^20, 50L)
    v <- c(k / 2^sample(0:min(s, 20L), 50L, TRUE), 2^60, -2^62, 1e37)
    if (s > 0L) {
      v <- v[abs(v) < 10^(p - s)]
    }
    # each double's exact value, as a fraction, against the decimal's
    x <- decimal128(v, p, s)
    exact <- gmp::as.bigq(v)
    dec <- gmp::as.bigq(
      gmp::as.bigz(as.character(dec_view(x))),
      gmp::as.bigz(10)^s
    )
    want <- as.integer(dec > exact) - as.integer(dec < exact)
    label <- sprintf("scale %d", s)
    expect_identical(x == v, want == 0L, label = label)
    expect_identical(x < v, want < 0L, label = label)
    expect_identical(x >= v, want >= 0L, label = label)
    expect_identical(v > x, want < 0L, label = label)
  }
})

test_that("an integer or whole double beyond 38 digits compares by its sign (#113)", {
  d <- decimal128(c("1.25", NA, "-99"), 5, 2)
  huge <- uint128(paste0("2", strrep("0", 38)))
  expect_no_warning(r <- d < huge)
  expect_identical(r, c(TRUE, NA, TRUE))
  expect_identical(int128(paste0("-1", strrep("0", 38))) < d, c(TRUE, NA, TRUE))
  expect_identical(d == 1e30, c(FALSE, NA, FALSE))
  expect_identical(d < 1e38, c(TRUE, NA, TRUE))
  expect_identical(decimal128(strrep("9", 38), 38, 0) < 1e38, TRUE)
  expect_identical(d > -1e300, c(TRUE, NA, TRUE))
})

test_that("format() and summary() keep \".\" under OutDec (#114)", {
  x <- decimal128(c("-1234567.891234", "2.5", NA), 20, 6)
  y <- int64(c(1234567, 2, NA))
  plain <- list(format(x, big.mark = " "), format(x), summary(x), summary(y))
  withr::local_options(OutDec = ",", scipen = -5, digits = 3)
  expect_identical(format(x, big.mark = " ")[[1L]], "-1 234 567.891234")
  expect_identical(
    list(format(x, big.mark = " "), format(x), summary(x), summary(y)),
    plain
  )
  expect_false(any(grepl(",", summary(x), fixed = TRUE)))
})

test_that("bit64 can't compute an integer64 with a decimal128 (#115)", {
  skip_if_not_installed("bit64")
  # bit64 registers its methods when its namespace loads
  requireNamespace("bit64", quietly = TRUE)
  zu_register_bit64()
  d <- decimal128("1.5", 2, 1)
  expect_error(bit64::as.integer64(d), class = "zuint_incompatible_error")
  expect_identical(as.character(d * bit64::as.integer64(2)), "3.0")
  expect_identical(
    as_integer64(decimal128("7.00", 5, 2)),
    bit64::as.integer64(7)
  )
})

test_that("decimal128(x, precision) keeps x's scale, and the other way round (#124)", {
  d <- decimal128(c("1.25", "-2.50"), 5, 2)
  expect_identical(decimal128(d, 20), decimal128(c("1.25", "-2.50"), 20, 2))
  expect_identical(decimal128(d, scale = 1), decimal128(c("1.3", "-2.5"), 5, 1))
  # the scale stays, so one digit holds neither value
  expect_warning(r <- decimal128(d, 1), class = "zuint_cast_warning")
  expect_identical(dec_typeof(r), "DECIMAL(1,1)")
})

test_that("c() keeps its own arguments out of the data, and names in the double fallback (#128)", {
  d <- decimal128(c(a = "1.50", b = "-2.25"), 5, 2)
  expect_identical(c(d, use.names = FALSE), unname(d))
  expect_identical(c(d, d[1], recursive = TRUE), c(d, d[1]))
  withr::local_options(zuint.double = "allow")
  expect_warning(r <- c(x = d[[1]], y = 0.5), class = "zuint_double_warning")
  expect_identical(r, c(x = 1.5, y = 0.5))
})

test_that("vctrs types a double as c() types an int32 one (#129)", {
  skip_if_not_installed("vctrs")
  d <- decimal128(c("1.50", NA), 5, 2)
  expect_identical(vctrs::vec_c(d, 3), c(d, 3))
  expect_identical(vctrs::vec_ptype2(d, 1.5), vctrs::vec_ptype2(d, 1L))
  # vctrs types prototypes: a double past int32 is a lossy cast
  expect_error(vctrs::vec_c(d, 2^40), class = "vctrs_error_cast_lossy")
})

test_that("zu_ifelse() and zu_vapply() take decimals (#126)", {
  d <- decimal128(c("1.0", "2.5", "-3.0"), 10, 1)
  e <- decimal128(c("7.00", "8.25", "9.00"), 10, 2)
  test <- c(TRUE, FALSE, NA)
  r <- zu_ifelse(test, d, e)
  both <- c(d, e)
  expect_identical(r, c(both[1L], both[5L], decimal128(NA, 11, 2)))
  expect_identical(
    zu_ifelse(c(a = TRUE, b = FALSE), d[1], 3L),
    c(a = d[1], b = 3L)[1:2] |> stats::setNames(c("a", "b"))
  )
  r <- zu_vapply(1:3, function(i) d[i] * 2L, decimal128(0, 12, 1))
  expect_identical(r, decimal128(c("2.0", "5.0", "-6.0"), 12, 1))
  expect_warning(
    zu_vapply(1L, function(i) decimal128("1.25", 5, 2), decimal128(0, 5, 1)),
    class = "zuint_cast_warning"
  )
})

test_that("round(), floor(), ceiling() and trunc() give DuckDB's type and value (#127)", {
  con <- local_duckdb_plain()
  types <- list(
    c(2L, 0L),
    c(5L, 0L),
    c(3L, 1L),
    c(5L, 2L),
    c(10L, 2L),
    c(18L, 3L),
    c(19L, 3L),
    c(38L, 0L),
    c(38L, 2L),
    c(38L, 38L)
  )
  for (type in types) {
    p <- type[[1L]]
    s <- type[[2L]]
    coefs <- c(fx_coefs(20L, p, seed = p + s), "5", "-5", "25", "-35", "0")
    # ties at every digit the rounding can cut
    ties <- paste0(c("", "-"), "5", strrep("0", 0:(p - 1L)))
    coefs <- unique(c(coefs, ties[nchar(sub("-", "", ties)) <= p]))
    texts <- fx_format(coefs, p, s)
    x <- decimal128(texts, p, s)
    df <- data.frame(x = texts)
    cases <- c(
      lapply(c(-p - 1L, -p, -2L, -1L, 0L, 1L, 2L, s, s + 1L), function(d) {
        list(
          r = function(x) round(x, d),
          sql = sprintf("round(%%s, %d)", d),
          d = d
        )
      }),
      list(
        list(r = floor, sql = "floor(%s)", d = NA),
        list(r = ceiling, sql = "ceil(%s)", d = NA),
        list(r = trunc, sql = "trunc(%s)", d = NA)
      )
    )
    for (case in cases) {
      label <- sprintf("%s on DECIMAL(%d, %d)", case$sql, p, s)
      want_type <- duck_typeof(con, sprintf(case$sql, dec_sql("'0'", p, s)))
      duck <- duck_df(
        con,
        df,
        sprintf("TRY(%s)::VARCHAR", sprintf(case$sql, dec_sql("x", p, s)))
      )
      r <- withCallingHandlers(
        case$r(x),
        zuint_overflow_warning = function(w) invokeRestart("muffleWarning")
      )
      expect_identical(dec_typeof(r), want_type, label = label)
      # TRY() is NULL where DuckDB overflows (rounding 38 nines up): NA here
      expect_identical(as.character(r), duck, label = label)
    }
  }
  # names stay; NA stays
  a <- decimal128(c(u = "1.25", v = NA), 5, 2)
  expect_identical(round(a, 1), decimal128(c(u = "1.3", v = NA), 5, 1))
  expect_identical(floor(a), decimal128(c(u = "1", v = NA), 5, 0))
})

test_that("cumsum() is DuckDB's running sum; cummax() and cummin() keep the type (#127)", {
  con <- local_duckdb_plain()
  for (type in list(c(5L, 2L), c(18L, 9L), c(38L, 0L), c(38L, 30L))) {
    p <- type[[1L]]
    s <- type[[2L]]
    coefs <- fx_coefs(30L, p, seed = 7L * p)
    coefs <- coefs[abs(as.numeric(coefs)) < 1e36 | p < 38L]
    texts <- fx_format(coefs, p, s)
    x <- decimal128(texts, p, s)
    label <- sprintf("DECIMAL(%d, %d)", p, s)
    df <- data.frame(x = texts)
    win <- function(f) {
      duck_df(
        con,
        df,
        sprintf(
          "%s(%s) OVER (ORDER BY i ROWS UNBOUNDED PRECEDING)::VARCHAR",
          f,
          dec_sql("x", p, s)
        )
      )
    }
    expect_identical(as.character(cumsum(x)), win("sum"), label = label)
    expect_identical(dec_typeof(cumsum(x)), sprintf("DECIMAL(38,%d)", s))
    expect_identical(as.character(cummax(x)), win("max"), label = label)
    expect_identical(as.character(cummin(x)), win("min"), label = label)
    expect_identical(dec_typeof(cummax(x)), dec_typeof(x))
  }
  # NA propagates, as base cumsum() does; past 38 digits NA from there on
  x <- decimal128(c("1.5", NA, "2.0"), 5, 1)
  expect_identical(is.na(cumsum(x)), is.na(cumsum(as.double(x))))
  top <- decimal128(c(strrep("9", 38), "1", "-5"), 38, 0)
  expect_warning(r <- cumsum(top), class = "zuint_overflow_warning")
  expect_identical(as.character(r), c(strrep("9", 38), NA, NA))
})

# ---- mutants and limits the review found unchecked (#118, #121) ----------------

test_that("the product scale stops at 38, and DuckDB's 18-digit cap at scale 18 (#121)", {
  con <- local_duckdb_plain()
  for (pair in list(
    c(38, 19, 38, 18),
    c(38, 19, 38, 19),
    c(38, 20, 38, 19),
    c(9, 8, 9, 9),
    c(9, 9, 9, 9),
    c(10, 9, 9, 9),
    c(18, 9, 18, 8),
    c(19, 9, 18, 8),
    c(18, 9, 18, 9),
    c(18, 9, 18, 10)
  )) {
    pa <- pair[[1L]]
    sa <- pair[[2L]]
    pb <- pair[[3L]]
    sb <- pair[[4L]]
    label <- sprintf("DECIMAL(%d, %d) * DECIMAL(%d, %d)", pa, sa, pb, sb)
    want <- duck_typeof(
      con,
      sprintf("%s * %s", dec_sql("'0'", pa, sa), dec_sql("'0'", pb, sb))
    )
    a <- decimal128("0", pa, sa)
    b <- decimal128("0", pb, sb)
    if (want == "ERROR") {
      expect_error(a * b, class = "zuint_incompatible_error", label = label)
    } else {
      expect_identical(dec_typeof(a * b), want, label = label)
    }
  }
})

test_that("a whole double is INTEGER, BIGINT or HUGEINT at DuckDB's thresholds (#121)", {
  con <- local_duckdb_plain()
  a <- decimal128("1.5", 5, 2)
  # each double built by arithmetic, which is exact everywhere: R's parser
  # reads 19-digit text inexactly where long double is double (arm64)
  vals <- list(
    "2147483647" = 2^31 - 1,
    "2147483648" = 2^31,
    "-2147483648" = -2^31,
    "-2147483649" = -2^31 - 1,
    "9223372036854774784" = 2^63 - 1024,
    "9223372036854775808" = 2^63,
    "-9223372036854775808" = -2^63
  )
  for (lit in names(vals)) {
    want <- duck_typeof(con, sprintf("%s + %s", dec_sql("'0'", 5, 2), lit))
    expect_identical(dec_typeof(a + vals[[lit]]), want, label = lit)
  }
})

test_that("sum() fits DECIMAL(38, s) exactly, beyond int64 and within int128 (#118, #121)", {
  nines <- decimal128(c(strrep("9", 37), strrep("9", 37)), 38, 0)
  expect_identical(as.character(sum(nines)), paste0("1", strrep("9", 36), "8"))
  # 6e37 twice is 1.2e38: past 38 digits, inside int128
  six <- decimal128(rep(paste0("6", strrep("0", 37)), 2), 38, 0)
  expect_warning(r <- sum(six), class = "zuint_overflow_warning")
  expect_true(is.na(r))
  edge <- decimal128(
    c(paste0("5", strrep("0", 37)), paste0("4", strrep("9", 37))),
    38,
    0
  )
  expect_identical(as.character(sum(edge)), strrep("9", 38))
  expect_warning(
    sum(c(edge, decimal128("1", 38, 0))),
    class = "zuint_overflow_warning"
  )
})

test_that("the vctrs casts to integer and double refuse a lossy decimal (#118)", {
  skip_if_not_installed("vctrs")
  expect_error(
    vctrs::vec_cast(decimal128("1.5", 5, 1), integer()),
    class = "vctrs_error_cast_lossy"
  )
  expect_identical(vctrs::vec_cast(decimal128("2.0", 5, 1), integer()), 2L)
  expect_error(
    vctrs::vec_cast(decimal128(strrep("9", 38), 38, 0), double()),
    class = "vctrs_error_cast_lossy"
  )
  expect_identical(vctrs::vec_cast(decimal128("0.5", 5, 1), double()), 0.5)
})

test_that("range(finite =), median(na.rm =), anyDuplicated(fromLast =) and all.equal() (#118)", {
  x <- decimal128(c("1.5", NA, "-2.0", "1.5"), 5, 1)
  expect_identical(range(x, finite = TRUE), decimal128(c("-2.0", "1.5"), 5, 1))
  expect_identical(range(x, na.rm = TRUE), range(x, finite = TRUE))
  expect_true(all(is.na(range(x))))
  expect_identical(median(x, na.rm = TRUE), 1.5)
  expect_identical(median(x), NA_real_)
  expect_identical(anyDuplicated(x), 4L)
  expect_identical(anyDuplicated(x, fromLast = TRUE), 1L)
  y <- x
  y[1] <- decimal128("1.4", 5, 1)
  expect_identical(all.equal(x, y), "1 of 4 values differ")
  expect_true(all.equal(x, x))
  expect_match(all.equal(x, decimal128(x, 6, 1)), "Types differ")
})
