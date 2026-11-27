source("helper.R")
rel <- function() .Call(zuint:::zu_arrow_releases_c)
sch <- na_struct(list(a = na_int64(), b = opaque("uhugeint"), c = na_uint64(), d = na_decimal128(20, 0), e = na_int32(), f = opaque("hugeint")))
batch <- function(cvals = c("1", "2", "3"), n = 3, off = 0) nanoarrow_array_modify(nanoarrow_array_init(sch), list(length = n, null_count = 0, offset = off, children = list(
  a = mk(na_int64(), bytes(c("-1","-2","9007199254740993"), 8), 3, valid = bitmap(c(TRUE, FALSE, TRUE))),
  b = mk(opaque("uhugeint"), bytes(c("340282366920938463463374607431768211454","0","7"), 16), 3),
  c = mk(na_uint64(), bytes(cvals, 8), 3),
  d = mk(na_decimal128(20, 0), bytes(c("-5","6","99999999999999999999"), 16), 3, valid = bitmap(c(TRUE, TRUE, FALSE))),
  e = mk(na_int32(), bytes(c("1","2","3"), 4), 3),
  f = mk(opaque("hugeint"), bytes(c("-170141183460469231731687303715884105727","0","7"), 16), 3, valid = bitmap(c(FALSE, TRUE, TRUE))))), validate = FALSE)
to <- list(d = int128())
cat("== struct good\n"); r <- try_(zuarrow::arrow_to_r(batch(), to = to)); print(r); print(sapply(r, function(c) class(c)[1]))
cat("== struct sliced at parent offset 1 length 2\n"); r <- try_(zuarrow::arrow_to_r(batch(n = 2, off = 1), to = to)); print(r)
cat("== struct, third column has sentinel\n")
badb <- function() batch(c("1", "18446744073709551615", "3"))
for (l in c("error", "warn", "character", "allow")) { cat(" lossy", l, "\n"); r <- try_(zuarrow::arrow_to_r(badb(), to = to, lossy = l)); if (!is.null(r)) print(r$c) }
cat("== stream of 3 batches, 2 with sentinel\n")
st <- function() basic_array_stream(list(batch(), badb(), badb()), schema = sch, validate = FALSE)
for (l in c("error", "warn", "allow")) { cat(" lossy", l, "\n"); s <- st(); r <- try_(zuarrow::arrow_to_r(s, to = to, lossy = l)); if (!is.null(r)) print(format(r$c)); cat("  stream valid after:", tryCatch(nanoarrow_pointer_is_valid(s), error = function(e) conditionMessage(e)), "\n") }
cat("== without to: decimal col fails after a,b,c converted -> nothing returned; releases balanced?\n")
b0 <- rel(); r <- try_(zuarrow::arrow_to_r(batch())); invisible(gc()); cat("delta", rel() - b0, "\n")
cat("== copy = FALSE\n"); r <- try_(zuarrow::arrow_to_r(batch(), to = to, copy = FALSE)); print(sapply(r, function(c) class(c)[1])); b <- batch(); r <- zuarrow::arrow_to_r(b, to = to, copy = FALSE); rm(b); invisible(gc()); print(r)
cat("== to as data.frame prototype with wrong names / partial\n")
r <- try_(zuarrow::arrow_to_r(batch(), to = list(d = int128(), e = uint64(), a = uint64(), zzz = int64()))); if (!is.null(r)) print(r)
