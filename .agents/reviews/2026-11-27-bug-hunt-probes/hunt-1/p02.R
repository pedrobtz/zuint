source("pre.R")
con <- duck()
q <- function(s) DBI::dbGetQuery(con, s)[[1]]
print(q("SELECT 0.5::DECIMAL(1,1)::VARCHAR")); print(q("SELECT (-0.5)::DECIMAL(1,1)::VARCHAR")); print(q("SELECT (-0.5)::DECIMAL(3,2)::VARCHAR"))
# double -> decimal differential
set.seed(1)
gen <- function(n) { m <- runif(n, -1, 1); e <- sample(-40:39, n, TRUE); m * 10^e }
v <- c(gen(20000), 9.999999999999999e37, 1e37, 0.95, 2.675, 1.005, 0.5, 1.5, 2.5, -0.5, 0.05, 0.15, 0.25, 0.35, 1e22, 1e23, 123456789012345678, 2^62, 2^63, 2^64, 2^100, 2^126, 2^127, -2^127, 5e-39, 4.9e-39, 0.045, 1.45, 8.345, 1.115, 1.125,1.135,
  (1:2000) / 1000 + 0.0005, (1:2000)/100 + 0.005, sample(1e6,2000)/1000+0.0005)
df <- data.frame(v = v)
duckdb::duckdb_register(con, "t", df)
bad <- 0
for (ps in list(c(38,0), c(38,10), c(38,38), c(38,37), c(18,3), c(18,2), c(9,2), c(4,1), c(1,1), c(1,0), c(19,0), c(20,5), c(38,20), c(30,15), c(5,2), c(10,3))) {
  p <- ps[1]; s <- ps[2]
  d <- q(sprintf("SELECT TRY_CAST(v AS DECIMAL(%d,%d))::VARCHAR FROM t", p, s))
  z <- suppressWarnings(as.character(decimal128(v, p, s)))
  z2 <- sub("^(-?)\\.", "\\10.", z)
  diff <- which(!(is.na(d) & is.na(z2)) & !(d == z2) %in% TRUE)
  cat(p, s, "ndiff", length(diff), "\n")
  if (length(diff)) { h <- head(diff, 8); print(data.frame(v = sprintf("%.17g", v[h]), duck = d[h], zu = z[h])) }
}
