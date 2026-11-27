source("pre.R")
con <- duck()
set.seed(7)
alpha <- c(as.character(0:9), as.character(0:9), ".", ".", "e", "E", "+", "-", "_", " ", "\t", "\n", "x", "a", ",", "'", "N", "A")
rs <- function() paste(sample(alpha, sample(1:12, 1), TRUE), collapse = "")
t1 <- unique(c(replicate(30000, rs()),
  "NA", " NA", "NA ", "na", "N A", "null", "NULL", "NaN", "nan", "inf", "-inf", "Infinity", "", " ", "\t", "\n", "\v", "\f", "\r", " \v1", "1\f", " 1", "1 ", " 1", "１２", "١٢", "1é", "é", "1 .5", "1. 5", "+ 1", "- 1", "+-1", "1e", "1e+", "1e-", "e5", ".e5", "1.e5", "1._5", "1_.5", "_1", "1_", "1__0", "1_0", "1e1_0", "1e_1", "0x1", "0b1", "1L", "1f", "1d", "TRUE", "true", "1e400", "1e-400", "1e2147483648", "1e-2147483648", "1e99999999999999999999", "0e99999999999999999999", "0.0e-99999999999999999", "00000000000000000000000000000000000000000000001", "0.00000000000000000000000000000000000000000000000000001", "1" , strrep("9", 38), strrep("9", 39), strrep("9", 40), strrep("9", 41), strrep("9", 42), paste0("0.", strrep("9", 39)), paste0("0.", strrep("9", 40)), paste0("0.", strrep("9", 41)), paste0(strrep("9", 37), ".5"), paste0(strrep("9", 38), ".4"), paste0(strrep("9", 38), ".5"), paste0("-", strrep("9", 38), ".5"), paste0(strrep("1", 39), "e-1"), paste0(strrep("1", 45), "e-10"), "1e37", "1e38", "9.9e37", "-1e37", "1e-38", "1e-39", "5e-39", "4.9e-39", "0.5", "1.5", "2.5", "-0.5", "0.05", "0.005", "0.0049999999999999999999999999999999999999999999", "0.00500000000000000000000000000000000000000000001", "++1", "1+", "1-", "1.2.3", "..1", "1..", " 1 2", "1\n", "\n1", "1\r\n", "1;", "(1)", "$1", "1%", "1 e5", "1e 5", "1E5", "1e05", "1e+05", "1e-05", "1e0", "1e00000000000000000000001", "-0", "+0", "-0.0", "-.0", "-0e5", ".5e1", "5.e1", "5.e-1", "-_1", "1_e5"))
duckdb::duckdb_register(con, "tx", data.frame(t = t1, stringsAsFactors = FALSE))
nb <- 0
for (ps in list(c(5,2), c(38,0), c(38,38), c(38,10), c(18,3), c(1,0), c(1,1), c(4,0), c(9,4), c(19,19), c(20,0), c(3,3))) { p <- ps[1]; s <- ps[2]
  d <- DBI::dbGetQuery(con, sprintf("SELECT TRY_CAST(t AS DECIMAL(%d,%d))::VARCHAR FROM tx", p, s))[[1]]
  z <- suppressWarnings(as.character(decimal128(t1, p, s)))
  diff <- which(!(is.na(d) & is.na(z)) & !(d == z) %in% TRUE)
  cat(p, s, "ndiff", length(diff), "\n")
  if (length(diff)) { h <- head(diff, 25); print(data.frame(t = encodeString(t1[h], quote = '"'), duck = d[h], zu = z[h])) ; nb <- nb + length(diff)}
}
cat("non-NA", sum(!is.na(z)), "of", length(z), "\n")
P(decimal128(c("1.234e4", "0.0000000001234e10"), 5, 2)); print(DBI::dbGetQuery(con, "SELECT TRY_CAST('0.0000000001234e10' AS DECIMAL(5,2))::VARCHAR, TRY_CAST('1.234e4' AS DECIMAL(4,0))::VARCHAR"))
P(decimal128("1.234e4", 4, 0))
# encodings
l1 <- iconv("1 2", "UTF-8", "latin1"); P(decimal128(c(l1, "1 ", " 1", " 1", "1 "), 5, 2))
b <- "12"; Encoding(b) <- "bytes"; P(decimal128(b, 5, 2))
P(decimal128(c("5", NA, "NA", "  ", "NA\n", " N A "), 5, 2))
P(decimal128(c(NA_character_), 5, 2)); P(decimal128(strrep("0", 100000), 5, 2)); P(decimal128(paste0("0.", strrep("0", 100000), "1e100001"), 5, 2)); P(decimal128(paste0(strrep("1", 39), "e-39"), 38, 38)); P(decimal128(paste0("1", strrep("0", 50), "e-50"), 5, 2))
