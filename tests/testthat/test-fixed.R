# The fixed-point core (design 2.2, Stage 9.1) through its internal entry
# points. Two oracles: gmp computes each exact answer from parts the test
# chose, and DuckDB 2.0.1's casts give the engine's. zuint differs from
# DuckDB in two recorded ways (design 2.2), and every difference the tests
# see must be one of them.

test_that("parsing gives the exact value where DuckDB reads the text", {
  con <- local_duckdb_plain()
  withr::local_seed(20261125)
  types <- fx_types()
  for (k in seq_len(nrow(types))) {
    p <- types$p[k]
    s <- types$s[k]
    cases <- fx_texts(150L, p, s)
    ours <- fx_parse(cases$text, p, s)
    duck <- duck_coef(duck_eval(
      con,
      cases$text,
      sprintf("TRY_CAST(x AS DECIMAL(%d, %d))::VARCHAR", p, s)
    ))
    exact <- fx_exact(cases$neg, cases$int, cases$frac, cases$e, s)
    fits <- fx_fits(exact, p)
    label <- sprintf("DECIMAL(%d, %d)", p, s)

    # accepted exactly when DuckDB accepts and the exact value fits
    expect_identical(ours$status == fx_ok, !is.na(duck) & fits, label = label)
    # and then it is the exact value, rounded half away from zero
    ok <- ours$status == fx_ok
    expect_identical(ours$coef[ok], as.character(exact[ok]), label = label)

    # Where DuckDB accepts what zuint refuses, its value has more than p
    # digits: deviation 1.
    wide <- !is.na(duck) & !ok
    if (any(wide)) {
      expect_true(all(!fx_fits(duck[wide], p)), label = label)
    }
    # Where both accept and differ, DuckDB is the one that is not exact,
    # the text has an exponent and more digits than DuckDB's storage
    # width keeps: deviation 2.
    differ <- ok & !is.na(duck) & duck != ours$coef
    if (any(differ)) {
      cap <- if (p <= 4L) {
        4L
      } else if (p <= 9L) {
        9L
      } else if (p <= 18L) {
        18L
      } else {
        38L
      }
      ndig <- nchar(cases$int[differ]) + nchar(cases$frac[differ])
      expect_true(all(cases$exp[differ] & ndig > cap), label = label)
    }
  }
})

test_that("parsing matches DuckDB on texts outside the grammar", {
  con <- local_duckdb_plain()
  withr::local_seed(20261126)
  alphabet <- strsplit("0123456789.eE+-_ x\tbn", "")[[1L]]
  base <- fx_texts(1500L, 38L, 6L)$text
  mutate <- function(t) {
    k <- sample(nchar(t) + 1L, 1L)
    c <- sample(alphabet, 1L)
    switch(
      sample(3L, 1L),
      paste0(substr(t, 1L, k - 1L), c, substr(t, k, nchar(t))),
      paste0(substr(t, 1L, k - 1L), substr(t, k + 1L, nchar(t))),
      paste0(substr(t, 1L, k - 1L), c, substr(t, k + 1L, nchar(t)))
    )
  }
  texts <- unique(c(
    vapply(base, mutate, ""),
    "",
    " ",
    ".",
    "-",
    "+",
    "e5",
    "1e",
    "0x1",
    "-0x1",
    "0b1",
    "1e2.",
    "1e2.5",
    "1e+",
    "1e-",
    "1e 2",
    "1 e2",
    "- 1",
    "1__0",
    "_1",
    "1_",
    "1._5",
    "1_.5",
    "--1",
    "+-1",
    "1.2.3",
    "NaN",
    "inf",
    "1e32768",
    "1e-32769"
  ))
  for (s in c(0L, 6L, 38L)) {
    ours <- fx_parse(texts, 38L, s)
    duck <- duck_coef(duck_eval(
      con,
      texts,
      sprintf("TRY_CAST(x AS DECIMAL(38, %d))::VARCHAR", s)
    ))
    # DuckDB's storage width here is 38 digits, so only deviation 1 can
    # differ, and it would show as DuckDB accepting a value too wide
    keep <- is.na(duck) | fx_fits(ifelse(is.na(duck), "0", duck), 38L)
    expect_identical(
      ours$status[keep] == fx_ok,
      !is.na(duck[keep]),
      label = paste("scale", s)
    )
    both <- keep & !is.na(duck)
    expect_identical(ours$coef[both], duck[both], label = paste("scale", s))
  }
})

test_that("a refused text is invalid or out of range, by its grammar", {
  r <- fx_parse(
    c("abc", "", "1.2.3", "0x10", "1e", "999.995", "1e40", "12345e-2"),
    5L,
    2L
  )
  expect_identical(r$status, c(rep(fx_invalid, 5L), rep(fx_overflow, 3L)))
  expect_identical(r$coef, rep(NA_character_, 8L))
  expect_identical(fx_parse(NA_character_, 5L, 2L)$status, NA_integer_)
})

test_that("the two deviations from DuckDB are the ones the design records", {
  # DuckDB 2.0.1 reads "1.234e4" as DECIMAL(4, 0) 12340, five digits
  expect_identical(fx_parse("1.234e4", 4L, 0L)$status, fx_overflow)
  expect_identical(fx_parse("1.234e4", 5L, 0L)$coef, "12340")
  # and "0.0000000001234e10" as DECIMAL(5, 2) 0.00, its digits dropped
  expect_identical(fx_parse("0.0000000001234e10", 5L, 2L)$coef, "123")
  # the same cut at 38 digits: DuckDB ends this one .2792711 (#140); gmp
  # gives the exact value, -3345461776248473059360487613332.27927116
  skip_if_not_installed("gmp")
  digits <- "-3345461776248473059360487613332279271164"
  exact <- gmp::as.bigq(gmp::as.bigz(digits), gmp::as.bigz(10)^9)
  r <- fx_parse("-334546177624847.3059360487613332279271164e16", 38L, 7L)
  expect_identical(
    r$coef,
    as.character(fx_round_half_away(exact * gmp::as.bigz(10)^7))
  )
  expect_identical(r$coef, "-33454617762484730593604876133322792712")
})

test_that("formatting is DuckDB's text", {
  con <- local_duckdb_plain()
  types <- fx_types()
  for (k in seq_len(nrow(types))) {
    p <- types$p[k]
    s <- types$s[k]
    coefs <- fx_coefs(60L, p, seed = 1000L + k)
    ours <- fx_format(coefs, p, s)
    expect_identical(
      ours,
      fx_format_ref(coefs, p, s),
      label = sprintf("(%d, %d)", p, s)
    )
    # DuckDB reads the text back to the same value and writes it the same
    duck <- duck_eval(
      con,
      ours,
      sprintf("CAST(x AS DECIMAL(%d, %d))::VARCHAR", p, s)
    )
    expect_identical(ours, duck, label = sprintf("(%d, %d)", p, s))
    expect_identical(fx_parse(ours, p, s)$coef, coefs)
  }
  expect_identical(
    fx_format(c("50", "-5", "0"), 2L, 2L),
    c(".50", "-.05", ".00")
  )
  expect_identical(
    fx_format(c("50", "-5", "0"), 3L, 2L),
    c("0.50", "-0.05", "0.00")
  )
  # a coefficient beyond its precision is not a value of the type
  expect_identical(fx_format("100", 2L, 0L), NA_character_)
})

test_that("rescaling rounds half away from zero and checks the new precision", {
  con <- local_duckdb_plain()
  pairs <- list(
    c(38, 10, 38, 2),
    c(38, 2, 38, 10),
    c(10, 4, 5, 1),
    c(5, 1, 10, 4),
    c(18, 9, 9, 0),
    c(38, 38, 38, 0),
    c(38, 0, 38, 38),
    c(4, 2, 3, 1),
    c(19, 0, 18, 0),
    c(38, 37, 2, 1)
  )
  for (k in seq_along(pairs)) {
    pr <- as.integer(pairs[[k]])
    coefs <- fx_coefs(80L, pr[1L], seed = 2000L + k)
    ours <- fx_rescale(coefs, pr[2L], pr[3L], pr[4L])
    c <- gmp::as.bigz(coefs)
    q <- gmp::as.bigq(c) *
      gmp::as.bigq(fx_pow10(max(pr[4L] - pr[2L], 0L))) /
      gmp::as.bigq(fx_pow10(max(pr[2L] - pr[4L], 0L)))
    exact <- fx_round_half_away(q)
    fits <- fx_fits(exact, pr[3L])
    label <- paste(pr, collapse = ",")
    expect_identical(ours$status == fx_ok, fits, label = label)
    expect_identical(ours$coef[fits], as.character(exact[fits]), label = label)
    text <- fx_format(coefs, pr[1L], pr[2L])
    duck <- duck_coef(duck_eval(
      con,
      text,
      sprintf(
        "TRY_CAST(CAST(x AS DECIMAL(%d, %d)) AS DECIMAL(%d, %d))::VARCHAR",
        pr[1L],
        pr[2L],
        pr[3L],
        pr[4L]
      )
    ))
    expect_identical(ours$coef, duck, label = label)
  }
})

test_that("rescaling straddles 128 bits and the target precision", {
  top <- as.character(fx_pow10(38) - 1)
  # 10^38 - 1 at scale 0 to scale 1 needs 39 digits
  expect_identical(fx_rescale(top, 0L, 38L, 1L)$status, fx_overflow)
  expect_identical(fx_rescale(top, 1L, 38L, 1L)$coef, top)
  # 9.5 to scale 0: 10, which DECIMAL(1, 0) cannot hold, DECIMAL(2, 0) can
  expect_identical(fx_rescale("95", 1L, 1L, 0L)$status, fx_overflow)
  expect_identical(fx_rescale("95", 1L, 2L, 0L)$coef, "10")
  expect_identical(fx_rescale("94", 1L, 1L, 0L)$coef, "9")
  expect_identical(fx_rescale("-95", 1L, 2L, 0L)$coef, "-10")
  # a power of ten whose product leaves 128 bits
  expect_identical(
    fx_rescale(as.character(fx_pow10(37)), 0L, 38L, 38L)$status,
    fx_overflow
  )
})

test_that("conversion to double is DuckDB's, bit for bit", {
  con <- local_duckdb_plain()
  types <- fx_types()
  for (k in seq_len(nrow(types))) {
    p <- types$p[k]
    s <- types$s[k]
    coefs <- fx_coefs(80L, p, seed = 3000L + k)
    ours <- fx_to_double(coefs, p, s)
    text <- fx_format(coefs, p, s)
    duck <- as.numeric(duck_eval(
      con,
      text,
      sprintf("CAST(CAST(x AS DECIMAL(%d, %d)) AS DOUBLE)", p, s)
    ))
    expect_identical(ours, duck, label = sprintf("(%d, %d)", p, s))
  }
})

test_that("conversion to double rounds to nearest, ties to even", {
  # 2^53 + 1 at scale 0 in DECIMAL(18, 0) is a tie, and goes to 2^53
  expect_identical(fx_to_double("9007199254740993", 18L, 0L), 2^53)
  # and 2^53 + 3 is a tie whose even neighbour is above it
  expect_identical(fx_to_double("9007199254740995", 18L, 0L), 2^53 + 4)
  # 1 + 2^-52 * (0.5 + tiny) needs the sticky bit to round up
  expect_identical(
    fx_to_double("10000000000000001110223024625156540424", 38L, 37L),
    1 + 2^-52
  )
  expect_identical(fx_to_double(c("1", "-1"), 38L, 38L), c(1e-38, -1e-38))
  expect_identical(fx_to_double("0", 38L, 10L), 0)
})

test_that("conversion from double is DuckDB's round(x * 10^s)", {
  con <- local_duckdb_plain()
  withr::local_seed(20261127)
  types <- fx_types()
  for (k in seq_len(nrow(types))) {
    p <- types$p[k]
    s <- types$s[k]
    n <- 200L
    x <- c(
      (sample(-10^min(p, 15):10^min(p, 15), n / 2, TRUE) + 0.5) / 10^s, # ties
      runif(n / 4, -1, 1) * 10^(p - s), # anywhere in range
      c(
        10^(p - s),
        -10^(p - s),
        10^(p - s) * (1 - 1e-16),
        0.125,
        2.675,
        1.005,
        -0.0,
        5e-324
      ),
      runif(n / 4, -1, 1) * 10^(p - s + 1) # beyond it
    )
    ours <- fx_from_double(x, p, s)
    duck <- duck_coef(duck_eval(
      con,
      x,
      sprintf("TRY_CAST(x AS DECIMAL(%d, %d))::VARCHAR", p, s)
    ))
    expect_identical(ours$coef, duck, label = sprintf("(%d, %d)", p, s))
  }
  # NaN is NA, as in the integer types' casts
  r <- fx_from_double(c(NaN, Inf, -Inf, NA, 1e300), 38L, 2L)
  expect_identical(
    r$status,
    c(NA_integer_, fx_invalid, fx_invalid, NA_integer_, fx_overflow)
  )
})

test_that("comparison across scales is exact", {
  # gmp alone: DuckDB compares two DECIMAL(38, s) on a common type that
  # can overflow, so it is no oracle across scales
  skip_if_not_installed("gmp")
  withr::local_seed(20261128)
  a <- fx_coefs(300L, 38L, seed = 4001L)
  b <- fx_coefs(300L, 38L, seed = 4002L)
  n <- min(length(a), length(b))
  a <- a[seq_len(n)]
  b <- b[seq_len(n)]
  # equal values on different scales, and the 128-bit edge of a rescale
  a <- c(a, "15", "-15", "1", as.character(fx_pow10(38) - 1), "0")
  b <- c(b, "150", "-150", as.character(fx_pow10(37)), "1", "0")
  sa <- c(sample(0:38, n, TRUE), 1L, 1L, 0L, 0L, 3L)
  sb <- c(sample(0:38, n, TRUE), 2L, 2L, 37L, 38L, 0L)
  ours <- integer(length(a))
  for (i in seq_along(a)) {
    ours[i] <- fx_compare(a[i], sa[i], b[i], sb[i])
  }
  qa <- gmp::as.bigq(gmp::as.bigz(a)) / gmp::as.bigq(fx_pow10(sa))
  qb <- gmp::as.bigq(gmp::as.bigz(b)) / gmp::as.bigq(fx_pow10(sb))
  expect_identical(ours, as.integer(sign(qa - qb)))
  expect_identical(fx_compare(NA_character_, 0L, "1", 0L), NA_integer_)
})

test_that("checked arithmetic is exact or an overflow", {
  withr::local_seed(20261129)
  a <- oracle_random("int128", 400L, seed = 5001L)
  b <- oracle_random("int128", 400L, seed = 5002L)
  n <- min(length(a), length(b))
  edge <- oracle_edges("int128")
  a <- c(a[seq_len(n)], edge, sample(edge))
  b <- c(b[seq_len(n)], rev(edge), edge)
  small <- as.character(gmp::as.bigz(a) %/% gmp::as.bigz(2)^64)
  r <- oracle_range("int128")
  for (op in c("+", "-", "*")) {
    rhs <- if (op == "*") small else b
    ours <- fx_arith(op, a, rhs)
    exact <- switch(
      op,
      "+" = gmp::as.bigz(a) + gmp::as.bigz(rhs),
      "-" = gmp::as.bigz(a) - gmp::as.bigz(rhs),
      "*" = gmp::as.bigz(a) * gmp::as.bigz(rhs)
    )
    fits <- exact >= r$min & exact <= r$max
    expect_identical(ours$status == fx_ok, fits, label = op)
    expect_identical(ours$coef[fits], as.character(exact[fits]), label = op)
  }
  # -2^127 is a valid int128 to the C table, but the R payload's NA
  expect_identical(fx_arith("-", as.character(r$min), "1")$status, fx_overflow)
})

test_that("precision and scale are checked at their limits", {
  for (p in c(0L, 39L)) {
    expect_error(fx_parse("1", p, 0L), class = "simpleError")
  }
  for (p in c(1L, 37L, 38L)) {
    expect_identical(fx_parse("0", p, p)$status, fx_ok)
    expect_error(fx_parse("0", p, p + 1L), class = "simpleError")
    expect_error(fx_parse("0", p, -1L), class = "simpleError")
    # 10^(p-s) - 1 fits, 10^(p-s) does not, for s = p - 1
    expect_identical(
      fx_parse("9.9", p, p - 1L)$status,
      if (p == 1L) fx_overflow else fx_ok
    )
    expect_identical(fx_parse("10", p, p - 1L)$status, fx_overflow)
  }
  top <- as.character(fx_pow10(38) - 1)
  expect_identical(fx_parse(top, 38L, 0L)$coef, top)
  expect_identical(fx_parse(paste0(top, "0"), 38L, 0L)$status, fx_overflow)
  expect_identical(fx_parse(paste0("-", top), 38L, 0L)$coef, paste0("-", top))
  # the halfway point just below and at 10^38 at scale 0
  expect_identical(fx_parse(paste0(top, ".4"), 38L, 0L)$coef, top)
  expect_identical(fx_parse(paste0(top, ".5"), 38L, 0L)$status, fx_overflow)
  expect_error(fx_rescale("1", 39L, 38L, 0L), class = "simpleError")
  expect_error(fx_to_double("1", 38L, 39L), class = "simpleError")
  expect_error(fx_from_double(1, 38L, 39L), class = "simpleError")
})

test_that("the C table resolves through zuint-r.h", {
  api <- .Call(zu_api_c)
  expect_identical(api[[1L]], 1L)
  ptr <- .Machine$sizeof.pointer
  expect_identical(api[[2L]], 8L + .Call(zu_api_sizes_c))
  # every member is set, and the list here names every member there is
  expect_true(all(api[[3L]]))
  expect_identical(length(api[[3L]]) * ptr, .Call(zu_api_sizes_c))
  expect_true(.Call(zu_api_version_c, 1L))
  expect_false(.Call(zu_api_version_c, 0L))
  expect_false(.Call(zu_api_version_c, 2L))
  for (k in c(0L, -1L, -2L, -3L, -4L, -5L)) {
    expect_true(nzchar(.Call(zu_dec_strerror_c, k)))
  }
  expect_identical(.Call(zu_dec_strerror_c, 7L), NA_character_)
})

test_that("the installed headers say what the table is", {
  inc <- system.file("include", package = "zuint")
  expect_true(file.exists(file.path(inc, "zuint.h")))
  expect_true(file.exists(file.path(inc, "zuint-r.h")))
  header <- readLines(file.path(inc, "zuint.h"))
  line <- grep("define ZUINT_ABI_VERSION", header, value = TRUE)
  expect_identical(as.integer(gsub("\\D", "", line)), .Call(zu_api_c)[[1L]])
  # zuint.h names no R header; zuint-r.h is the one that does
  expect_length(grep("#include <R", header), 0L)
  expect_length(grep("#include <(stddef|stdint)\\.h>", header), 2L)
})

test_that("zuint.h compiles alone, with no R headers on the path", {
  skip_on_cran()
  cc <- tryCatch(
    system2(
      file.path(R.home("bin"), "R"),
      c("CMD", "config", "CC"),
      stdout = TRUE
    ),
    error = function(e) ""
  )
  skip_if(!nzchar(cc[1L]), "no C compiler")
  inc <- system.file("include", package = "zuint")
  src <- withr::local_tempfile(fileext = ".c")
  writeLines(
    c(
      "#include \"zuint.h\"",
      "int probe(const zuint_api_v1 *api) {",
      "  zuint_i128 c = {0, 0};",
      "  return api->dec_fits(c, 1) == ZUINT_OK && sizeof(zuint_api_v1) > 8;",
      "}"
    ),
    src
  )
  # only the installed include directory is on the path
  # system2(), not system(): Windows runs no shell, so "2>&1" would reach
  # the compiler as a file name
  # CC can carry flags ("clang -arch arm64"), and system2() quotes the
  # command, so split them off
  cc <- strsplit(trimws(cc[1L]), "[[:space:]]+")[[1L]]
  out <- suppressWarnings(system2(
    cc[1L],
    c(
      cc[-1L],
      "-std=c99 -Wall -Wextra -Werror -pedantic -fsyntax-only",
      shQuote(paste0("-I", inc)),
      shQuote(src)
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  expect_null(attr(out, "status"), label = paste(out, collapse = "\n"))
})
