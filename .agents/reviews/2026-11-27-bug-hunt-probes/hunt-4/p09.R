source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
q <- "SELECT * FROM (VALUES
 (9223372036854775807::BIGINT, 18446744073709551614::UBIGINT, 170141183460469231731687303715884105727::HUGEINT, 340282366920938463463374607431768211454::UHUGEINT),
 (-9223372036854775807::BIGINT, 0::UBIGINT, -170141183460469231731687303715884105727::HUGEINT, 0::UHUGEINT),
 (NULL, NULL, NULL, NULL),
 (-1, 9223372036854775808::UBIGINT, -1::HUGEINT, 170141183460469231731687303715884105728::UHUGEINT)) t(b, ub, h, uh)"
txt <- DBI::dbGetQuery(con, paste("SELECT b::VARCHAR b, ub::VARCHAR ub, h::VARCHAR h, uh::VARCHAR uh FROM (", q, ")"))
for (lossless in c("true", "false")) {
  DBI::dbExecute(con, paste("SET arrow_lossless_conversion =", lossless))
  cat("== lossless", lossless, "\n")
  r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, q)))
  if (!is.null(r)) { print(sapply(r, function(c) class(c)[1])); print(sapply(names(r), function(n) identical(as.character(r[[n]]), txt[[n]]))) }
  st <- DBI::dbGetQueryArrow(con, q); print(sapply(st$get_schema()$children, function(c) c$format))
  r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, q), to = data.frame(b = int64(), ub = uint64(), h = int128(), uh = uint128())))
  if (!is.null(r)) { print(sapply(r, function(c) class(c)[1])); print(sapply(names(r), function(n) identical(as.character(r[[n]]), txt[[n]]))); print(r$uh) }
  r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, q), to = int128()))
  if (!is.null(r)) { print(sapply(r, function(c) class(c)[1]))}
}
# DuckDB -> R -> DuckDB
DBI::dbExecute(con, "SET arrow_lossless_conversion = true")
r <- zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, q))
tbl <- arrow::read_ipc_stream(zuarrow::arrow_write(r, NULL, format = "stream"), as_data_frame = FALSE)
print(duck_view(con, tbl, c("b","ub","h","uh")))
# sentinels from duckdb
qs <- "SELECT (-9223372036854775807-1)::BIGINT b, 18446744073709551615::UBIGINT ub, (-170141183460469231731687303715884105727-1)::HUGEINT h, 340282366920938463463374607431768211455::UHUGEINT uh"
for (l in c("error","warn","character","allow")) { cat("lossy", l, "\n"); r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, qs), lossy = l)); if (!is.null(r)) print(r) }
# large, multi-batch result
r <- zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, "SELECT (i * 1000000000000000000000::HUGEINT) h, CASE WHEN i % 7 = 0 THEN NULL ELSE i::UBIGINT + 18446744073709000000 END u FROM range(300000) t(i)"))
chk <- DBI::dbGetQuery(con, "SELECT (i * 1000000000000000000000::HUGEINT)::VARCHAR h, (CASE WHEN i % 7 = 0 THEN NULL ELSE i::UBIGINT + 18446744073709000000 END)::VARCHAR u FROM range(300000) t(i)")
cat("multi-batch:", nrow(r), identical(as.character(r$h), chk$h), identical(as.character(r$u), chk$u), "\n")
