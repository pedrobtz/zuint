source("pre.R")
con <- duck()
t <- c(paste0("0.", strrep("0", 1000), "1e1001"), paste0(strrep("1", 39), "e-39"), paste0("1", strrep("0", 50), "e-50"), "12345e-2", "100e-2", "1e2", "0.001e3", "123.45e0", "1234.5e-1", "12.345e1", "1.2345e2", "0.12345e3","0.0012345e5", "12345.0e-2", "1e-2", "10e-1", "0.5e1", "5e-1", "50e-2", "0.05e1", "99999e-2", "999.99e0", "9.9999e2", "1000e-1")
duckdb::duckdb_register(con, "tx", data.frame(t = t))
d <- DBI::dbGetQuery(con, "SELECT TRY_CAST(t AS DECIMAL(5,2))::VARCHAR FROM tx")[[1]]
z <- suppressWarnings(as.character(decimal128(t, 5, 2)))
print(data.frame(t = substr(t, 1, 30), duck = d, zu = z))
