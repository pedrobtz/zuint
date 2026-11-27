source("helper.R")
J <- function(t) sprintf('{"type_name":"%s","vendor_name":"DuckDB"}', t)
N <- "ARROW:extension:name"; M <- "ARROW:extension:metadata"
s <- nanoarrow_schema_modify(na_fixed_size_binary(16), list(metadata = setNames(list("arrow.opaque", J("uhugeint"), J("hugeint")), c(N, M, M))))
p <- nanoarrow_schema_parse(s); cat("nanoarrow ext name:", p$extension_name, " ext md:", rawToChar(p$extension_metadata), "\n")
f <- tempfile(); write_nanoarrow(struct1(s, mk(s, bytes(c("1","-2"),16), 2), 2), f)
t <- arrow::read_ipc_stream(f, as_data_frame = FALSE); print(t$schema$x$metadata)
print(zuarrow::arrow_to_r(mk(s, bytes(c("1","-2"),16), 2)))
print(zuarrow::arrow_read(f))
