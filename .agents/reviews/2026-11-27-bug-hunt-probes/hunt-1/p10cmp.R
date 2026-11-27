a <- readRDS("o_base.rds")
for (f in c("o_h1.rds","o_h2.rds","o_c.rds","o_de.rds","o_no.rds")) { b <- readRDS(f); d <- names(a)[!mapply(identical, a, b[names(a)])]; cat(f, ":", length(d), "differ\n"); for (n in d) { cat("  --", n, "\n"); print(a[[n]]); print(b[[n]]) } }
