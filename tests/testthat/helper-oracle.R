# gmp as the oracle for values (design 12). Every helper skips the calling
# test when gmp is absent.

zu_all_types <- c("int64", "uint64", "int128", "uint128")

zu_ctor <- function(type) {
  switch(
    type,
    int64 = int64,
    uint64 = uint64,
    int128 = int128,
    uint128 = uint128
  )
}

# The representable range of each type, NA sentinel excluded, as bigz.
oracle_range <- function(type) {
  testthat::skip_if_not_installed("gmp")
  two <- gmp::as.bigz(2)
  switch(
    type,
    int64 = list(min = -(two^63 - 1), max = two^63 - 1),
    uint64 = list(min = gmp::as.bigz(0), max = two^64 - 2),
    int128 = list(min = -(two^127 - 1), max = two^127 - 1),
    uint128 = list(min = gmp::as.bigz(0), max = two^128 - 2)
  )
}

# 0, +-1, +-(2^53 - 1, 2^53, 2^53 + 1), MIN, MIN + 1, MAX - 1 and MAX, as
# far as the type reaches, as decimal strings.
oracle_edges <- function(type) {
  r <- oracle_range(type)
  two <- gmp::as.bigz(2)
  p53 <- c(two^53 - 1, two^53, two^53 + 1)
  v <- c(gmp::as.bigz(0:1), p53, r$min, r$min + 1, r$max - 1, r$max)
  if (r$min < 0) {
    v <- c(v, gmp::as.bigz(-1), -p53)
  }
  v <- v[v >= r$min & v <= r$max]
  unique(as.character(v))
}

# The values just outside the range, as decimal strings.
oracle_outside <- function(type) {
  r <- oracle_range(type)
  as.character(c(r$min - 1, r$max + 1))
}

# n random values across the whole range, as decimal strings.
oracle_random <- function(type, n, seed) {
  r <- oracle_range(type)
  bits <- switch(type, int64 = , uint64 = 64, int128 = , uint128 = 128)
  # urand.bigz() announces its seeding on stdout
  utils::capture.output(v <- gmp::urand.bigz(n, bits, seed = seed))
  if (r$min < 0) {
    v <- v - gmp::as.bigz(2)^(bits - 1)
  }
  v <- v[v >= r$min & v <= r$max]
  as.character(v)
}

oracle_fits <- function(type, values) {
  r <- oracle_range(type)
  v <- gmp::as.bigz(values)
  v >= r$min & v <= r$max
}

# Operand kinds for the arithmetic matrix: R's integer and the four types.
zu_all_kinds <- c("integer", zu_all_types)

oracle_kind_values <- function(kind) {
  if (kind == "integer") {
    return(c("0", "1", "-1", "7", "-7", "2147483647", "-2147483647"))
  }
  edges <- oracle_edges(kind)
  c(edges, oracle_random(kind, 6, seed = nchar(kind)))
}

# A vector of `kind` holding the decimal strings `v`.
oracle_make <- function(kind, v) {
  if (kind == "integer") as.integer(v) else zu_ctor(kind)(v)
}

# The type operands of kinds a and b compute in, or NA when there is none.
oracle_common <- function(a, b) {
  if (a == "integer") {
    return(b)
  }
  if (b == "integer" || a == b) {
    return(a)
  }
  pair <- sort(c(a, b))
  key <- paste(pair, collapse = "+")
  switch(
    key,
    "int64+uint64" = "int128",
    "int128+int64" = "int128",
    "int128+uint64" = "int128",
    "uint128+uint64" = "uint128",
    NA_character_
  )
}

# The exact result of `op` on bigz vectors, R's semantics: %/% floors and
# %% takes the sign of the divisor. Division by zero is NA.
oracle_op <- function(op, a, b) {
  zero <- b == 0 & op %in% c("%/%", "%%")
  b[zero] <- 1
  r <- switch(
    op,
    "+" = a + b,
    "-" = a - b,
    "*" = a * b,
    "%/%" = a %/% b,
    "%%" = a - b * (a %/% b)
  )
  r[zero] <- NA
  r
}

# v modulo 2^width, in the range of `type`; NA where that is the NA pattern.
oracle_wrap <- function(v, type) {
  bits <- switch(type, int64 = , uint64 = 64, int128 = , uint128 = 128)
  m <- gmp::as.bigz(2)^bits
  r <- v %% m
  if (type %in% c("int64", "int128")) {
    hi <- r >= m / 2
    r[hi] <- r[hi] - m
  }
  r[!is.na(r) & !oracle_fits(type, as.character(r))] <- NA
  r
}

oracle_chr <- function(v) {
  out <- as.character(v)
  out[is.na(v)] <- NA_character_
  out
}

zu_width <- function(type) switch(type, int64 = , uint64 = 64L, int128 = , uint128 = 128L)

# Text of a bigz in base 16 or 2, as format_hex() and format_bin() write it.
oracle_base <- function(v, base) {
  prefix <- if (base == 16) "0x" else "0b"
  mag <- as.character(abs(v), b = base)
  out <- paste0(ifelse(v < 0, "-", ""), prefix, mag)
  out[is.na(v)] <- NA_character_
  out
}

# Two's complement bit strings of the full width, and back.
oracle_bits <- function(v, type) {
  w <- zu_width(type)
  m <- gmp::as.bigz(2)^w
  u <- ifelse(v < 0, as.character(v + m), as.character(v))
  b <- as.character(gmp::as.bigz(u), b = 2)
  paste0(strrep("0", w - nchar(b)), b)
}

oracle_from_bits <- function(bits, type) {
  w <- zu_width(type)
  u <- gmp::as.bigz(paste0("0b", bits))
  if (type %in% c("int64", "int128")) {
    hi <- u >= gmp::as.bigz(2)^(w - 1)
    u[hi] <- u[hi] - gmp::as.bigz(2)^w
  }
  u[!oracle_fits(type, as.character(u))] <- NA
  u
}

oracle_bitop <- function(a, b, f) {
  x <- strsplit(a, "")
  y <- strsplit(b, "")
  vapply(seq_along(x), function(i) paste(f(x[[i]], y[[i]]), collapse = ""), character(1))
}
