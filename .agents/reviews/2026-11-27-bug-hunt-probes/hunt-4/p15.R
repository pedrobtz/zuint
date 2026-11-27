source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
cat("== decimal formats\n")
for (f in c("d:38,0", "d:38,0,128", "d:39,0", "d:1,0", "d:0,0", "d:-1,0", "d:38,0,256", "d:38,0,64", "d:9,0,32", "d:38,1", "d:38,-1", "d: 5,0", "d:5, 0", "d:5,0 ", "d:5,0,", "d:5,0,128,1", "d:5", "d:5,", "d:,0", "d:+5,+0", "d:05,00", "d:5,0x", "d:4294967301,0", "d:5,4294967296", "d:5,-0", "l ", "lx", "", "w:16", "w:016"))
  cat(sprintf("%-16s", dQuote(f, FALSE)), format(.Call(zuint:::zu_arrow_format_type_c, f)), "\n")
cat("== temporal etc with to = int64()\n")
q <- "SELECT TIMESTAMP '2024-01-02 03:04:05.123456' ts, DATE '2024-01-02' d, TIME '03:04:05.5' tm, INTERVAL 3 SECOND iv, 1.5::DECIMAL(10,2) dec, 7::DECIMAL(18,0) dec0, 12345678901234567890::DECIMAL(38,0) dec38, 3.7::DOUBLE dbl, 3.7::FLOAT flt, true bl, 'abc'::BLOB bb, 4000000000::UINTEGER ui, (-128)::TINYINT ti"
for (nm in c("ts","d","tm","iv","dec","dec0","dec38","dbl","flt","bl","bb","ui","ti")) for (p in list(int64(), uint64(), int128())) {
  cat(sprintf(" %-6s to %-9s:", nm, class(p)[1])); r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, q), to = setNames(list(p), nm))[[nm]]); if (!is.null(r)) show(r) }
