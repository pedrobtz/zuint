source("helper.R")
cat(ls(asNamespace("zuarrow"))[1:60], "\n"); cat(getNamespaceExports("zuarrow"), "\n")
protos <- list(int64 = int64(), uint64 = uint64(), int128 = int128(), uint128 = uint128())
fm <- list(c = list(na_int8(), 1, c("-128","-1","0","127")), C = list(na_uint8(), 1, c("0","255","128")),
  s = list(na_int16(), 2, c("-32768","-1","32767")), S = list(na_uint16(), 2, c("0","65535")),
  i = list(na_int32(), 4, c("-2147483648","-1","2147483647")), I = list(na_uint32(), 4, c("0","4294967295","2147483648")),
  l = list(na_int64(), 8, c("-9223372036854775807","-1","9223372036854775807","9007199254740993")),
  L = list(na_uint64(), 8, c("0","18446744073709551614","9223372036854775808","9007199254740993")))
for (f in names(fm)) {
  s <- fm[[f]]
  cat("== format", f, "values", s[[3]], "\n")
  cat(" default:"); show(try_(zuarrow::arrow_to_r(mk(s[[1]], bytes(s[[3]], s[[2]]), length(s[[3]])))))
  for (p in names(protos)) { cat(" to", p, ":"); r <- try_(zuarrow::arrow_to_r(mk(s[[1]], bytes(s[[3]], s[[2]]), length(s[[3]])), to = protos[[p]])); if (!is.null(r)) show(r) }
}
