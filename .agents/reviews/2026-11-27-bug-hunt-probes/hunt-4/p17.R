args <- commandArgs(TRUE)
if (args[1] == "with") source("helper.R") else loadNamespace("zuarrow")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
q <- "SELECT '10:00:00+02'::TIMETZ tz, '101'::BIT bt, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID u, 123456789012345678901234567890::VARINT vi, i FROM range(3) t(i)"
q2 <- "SELECT CASE WHEN i = 1 THEN NULL ELSE '10:00:00+02'::TIMETZ END tz, i FROM range(3) t(i)"
out <- list()
for (l in c("error", "warn", "character", "allow")) for (qq in c(q, q2)) {
  st <- tryCatch(DBI::dbGetQueryArrow(con, qq), error = function(e) NULL)
  if (is.null(st)) { cat("query failed\n"); next }
  w <- character()
  r <- tryCatch(withCallingHandlers(zuarrow::arrow_to_r(st, lossy = l), warning = function(c) { w <<- c(w, paste(class(c)[1], conditionMessage(c))); invokeRestart("muffleWarning") }), error = function(e) paste(class(e)[1], conditionMessage(e)))
  out[[length(out) + 1]] <- list(l, r, w)
}
if (args[1] == "with") cat("zuint loaded:", "zuint" %in% loadedNamespaces(), "\n")
saveRDS(out, paste0("p17-", args[1], ".rds"))
if (args[1] == "with") { a <- readRDS("p17-without.rds"); b <- out; for (i in seq_along(a)) { cat(i, a[[i]][[1]], "identical:", identical(a[[i]], b[[i]]), "\n"); if (!identical(a[[i]], b[[i]])) { str(a[[i]]); str(b[[i]]) } } }
