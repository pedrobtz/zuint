source("pre.R"); library(vctrs)
i64b <- bit64::as.integer64(c("5","-1",NA))
d <- decimal128(c("1.50","-2.25",NA), 10, 2)
L <- list(i64=int64(c(5,-1,NA)),u64=uint64(c(5,7,NA)),i128=int128(c(5,-1,NA)),u128=uint128(c(5,7,NA)), int=c(5L,-1L,NA), dbl=c(5,-1,NA), lgl=c(TRUE,FALSE,NA), chr=c("5","-1",NA), bit64=i64b, dec=d, fct=factor("a"), date=Sys.Date())
ty <- function(x) tryCatch(vec_ptype_full(x), error=function(e) paste("ERR"))
cat("== ptype2 matrix (rows x, cols y); * marks asymmetry vs zu_common_type/c()\n")
for (a in names(L)) for (b in names(L)) {
  if (!(a %in% c("i64","u64","i128","u128","dec") || b %in% c("i64","u64","i128","u128","dec"))) next
  r1 <- tryCatch(ty(vec_ptype2(L[[a]], L[[b]])), error=function(e) "ERR")
  r2 <- tryCatch(ty(vec_ptype2(L[[b]], L[[a]])), error=function(e) "ERR")
  cc <- tryCatch(withCallingHandlers({z <- c(L[[a]], L[[b]]); if (is.object(z)) ty(z) else typeof(z)}, warning=function(w) invokeRestart("muffleWarning")), error=function(e) paste0("ERR"))
  vc <- tryCatch(as.character(vec_c(L[[a]], L[[b]])), error=function(e) paste0("ERR:", class(e)[1]))
  cv <- tryCatch(withCallingHandlers(as.character(c(L[[a]], L[[b]])), warning=function(w) invokeRestart("muffleWarning")), error=function(e) "ERR")
  cat(sprintf("%-6s %-6s ptype2=%-14s rev=%-14s c()=%-14s %s vec_c=[%s] c=[%s]\n", a, b, r1, r2, cc, if (r1!=r2) "ASYM" else "", paste(vc, collapse=","), paste(cv, collapse=",")))
}
