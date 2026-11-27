source("pre.R")
con <- duck()
q <- function(s) tryCatch(DBI::dbGetQuery(con, s)[[1]], error = function(e) paste("ERR", substr(conditionMessage(e),1,90)))
# rounding differential against DuckDB: types and values
set.seed(3)
vals <- function(p, s, n = 40) {
  k <- p
  co <- vapply(seq_len(n), function(i) { m <- sample(c(k, sample(k, 1)), 1); paste(sample(0:9, m, TRUE), collapse = "") }, "")
  co <- c(co, strrep("9", p), strrep("5", p), paste0(strrep("4", p - 1), "5"), "0", "5", "50", "49", "500", "15", "25", "150", "250")
  co <- co[nchar(co) <= p]
  co <- paste0(strrep("0", pmax(0, s + 1 - nchar(co))), co)
  t <- if (s > 0) paste0(substr(co, 1, nchar(co) - s), ".", substr(co, nchar(co) - s + 1, nchar(co))) else co
  c(t, paste0("-", t))
}
nb <- 0
types <- list(c(5,2), c(38,0), c(38,38), c(38,37), c(38,10), c(18,18), c(18,0), c(1,0), c(1,1), c(4,0), c(10,5), c(19,1), c(20,19), c(37,36), c(3,1), c(2,2))
for (ps in types) { p <- ps[1]; s <- ps[2]
  t <- vals(p, s)
  duckdb::duckdb_register(con, "tt", data.frame(t = t), overwrite = TRUE)
  x <- decimal128(t, p, s)
  stopifnot(!anyNA(x))
  for (f in c("floor", "ceiling", "trunc", paste0("round", c(-40,-39,-38,-37,-20, -5, -3,-2,-1,0,1,2,3,5,10,36,37,38,39)))) {
    if (startsWith(f, "round")) { d <- as.integer(sub("round", "", f)); sqlf <- sprintf("round(t::DECIMAL(%d,%d), %d)", p, s, d); zf <- function(x) round(x, d) }
    else { sqlf <- sprintf("%s(t::DECIMAL(%d,%d))", sub("ceiling","ceil",f), p, s); zf <- get(f) }
    dt <- q(sprintf("SELECT typeof(%s) FROM tt LIMIT 1", sqlf))
    dv <- q(sprintf("SELECT (%s)::VARCHAR FROM tt", sqlf))
    wr <- NULL
    r <- tryCatch(withCallingHandlers(zf(x), warning = function(w) { wr <<- conditionMessage(w); invokeRestart("muffleWarning") }), error = function(e) e)
    if (inherits(r, "error")) { cat("ZU ERROR", p, s, f, conditionMessage(r), "| duck", dt, "\n"); nb <- nb + 1; next }
    zt <- sprintf("DECIMAL(%d,%d)", decimal_precision(r), decimal_scale(r))
    if (zt != dt) { cat("TYPE", p, s, f, "zu", zt, "duck", dt, "\n"); nb <- nb + 1 }
    zv <- as.character(r)
    if (length(dv) == 1 && startsWith(dv, "ERR")) { cat("DUCKERR", p, s, f, dv, " zu NA count", sum(is.na(zv)), "warn", wr, "\n"); next }
    bad <- which(!(zv == dv) %in% TRUE)
    if (length(bad)) { nb <- nb + 1; i <- bad[1]; cat("VALUE", p, s, f, "x", t[i], "zu", zv[i], "duck", dv[i], "n", length(bad), "warn", wr, "\n") }
  }
}
cat("nbad", nb, "\n")
