source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
nar <- "9218868437227407266"                       # bits of NA_real_
nac <- as.character(gmp::as.bigz(nar) * gmp::as.bigz(2)^64 + gmp::as.bigz(nar))  # both words NA_real_
nan <- "9221120237041090560"
edge <- list(
  int64 = c("0","1","-1","-2","9223372036854775807","-9223372036854775807", nar, nan, "9007199254740993", NA),
  uint64 = c("0","1","18446744073709551614","9223372036854775808", nar, nan, "9223372036854775807", NA),
  int128 = c("0","1","-1","-2","170141183460469231731687303715884105727","-170141183460469231731687303715884105727", nac, "18446744073709551616","-18446744073709551616", "9223372036854775808", NA),
  uint128 = c("0","1","340282366920938463463374607431768211454","170141183460469231731687303715884105728", nac, "18446744073709551615", NA))
ctor <- list(int64 = int64, uint64 = uint64, int128 = int128, uint128 = uint128)
fmt <- c(int64 = "l", uint64 = "L", int128 = "w:16", uint128 = "w:16"); dt <- c(int64 = "BIGINT", uint64 = "UBIGINT", int128 = "HUGEINT", uint128 = "UHUGEINT")
bad <- 0; ok <- 0
ck <- function(cond, ...) if (isTRUE(cond)) ok <<- ok + 1 else { bad <<- bad + 1; cat("FAIL:", ..., "\n") }
for (tn in names(edge)) for (n in c(0, 1, 7, 8, 9, 63, 64, 65, 130)) for (nas in c("mixed", "none", "all")) {
  v <- rep_len(edge[[tn]], n)
  if (nas == "none") v <- rep_len(setdiff(edge[[tn]], NA), n)
  if (nas == "all") v <- rep(NA_character_, n)
  x <- ctor[[tn]](v)
  L <- paste(tn, n, nas)
  ck(identical(as.character(x), as.character(v)), L, "ctor")
  a <- zuarrow::arrow_array(x)
  na <- as_nanoarrow_array(a)
  sc <- infer_nanoarrow_schema(na)
  ck(sc$format == fmt[[tn]], L, "format", sc$format)
  p <- nanoarrow:::nanoarrow_array_proxy_safe(na)
  ck(p$length == n && p$offset == 0 && p$null_count == sum(is.na(v)), L, "len/nc", p$length, p$null_count)
  w <- if (fmt[[tn]] == "w:16") 16 else 8
  db <- as.raw(p$buffers[[2]]); vb <- as.raw(p$buffers[[1]])
  ck(length(db) %in% c(n * w, if (n == 0) 1), L, "data size", length(db))
  if (n > 0) {
    isna <- is.na(v)
    want <- bytes(ifelse(isna, "0", v), w)
    ck(identical(db, want), L, "data bytes")
    if (any(isna)) ck(identical(vb, bitmap(!isna)), L, "bitmap", length(vb)) else ck(length(vb) == 0, L, "no bitmap expected")
  }
  # round trip
  back <- zuarrow::arrow_to_r(a)
  ck(identical(back, x), L, "roundtrip array")
  df <- data.frame(k = seq_len(n)); df$x <- x
  raw <- zuarrow::arrow_write(df, NULL, format = "stream")
  back <- zuarrow::arrow_read(raw)
  ck(identical(back$x, x), L, "roundtrip ipc")
  # arrow + duckdb
  tbl <- arrow::read_ipc_stream(raw, as_data_frame = FALSE)
  r <- duck_view(con, tbl)
  ck(identical(r$v_x, as.character(v)), L, "duckdb values", head(r$v_x), "|", head(v))
  if (n > 0) ck(all(r$t_x == dt[[tn]]), L, "duckdb type", r$t_x[1])
  # duckdb -> R again
  duckdb::duckdb_register_arrow(con, "t2", tbl)
  back <- zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, "SELECT x FROM t2"))
  duckdb::duckdb_unregister_arrow(con, "t2")
  ck(identical(back$x, x) , L, "duckdb roundtrip", class(back$x)[1])
  # parquet
  f <- tempfile(fileext = ".parquet"); arrow::write_parquet(tbl, f)
  raw2 <- arrow::write_to_raw(arrow::read_parquet(f, as_data_frame = FALSE), "stream")
  back <- zuarrow::arrow_read(raw2)
  ck(identical(back$x, x), L, "parquet roundtrip", class(back$x)[1])
}
cat("ok", ok, "bad", bad, "\n")
