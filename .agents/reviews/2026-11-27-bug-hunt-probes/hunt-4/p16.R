source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
cols <- c(ts = "TIMESTAMP '2024-01-02 03:04:05.123456'", d = "DATE '2024-01-02'", dec = "1.5::DECIMAL(10,2)", dec0 = "(-7)::DECIMAL(18,0)", dec4 = "7::DECIMAL(4,0)", dec38 = "12345678901234567890::DECIMAL(38,0)", dbl = "3.7::DOUBLE", flt = "3.7::FLOAT", bb = "'abc'::BLOB", ui = "4000000000::UINTEGER", ti = "(-128)::TINYINT", s = "' 12 '", s2 = "'0x10'", s3 = "'1e3'", s4 = "'12.0'", u = "uuid()", tz = "'10:00:00+02'::TIMETZ")
for (nm in names(cols)) for (p in list(NULL, int64(), uint64(), int128())) {
  q <- sprintf("SELECT %s x", cols[[nm]])
  if (is.null(p)) cat(sprintf(" %-6s fmt %s\n", nm, DBI::dbGetQueryArrow(con, q)$get_schema()$children$x$format))
  cat(sprintf(" %-6s to %-9s:", nm, class(p)[1])); r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, q), to = if (!is.null(p)) list(x = p))$x); if (!is.null(r)) cat("  <", class(r)[1], "> ", substr(paste(format(r), collapse = " "), 1, 60), "\n") }
