source("pre.R")
suppressPackageStartupMessages(library(gmp))
con <- duck()
q <- function(s) tryCatch(DBI::dbGetQuery(con, s)[[1]], error = function(e) paste("ERR", substr(conditionMessage(e),1,60)))
set.seed(2)
rdigits <- function(n) paste0(sample(c("-",""),1), paste(sample(0:9, n, TRUE), collapse=""))
rdec <- function(p, s, n = 6) { # text coefficient
  co <- vapply(seq_len(n), function(i) { k <- sample(c(p, p, sample(p,1)),1); c0 <- sub("^(-?)0+(?=\\d)", "\\1", rdigits(k), perl=TRUE); c0 }, "")
  co }
totext <- function(co, s) { # bigz coefficient -> decimal text
  neg <- co < 0; a <- as.character(abs(co)); 
  if (s > 0) { a <- ifelse(nchar(a) <= s, paste0(strrep("0", pmax(0, s - nchar(a) + 1)), a), a); a <- paste0(substr(a,1,nchar(a)-s), ".", substr(a, nchar(a)-s+1, nchar(a))) }
  paste0(ifelse(neg, "-", ""), a) }
mk <- function(co, p, s) decimal128(totext(as.bigz(co), s), p, s)
coef <- function(d) { z <- as.character(d); z[!is.na(z)] <- sub("^(-?)0+(?=[0-9])", "\\1", gsub(".", "", z[!is.na(z)], fixed=TRUE), perl=TRUE); as.bigz(z) }
nbad <- 0
for (it in 1:400) {
  p1 <- sample(38,1); s1 <- sample(0:p1,1); p2 <- sample(38,1); s2 <- sample(0:p2,1)
  if (it %% 4 == 0) { p1 <- sample(c(1,17,18,19,37,38),1); s1 <- sample(c(0,p1, max(0,p1-1)),1); p2 <- sample(c(1,17,18,19,37,38),1); s2 <- sample(c(0,p2,max(0,p2-1)),1) }
  c1 <- rdec(p1, s1); c2 <- rdec(p2, s2)
  a <- mk(c1, p1, s1); b <- mk(c2, p2, s2)
  if (!identical(as.character(coef(a)), as.character(as.bigz(c1)))) { cat("CONSTRUCT", p1, s1, "\n"); print(c1); print(totext(as.bigz(c1), s1)); print(as.character(a)); stop("x") }
  for (op in c("+","-","*")) {
    r <- tryCatch(suppressWarnings(get(op)(a, b)), error = function(e) e)
    dt <- q(sprintf("SELECT typeof(CAST(1 AS DECIMAL(%d,%d)) %s CAST(1 AS DECIMAL(%d,%d)))", p1,s1,op,p2,s2))
    if (inherits(r, "error")) { if (!grepl("^ERR", dt)) {nbad <- nbad+1; cat("zu error, duck", dt, ":", p1,s1,op,p2,s2, conditionMessage(r), "\n")}; next }
    zt <- sprintf("DECIMAL(%d,%d)", decimal_precision(r), decimal_scale(r))
    if (zt != dt) { nbad <- nbad+1; cat("TYPE", p1,s1,op,p2,s2, zt, dt, "\n") }
    sr <- decimal_scale(r); pr <- decimal_precision(r)
    A <- as.bigz(c1); B <- as.bigz(c2)
    ex <- switch(op, "+" = A*as.bigz(10)^(sr-s1) + B*as.bigz(10)^(sr-s2), "-" = A*as.bigz(10)^(sr-s1) - B*as.bigz(10)^(sr-s2), "*" = A*B)
    fits <- abs(ex) < as.bigz(10)^pr
    if (op != "*") fits <- fits & abs(A*as.bigz(10)^(sr-s1)) < as.bigz(10)^38 & abs(B*as.bigz(10)^(sr-s2)) < as.bigz(10)^38
    got <- coef(r)
    ok <- ifelse(fits, !is.na(got) & got == ex, is.na(got))
    if (!all(ok)) { nbad <- nbad + 1; i <- which(!ok)[1]; cat("VALUE", p1,s1,op,p2,s2, "a", as.character(a)[i], "b", as.character(b)[i], "got", as.character(r)[i], "want coef", as.character(ex[i]), "fits", fits[i], "\n") }
  }
}
cat("nbad", nbad, "\n")
