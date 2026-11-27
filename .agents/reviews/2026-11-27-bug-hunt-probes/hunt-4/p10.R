source("helper.R")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
cat("== default export UHUGEINT with to = uint128()\n")
r <- try_(zuarrow::arrow_to_r(DBI::dbGetQueryArrow(con, "SELECT 340282366920938463463374607431768211454::UHUGEINT uh"), to = list(uh = uint128()))); print(r); print(class(r$uh))
cat("== dictionary\n")
dict <- function(idx_schema, w, dict_schema, dict_arr, idx) {
  s <- nanoarrow_schema_modify(idx_schema, list(dictionary = dict_schema))
  a <- nanoarrow_array_modify(nanoarrow_array_init(s), list(length = length(idx), null_count = 0, buffers = list(NULL, bytes(idx, w)), dictionary = dict_arr), validate = FALSE)
  a
}
dl <- function() dict(na_int64(), 8, na_string(), as_nanoarrow_array(c("a","b","c")), c("0","2","1"))
for (to in list(NULL, int64(), uint64(), int128())) { cat(" l-index/string dict, to", class(to)[1], ": "); r <- try_(zuarrow::arrow_to_r(dl(), to = to)); if (!is.null(r)) show(r) }
dL <- function() dict(na_uint64(), 8, na_int64(), mk(na_int64(), bytes(c("100","-200","300"), 8), 3), c("0","2","1"))
for (to in list(NULL, int64(), uint64(), int128())) { cat(" L-index/int64 dict, to", class(to)[1], ": "); r <- try_(zuarrow::arrow_to_r(dL(), to = to)); if (!is.null(r)) show(r) }
di <- function() dict(na_int32(), 4, opaque("uhugeint"), mk(opaque("uhugeint"), bytes(c("100","340282366920938463463374607431768211454"), 16), 2), c("0","1","1"))
for (to in list(NULL, int64(), uint128())) { cat(" i-index/uhugeint dict, to", class(to)[1], ": "); r <- try_(zuarrow::arrow_to_r(di(), to = to)); if (!is.null(r)) show(r) }
cat("== nested\n")
lst <- function() as_nanoarrow_array(list(1:2, 3L), schema = na_list(na_int64()))
r <- try_(zuarrow::arrow_to_r(lst())); str(r)
r <- try_(zuarrow::arrow_to_r(lst(), to = int64())); str(r)
sa <- function() struct1(na_int64(), mk(na_int64(), bytes(c("5","6"), 8), 2), 2)
r <- try_(zuarrow::arrow_to_r(sa(), to = int64())); str(r)
r <- try_(zuarrow::arrow_to_r(sa(), to = list(x = uint64()))); str(r)
# list of hugeint
lh <- function() { s <- na_list(opaque("uhugeint")); a <- nanoarrow_array_init(s)
  nanoarrow_array_modify(a, list(length = 2, null_count = 0, buffers = list(NULL, as.raw(c(0,0,0,0, 1,0,0,0, 3,0,0,0))), children = list(mk(opaque("uhugeint"), bytes(c("1","340282366920938463463374607431768211454","7"), 16), 3))), validate = FALSE) }
r <- try_(zuarrow::arrow_to_r(lh())); str(r); if (!is.null(r)) print(r[[2]])
# direct C call with nested/dict schema
cat("== direct handler calls\n")
h <- zuint:::zu_arrow_to(1L)
a <- dl(); r <- try_(h(a, infer_nanoarrow_schema(a), "error")); print(class(r))
a <- sa(); r <- try_(.Call(zuint:::zu_from_arrow_c, a, infer_nanoarrow_schema(a))); print(class(r))
a <- dl(); r <- try_(.Call(zuint:::zu_from_arrow_c, a, infer_nanoarrow_schema(a)));
r <- tryCatch(zuint:::zu_arrow_try(.Call(zuint:::zu_from_arrow_c, a, infer_nanoarrow_schema(a)), NULL), error = function(e) class(e)); print(r)
