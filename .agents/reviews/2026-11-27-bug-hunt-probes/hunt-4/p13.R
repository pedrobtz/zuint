source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
cat("== released schema to handler\n")
h <- zuint:::zu_arrow_to(1L)
a <- zuint:::zu_arrow_from(int64(1:3)); s <- zuint:::zu_arrow_tag(a)
s2 <- nanoarrow_allocate_schema(); nanoarrow_pointer_move(s, s2)
print(tryCatch(h(a, s, "error"), error = function(e) paste(class(e)[1], conditionMessage(e))))
cat("== decimal128 class export\n")
d <- decimal128(c("1.50", "-2.25", NA), 10, 2); print(class(d))
r <- try_(zuarrow::arrow_array(d)); if (!is.null(r)) { print(infer_nanoarrow_schema(as_nanoarrow_array(r))$format); print(zuarrow::arrow_to_r(r)) }
df <- data.frame(k = 1:3); df$d <- d
r <- try_(zuarrow::arrow_write(df, NULL, format = "stream")); if (!is.null(r)) { t <- arrow::read_ipc_stream(r, as_data_frame = FALSE); print(t$schema); print(duck_view(con, t, "d")) }
cat("== names\n")
x <- int64(1:3); names(x) <- c("a", "b", "c")
r <- zuarrow::arrow_to_r(zuarrow::arrow_array(x)); print(r)
x <- uint128(c(a = "5", b = NA)); print(names(x)); r <- zuarrow::arrow_to_r(zuarrow::arrow_array(x)); print(r)
df <- data.frame(`weird name` = 1:2, check.names = FALSE); df[["é ü"]] <- int128(c("-1", NA)); df[[""]] <- uint64(c("3", NA))
r <- try_(zuarrow::arrow_read(zuarrow::arrow_write(df, NULL, format = "stream"))); str(r)
cat("== other attributes on the vector (dim, custom attr)\n")
x <- int64(1:4); attr(x, "foo") <- "bar"; r <- zuarrow::arrow_to_r(zuarrow::arrow_array(x)); print(attributes(r))
cat("== integer64 (bit64) plain\n")
x <- bit64::as.integer64(c("1", NA, "9007199254740993")); r <- try_(zuarrow::arrow_to_r(zuarrow::arrow_array(x))); print(class(r)); print(r)
cat("== schema with 4096 / 4097 metadata entries incl. extension\n")
J <- '{"type_name":"hugeint","vendor_name":"DuckDB"}'
for (n in c(4094, 4095)) {
  md <- c(setNames(as.list(rep("v", n)), sprintf("k%d", seq_len(n))), list("ARROW:extension:name" = "arrow.opaque", "ARROW:extension:metadata" = J))
  s <- nanoarrow_schema_modify(na_fixed_size_binary(16), list(metadata = md))
  r <- zuarrow::arrow_to_r(mk(s, bytes(c("1","-2"), 16), 2)); cat(n + 2, "entries ->", class(r)[1], "\n")
  if (n == 4095) { d <- tryCatch(duck_view(con, to_arrow_tbl(struct1(s, mk(s, bytes(c("1","-2"), 16), 2), 2))), error = function(e) conditionMessage(e)); print(d) }
}
