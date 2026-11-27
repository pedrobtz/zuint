source("helper.R")
l <- list(uint128(c("340282366920938463463374607431768211454", NA)), uint128("7"))
print(zuarrow:::zar_flatten(l))
ns <- asNamespace("zuarrow")
for (n in ls(ns)) { f <- get(n, ns); if (is.function(f)) { d <- deparse(f); if (any(grepl("zar_flatten(", d, fixed = TRUE)) && n != "zar_flatten") { cat("==", n, "\n"); cat(d, sep = "\n") } } }
