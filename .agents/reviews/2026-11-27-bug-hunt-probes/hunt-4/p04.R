source("helper.R")
set.seed(1)
types <- list(
  l = list(na_int64(), 8, function(v) as.character(v), int64),
  L = list(na_uint64(), 8, function(v) as.character(v + 2^40), uint64),
  h = list(opaque("hugeint"), 16, function(v) as.character(gmp::as.bigz(v) * gmp::as.bigz(2)^70 - 5), int128),
  u = list(opaque("uhugeint"), 16, function(v) as.character(gmp::as.bigz(v) * gmp::as.bigz(2)^100 + 7), uint128),
  d = list(na_decimal128(38,0), 16, function(v) as.character(-gmp::as.bigz(v) * gmp::as.bigz(2)^65), int128))
bad <- 0; n_ok <- 0
chk <- function(label, got, want_chr, cls) {
  g <- as.character(got)
  if (!identical(g, want_chr) || !inherits(got, cls)) { bad <<- bad + 1; cat("MISMATCH", label, "\n got ", head(g, 12), "\n want", head(want_chr, 12), "\n") } else n_ok <<- n_ok + 1
}
for (tn in names(types)) {
  t <- types[[tn]]
  for (n in c(0, 1, 7, 8, 9, 63, 64, 65, 130)) for (off in c(0, 1, 3, 7, 8, 9, 64)) {
    tot <- n + off + 3
    vals <- t[[3]](seq_len(tot))
    data <- bytes(vals, t[[2]])
    nullpos <- intersect(c(0, 7, 8, 63, 64), seq_len(tot) - 1)  # absolute bit positions
    valid <- rep(TRUE, tot); valid[nullpos + 1] <- FALSE
    idx <- off + seq_len(n)
    want_all <- vals[idx]
    want_nulls <- as.character(ifelse(valid[idx], vals[idx], NA_character_))
    to <- if (tn == "d") int128() else NULL
    cls <- class(t[[4]]())[1]
    L <- sprintf("%s n=%d off=%d", tn, n, off)
    # no bitmap
    chk(paste(L, "nobitmap"), zuarrow::arrow_to_r(mk(t[[1]], data, n, offset = off), to = to), want_all, cls)
    # all-valid bitmap, null_count 0 / -1
    chk(paste(L, "allvalid nc0"), zuarrow::arrow_to_r(mk(t[[1]], data, n, valid = bitmap(rep(TRUE, tot)), offset = off, null_count = 0), to = to), want_all, cls)
    chk(paste(L, "allvalid nc-1"), zuarrow::arrow_to_r(mk(t[[1]], data, n, valid = bitmap(rep(TRUE, tot)), offset = off, null_count = -1), to = to), want_all, cls)
    # nulls, null_count -1 / exact / wrong(too big)
    nn <- sum(!valid[idx])
    for (nc in c(-1, nn, nn + 1)) {
      if (nc == 0) next
      r <- tryCatch(zuarrow::arrow_to_r(mk(t[[1]], data, n, valid = bitmap(valid), offset = off, null_count = nc), to = to), error = function(e) e)
      if (inherits(r, "error")) { if (nc != nn + 1) {bad <- bad + 1; cat("ERR", L, "nc", nc, conditionMessage(r), "\n")} else if (n == 1 && off == 0 && tn == "l") cat("note: wrong null_count ->", conditionMessage(r), "\n") }
      else chk(paste(L, "nulls nc", nc), r, want_nulls, cls)
    }
    # null_count missing bitmap but nonzero count
    r <- tryCatch(zuarrow::arrow_to_r(mk(t[[1]], data, n, offset = off, null_count = -1), to = to), error = function(e) e)
    if (inherits(r, "error")) { if (n==1&&off==0) cat("nobitmap nc-1:", tn, conditionMessage(r), "\n") } else chk(paste(L, "nobitmap nc-1"), r, want_all, cls)
  }
}
cat("ok", n_ok, "bad", bad, "\n")
