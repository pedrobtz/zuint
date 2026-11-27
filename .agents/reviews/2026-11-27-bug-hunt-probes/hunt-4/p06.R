source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)); invisible(DBI::dbExecute(con, "SET arrow_lossless_conversion = true"))
data <- bytes(c("1", "-2"), 16)
J <- function(t) sprintf('{"type_name":"%s","vendor_name":"DuckDB"}', t)
withmd <- function(md, storage = na_fixed_size_binary(16)) nanoarrow_schema_modify(storage, list(metadata = md))
N <- "ARROW:extension:name"; M <- "ARROW:extension:metadata"
cases <- list(
  value_is_key2 = withmd(setNames(list("arrow.opaque", '{"vendor_name":"DuckDB","note":"type_name","type_name":"hugeint"}'), c(N, M))),
  name_only = withmd(setNames(list("arrow.opaque"), N)),
  md_only = withmd(setNames(list(J("hugeint")), M)),
  no_md = withmd(NULL),
  md_first = withmd(setNames(list(J("hugeint"), "arrow.opaque"), c(M, N))),
  extra_keys = withmd(setNames(list("a", "arrow.opaque", "b", J("hugeint"), "c"), c("k1", N, "k2", M, "k3"))),
  rep_md_h_u = withmd(setNames(list("arrow.opaque", J("hugeint"), J("uhugeint")), c(N, M, M))),
  rep_md_u_h = withmd(setNames(list("arrow.opaque", J("uhugeint"), J("hugeint")), c(N, M, M))),
  rep_name = withmd(setNames(list("other.ext", "arrow.opaque", J("hugeint")), c(N, N, M))),
  rep_name2 = withmd(setNames(list("arrow.opaque", "other.ext", J("hugeint")), c(N, N, M))),
  name_prefix = withmd(setNames(list("arrow.opaque2", J("hugeint")), c(N, M))),
  key_prefix = withmd(setNames(list("zz", "arrow.opaque", J("hugeint")), c("ARROW:extension:nam", N, M))),
  key_longer = withmd(setNames(list("zz", "arrow.opaque", J("hugeint")), c("ARROW:extension:name2", N, M))),
  other_ext = withmd(setNames(list("arrow.uuid", ""), c(N, M)))
)
for (nm in names(cases)) {
  cat(sprintf("%-14s", nm)); s <- cases[[nm]]
  r <- tryCatch(zuarrow::arrow_to_r(mk(s, data, 2)), error = function(e) e)
  if (inherits(r, "error")) cat(" zuint: ERR", class(r)[1], substr(conditionMessage(r), 1, 90)) else cat(" zuint:", class(r)[1], if (is.list(r)) "" else paste(format(r), collapse = ","))
  d <- tryCatch({ r <- duck_view(con, to_arrow_tbl(struct1(s, mk(s, data, 2), 2))); paste(r$t_x[1], substr(paste(r$v_x, collapse = ","), 1, 12)) }, error = function(e) paste("ERR", substr(conditionMessage(e), 1, 100)))
  cat(" | duckdb:", d, "\n")
}
cat("-- storage other than w:16 with hugeint ext\n")
for (st in list(l = list(na_int64(), bytes(c("1","-2"), 8)), L = list(na_uint64(), bytes(c("1","5"), 8)), w8 = list(na_fixed_size_binary(8), bytes(c("1","-2"), 8)), w32 = list(na_fixed_size_binary(32), bytes(c("1","-2"), 32)),
                d = list(na_decimal128(38, 0), data), i = list(na_int32(), bytes(c("1","-2"), 4)))) for (tn in c("hugeint", "uhugeint", "uuid")) {
  s <- opaque(tn, storage = st[[1]])
  cat(s$format, tn, ":"); for (to in list(NULL, int128(), int64())) { r <- try_(zuarrow::arrow_to_r(mk(s, st[[2]], 2), to = to)); if (!is.null(r)) cat("  to", class(to)[1], "->", class(r)[1], if (!is.list(r)) format(r), "\n") }
}
