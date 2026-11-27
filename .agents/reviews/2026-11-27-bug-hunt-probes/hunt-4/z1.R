ns <- asNamespace("zuarrow")
for (n in ls(ns)) { f <- get(n, ns); if (is.function(f)) { d <- deparse(f); if (any(grepl("share one class", d, fixed = TRUE))) { cat("==", n, "\n"); cat(d, sep = "\n") } } }
