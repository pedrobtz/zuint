# The fixed-point core (design 2.2) through its internal entry points, and
# its two oracles: gmp for the exact value, and DuckDB 2.0.1's SQL casts
# (replayed, helper-engines.R).

# The status codes of zu_fixed.h.
fx_ok <- 0L
fx_overflow <- -1L
fx_invalid <- -2L

# Coefficients move as int128 payloads; their text is int128's.
fx_coef <- function(payload) as.character(zu_from_storage(payload, "int128"))
fx_payload <- function(coef) zu_storage(int128(coef))

fx_parse <- function(x, p, s) {
  r <- .Call(zu_dec_parse_c, x, as.integer(p), as.integer(s))
  list(coef = fx_coef(r[[1L]]), status = r[[2L]])
}

fx_format <- function(coef, p, s) {
  .Call(zu_dec_format_c, fx_payload(coef), as.integer(p), as.integer(s))
}

fx_rescale <- function(coef, s, p_to, s_to) {
  r <- .Call(
    zu_dec_rescale_c,
    fx_payload(coef),
    as.integer(s),
    as.integer(p_to),
    as.integer(s_to)
  )
  list(coef = fx_coef(r[[1L]]), status = r[[2L]])
}

fx_to_double <- function(coef, p, s) {
  .Call(zu_dec_to_double_c, fx_payload(coef), as.integer(p), as.integer(s))
}

fx_from_double <- function(x, p, s) {
  r <- .Call(zu_dec_from_double_c, as.double(x), as.integer(p), as.integer(s))
  list(coef = fx_coef(r[[1L]]), status = r[[2L]])
}

fx_compare <- function(a, sa, b, sb) {
  .Call(
    zu_dec_compare_c,
    fx_payload(a),
    as.integer(sa),
    fx_payload(b),
    as.integer(sb)
  )
}

fx_arith <- function(op, a, b) {
  code <- match(op, c("+", "-", "*"))
  r <- .Call(zu_dec_arith_c, code, fx_payload(a), fx_payload(b))
  list(coef = fx_coef(r[[1L]]), status = r[[2L]])
}

# ---- gmp: the exact answers -------------------------------------------------

fx_bigz <- function(x) {
  testthat::skip_if_not_installed("gmp")
  gmp::as.bigz(x)
}

fx_pow10 <- function(k) {
  testthat::skip_if_not_installed("gmp")
  gmp::as.bigz(10)^k
}

# Rounds a bigq to an integer, half away from zero.
fx_round_half_away <- function(q) {
  neg <- q < 0
  a <- abs(q) + gmp::as.bigq(1, 2)
  r <- gmp::as.bigz(a) # truncation, which is floor for a positive value
  r[neg] <- -r[neg]
  r
}

# The coefficient at scale s of sign * int.frac * 10^e, rounded half away
# from zero.
fx_exact <- function(neg, int, frac, e, s) {
  testthat::skip_if_not_installed("gmp") # #120
  # gmp reads a leading 0 as octal, so the zeros go first
  digits <- sub("^0+", "", paste0(int, frac))
  digits[!nzchar(digits)] <- "0"
  v <- gmp::as.bigq(gmp::as.bigz(digits)) *
    gmp::as.bigq(fx_pow10(pmax(e - nchar(frac) + s, 0))) /
    gmp::as.bigq(fx_pow10(pmax(-(e - nchar(frac) + s), 0)))
  r <- fx_round_half_away(v)
  r[neg] <- -r[neg]
  r
}

fx_fits <- function(coef, p) abs(fx_bigz(coef)) < fx_pow10(p)

# The text DuckDB writes for a coefficient: the rule of its
# DecimalToString, written out again from the spec.
fx_format_ref <- function(coef, p, s) {
  testthat::skip_if_not_installed("gmp") # #120
  c <- gmp::as.bigz(coef)
  neg <- c < 0
  m <- abs(c)
  if (s == 0L) {
    return(paste0(ifelse(neg, "-", ""), as.character(m)))
  }
  int <- as.character(m %/% fx_pow10(s))
  frac <- as.character(m %% fx_pow10(s))
  frac <- paste0(strrep("0", s - nchar(frac)), frac)
  int[int == "0" & p == s] <- ""
  paste0(ifelse(neg, "-", ""), int, ".", frac)
}

# ---- DuckDB ------------------------------------------------------------------

# DuckDB's DECIMAL text back to a coefficient.
duck_coef <- function(text) {
  out <- rep(NA_character_, length(text))
  ok <- !is.na(text)
  out[ok] <- as.character(int128(sub(".", "", text[ok], fixed = TRUE)))
  out
}

# ---- structured texts ------------------------------------------------------

# n texts with known parts: sign, integer digits, fractional digits and
# exponent, decorated the ways DuckDB's grammar allows, for DECIMAL(p, s).
fx_texts <- function(n, p, s) {
  digits <- function(k) {
    if (k == 0L) {
      return("")
    }
    pick <- sample(4L, 1L)
    d <- switch(
      pick,
      sample(0:9, k, TRUE),
      rep(9L, k), # the top of a range
      c(sample(0:9, k - 1L, TRUE), 5L), # a halfway point
      c(sample(1:9, 1L), rep(0L, k - 1L))
    )
    paste(d, collapse = "")
  }
  rows <- lapply(seq_len(n), function(i) {
    ni <- sample(0:(p - s + 2L), 1L)
    nf <- sample(0:(s + 3L), 1L)
    if (ni == 0L && nf == 0L) {
      ni <- 1L
    }
    int <- paste0(strrep("0", sample(0:2, 1L, prob = c(8, 1, 1))), digits(ni))
    frac <- digits(nf)
    e <- if (runif(1) < 0.25) sample(-6:6, 1L) else NA_integer_
    neg <- runif(1) < 0.4
    plus <- !neg && runif(1) < 0.1
    us <- function(d) {
      # one '_' between two digits, sometimes
      if (nchar(d) >= 2L && runif(1) < 0.1) {
        k <- sample(nchar(d) - 1L, 1L)
        paste0(substr(d, 1L, k), "_", substr(d, k + 1L, nchar(d)))
      } else {
        d
      }
    }
    point <- nzchar(frac) || runif(1) < 0.1
    body <- paste0(us(int), if (point) "." else "", us(frac))
    if (!is.na(e)) {
      body <- paste0(
        body,
        sample(c("e", "E"), 1L),
        if (e >= 0 && runif(1) < 0.3) "+" else "",
        e
      )
    }
    ws <- function() sample(c("", "", "", " ", "\t", "  "), 1L)
    text <- paste0(
      ws(),
      if (neg) {
        "-"
      } else if (plus) {
        "+"
      } else {
        ""
      },
      body,
      ws()
    )
    list(
      text = text,
      neg = neg,
      int = int,
      frac = frac,
      e = if (is.na(e)) 0L else e,
      exp = !is.na(e)
    )
  })
  data.frame(
    text = vapply(rows, `[[`, "", "text"),
    neg = vapply(rows, `[[`, NA, "neg"),
    int = vapply(rows, `[[`, "", "int"),
    frac = vapply(rows, `[[`, "", "frac"),
    e = vapply(rows, `[[`, 0L, "e"),
    exp = vapply(rows, `[[`, NA, "exp"),
    stringsAsFactors = FALSE
  )
}

# The (p, s) pairs every comparison runs over: each storage width's edges,
# and scale 0, p - 1 and p.
fx_types <- function() {
  p <- c(1L, 2L, 4L, 5L, 9L, 10L, 18L, 19L, 30L, 37L, 38L)
  do.call(
    rbind,
    lapply(p, function(pp) {
      data.frame(p = pp, s = unique(c(0L, pp %/% 2L, max(pp - 1L, 0L), pp)))
    })
  )
}

# n random coefficients of DECIMAL(p, s), weighted to the edges: 0, +-1,
# +-(10^p - 1) and the halfway points.
fx_coefs <- function(n, p, seed) {
  testthat::skip_if_not_installed("gmp") # #120
  top <- fx_pow10(p) - 1
  utils::capture.output(
    r <- gmp::urand.bigz(n, ceiling(p * log2(10)) + 1, seed = seed)
  )
  r <- r %% (top + 1)
  neg <- withr::with_seed(seed, sample(c(TRUE, FALSE), n, TRUE))
  r[neg] <- -r[neg]
  # c() dispatches on its first argument, so that one is a bigz
  half <- fx_pow10(p - 1) * 5
  edges <- c(
    gmp::as.bigz(c(0, 1, -1)),
    top,
    -top,
    top - 1,
    -(top - 1),
    half,
    -half
  )
  unique(c(as.character(edges), as.character(r)))
}
