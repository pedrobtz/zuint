source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
cat("== struct with null parent from duckdb\n")
r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, "SELECT CASE WHEN i = 1 THEN NULL ELSE {'h': (i - 5)::HUGEINT, 'u': 18446744073709551614::UBIGINT, 'b': 9007199254740993::BIGINT, 'uh': 340282366920938463463374607431768211454::UHUGEINT} END s FROM range(3) t(i)"))); str(r)
if (!is.null(r)) print(r$s)
cat("== list<hugeint> / list<ubigint> from duckdb\n")
for (l in c("error", "character")) { r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, "SELECT [1::HUGEINT, -2::HUGEINT] c, [18446744073709551614::UBIGINT] b"), lossy = l)); str(r) }
cat("== R nested -> arrow -> duckdb\n")
df <- data.frame(k = 1:2); df$s <- data.frame(h = int128(c("-5", NA)), u = uint64(c("18446744073709551614", "1")))
raw <- try_(zuarrow::arrow_write(df, NULL, format = "stream"))
if (!is.null(raw)) { print(duck_view(con, arrow::read_ipc_stream(raw, as_data_frame = FALSE), "s")); str(zuarrow::arrow_read(raw)); cat("identical:", identical(zuarrow::arrow_read(raw), df), "\n") }
df <- data.frame(k = 1:2); df$l <- list(uint128(c("340282366920938463463374607431768211454", NA)), uint128(character()))
raw <- try_(zuarrow::arrow_write(df, NULL, format = "stream"))
if (!is.null(raw)) { print(duck_view(con, arrow::read_ipc_stream(raw, as_data_frame = FALSE), "l")); r <- try_(zuarrow::arrow_read(raw)); str(r) }
df <- data.frame(k = 1:2); df$l <- list(int64(c("9007199254740993", NA)), int64(character()))
raw <- try_(zuarrow::arrow_write(df, NULL, format = "stream"))
if (!is.null(raw)) { print(duck_view(con, arrow::read_ipc_stream(raw, as_data_frame = FALSE), "l")); r <- try_(zuarrow::arrow_read(raw)); str(r) }
cat("== file format + path\n")
df <- data.frame(a = int64(c("-1", NA))); df$b <- uint128(c("340282366920938463463374607431768211454", NA))
for (fm in c("stream", "file")) { f <- tempfile(); r <- try_({zuarrow::arrow_write(df, f, format = fm); zuarrow::arrow_read(f)}); cat(fm, identical(r, df), "\n") }
t <- arrow::read_ipc_file(f, as_data_frame = FALSE); print(duck_view(con, t, c("a", "b")))
