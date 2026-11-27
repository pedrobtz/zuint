a <- readRDS("p17-without.rds"); b <- readRDS("p17-with.rds")
for (i in seq_along(a)) { x <- a[[i]][[2]]; y <- b[[i]][[2]]; if (is.data.frame(x)) x$i <- NULL; if (is.data.frame(y)) y$i <- NULL
  cat(i, a[[i]][[1]], "identical:", identical(x, y), identical(a[[i]][[3]], b[[i]][[3]]), "\n"); if (!identical(x, y)) { str(x); str(y) } }
