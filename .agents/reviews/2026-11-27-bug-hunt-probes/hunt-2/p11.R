source("pre.R")
two <- as.bigz(2); set.seed(7)
rngs <- list(int64 = c(-(two^63 - 1), two^63 - 1), uint64 = c(as.bigz(0), two^64 - 2), int128 = c(-(two^127 - 1), two^127 - 1), uint128 = c(as.bigz(0), two^128 - 2))
# parse differential: random and edge texts in decimal, hex, binary
vals <- c(as.bigz(0), 1, -1, two^31, two^53, two^63 - 2, two^63 - 1, two^63, two^63 + 1, -(two^63 - 1), -two^63, -two^63 - 1, two^64 - 2, two^64 - 1, two^64, two^64 + 1, two^127 - 1, two^127, two^127 + 1, -(two^127 - 1), -two^127, -two^127 - 1, two^128 - 2, two^128 - 1, two^128, two^128 + 1, two^129, two^200, -two^200, as.bigz(10)^19, as.bigz(10)^38, as.bigz(10)^39, as.bigz(10)^20 - 1,
  urand.bigz(300, 64), -urand.bigz(300, 64), urand.bigz(300, 128), -urand.bigz(300, 128), urand.bigz(100, 130))
txt <- function(v, base) { s <- vapply(seq_along(v), function(k) as.character(abs(v[k]), b = base), ""); paste0(ifelse(v < 0, "-", ""), c("2" = "0b", "10" = "", "16" = "0x")[as.character(base)], s) }
for (ty in names(rngs)) { f <- get(ty); lo <- rngs[[ty]][1]; hi <- rngs[[ty]][2]
  e <- as.character(vals); e[vals < lo | vals > hi] <- NA
  for (b in c(2, 10, 16)) { s <- txt(vals, b)
    variants <- list(s, toupper(s), paste0("  ", s, "\t"), sub("^(-?)", "\\1+", s)[0], sub("^(-?)(0[xb])?", "\\1\\200000", s), ifelse(startsWith(s, "-"), s, paste0("+", s)))
    for (vi in seq_along(variants)) { sv <- variants[[vi]]; if (!length(sv)) next
      g <- as.character(suppressWarnings(f(sv)))
      ex <- e; if (vi == 2 && b != 10) { } 
      if (!identical(g, ex)) { k <- which(!(is.na(g) & is.na(ex)) & (is.na(g) != is.na(ex) | g != ex)); cat("MISMATCH parse", ty, "base", b, "variant", vi, "n", length(k), ":", sv[k[1]], "->", g[k[1]], "exp", ex[k[1]], "\n") }
    }
    # underscore separators every 3-4 digits
    su <- gsub("([0-9a-f]{3})(?=[0-9a-f])", "\\1_", s, perl = TRUE); su <- sub("^(-?0)_([xb])", "\\1\\2", su)
    g <- as.character(suppressWarnings(f(su))); if (b == 10 && !identical(g, e)) cat("MISMATCH parse underscore", ty, b, "\n")
  }
  # format roundtrip
  ok <- !is.na(e); z <- f(e[ok]); stopifnot(identical(as.character(z), e[ok]), identical(as.character(f(as.character(z))), e[ok]), identical(as.character(f(format_hex(z))), e[ok]), identical(as.character(f(format_bin(z))), e[ok]), identical(as.character(f(format_hex(z, pad = TRUE))), e[ok]))
  # cast to each other type
  for (ty2 in names(rngs)) { g <- as.character(suppressWarnings(get(ty2)(z))); e2 <- e[ok]; v <- vals[ok]; e2[v < rngs[[ty2]][1] | v > rngs[[ty2]][2]] <- NA; if (!identical(g, e2)) cat("MISMATCH cast", ty, "->", ty2, "\n") }
  # as.double correctly rounded? and as.integer
  d <- suppressWarnings(as.double(z)); v <- vals[ok]
  for (k in seq_along(v)) { m <- d[k]; if (m != 0) { ulp <- 2^(floor(log2(abs(m))) - 52); d0 <- abs(as.bigz(m) - v[k]); if (abs(as.bigq(m - ulp) - v[k]) < d0 || abs(as.bigq(m + ulp) - v[k]) < d0) cat("MISMATCH as.double", ty, as.character(v[k]), "\n") } else if (v[k] != 0) cat("MISMATCH as.double zero\n") }
  # double -> type for exact doubles
  dd <- c(0, 1, -1, 2^31, 2^53, 2^53 + 2, 2^62, 2^63 - 1024, 2^63, 2^63 + 2048, 2^64 - 2048, 2^64, 2^64 + 4096, 2^127 - 2^74, 2^127, 2^128 - 2^75, 2^128, 2^129, -(2^63 - 1024), -2^63, -2^63 - 2048, -(2^127 - 2^74), -2^127, -2^128, 1e300, -1e300, 2^100 + 2^60, 1e22, 1e23)
  bz <- as.bigz(dd); ex <- as.character(bz); ex[bz < lo | bz > hi] <- NA
  g <- as.character(suppressWarnings(f(dd))); if (!identical(g, ex)) { k <- which(!(is.na(g) & is.na(ex)) & (is.na(g) != is.na(ex) | g != ex)); cat("MISMATCH dbl", ty, format(dd[k], digits = 17), g[k], ex[k], "\n") }
  # comparisons with doubles
  zz <- f(e[ok][seq(1, sum(ok), length.out = 60)]); vv <- as.bigz(as.character(zz))
  for (d1 in c(dd, 0.5, -0.5, 2^53 + 0, 1.5, 9.2233720368547758e18, 1.8446744073709552e19)) { g <- zz < d1; ex <- as.bigq(vv) < as.bigq(d1); if (!identical(as.logical(g), as.logical(ex))) cat("MISMATCH cmp-dbl <", ty, d1, "\n"); g <- zz == d1; ex <- as.bigq(vv) == as.bigq(d1); if (!identical(as.logical(g), as.logical(ex))) cat("MISMATCH cmp-dbl ==", ty, d1, "\n"); g <- d1 >= zz; ex <- as.bigq(d1) >= as.bigq(vv); if (!identical(as.logical(g), as.logical(ex))) cat("MISMATCH cmp-dbl >=", ty, d1, "\n") }
}
# strings: encodings and odd whitespace
T(int64(c("１２", "12 ", " 12", "12\n", "\n12", "1\n2", "12\r\n", "\v12", "\f12", "12 3", enc2native("12"), iconv("12", "UTF-8", "latin1"), "é", "12é", "1e2", "1E2", "0x1p3", "0d12", "0o17", "017", "1,000", "1.000", "1 000", "１", "+", "-", "+ 1", "0x+1", "0x-1", "-+1", "0xFFFFFFFFFFFFFFFF", "-0x8000000000000000", "-0x7fffffffffffffff", "0b_1", "NA ", " NA", "NaN", "Inf", "TRUE", "NULL", "nan", "N", "-NA", "0X", "0xG", "-0", "+0", "-0x0", "00", "0_0", "9223372036854775807", "9223372036854775808", "-9223372036854775808", "0x_1", "0b1_0_1", "1_2_3", "_", "1__2")))
l1 <- "12"; Encoding(l1) <- "latin1"; T(int64(l1)); b <- "12"; Encoding(b) <- "bytes"; T(int64(b)); T(int64(strrep("0", 5000))); T(int64(paste0(strrep("0", 5000), "7"))); T(int64(paste0(strrep(" ", 5000), "7"))); T(uint128(paste0("0b", strrep("1", 127), "0"))); T(uint128(paste0("0b", strrep("1", 128)))); T(uint128(paste0("0b", strrep("0", 300), "1"))); T(int128(paste0("-0x8", strrep("0", 31)))); T(int128(paste0("-0x7", strrep("f", 31)))); T(uint64("-0")); T(uint64("-0x0")); T(uint64("-1")); T(uint64(-0.0)); T(uint64(NA_character_)); T(int64(c(a = NA_character_)))
cat("done\n")
