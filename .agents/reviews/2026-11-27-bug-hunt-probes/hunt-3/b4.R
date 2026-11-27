mode <- commandArgs(TRUE)[1]
source("pre.R")
if (mode == "attached") suppressPackageStartupMessages(library(bit64)) else if (mode == "loaded") invisible(loadNamespace("bit64"))
b <- as_integer64(int64(c(-2,-1,0,3,NA)))
show("int64 & integer64", int64(c(1,1,1,1,1)) & b)
show("integer64 & int64", b & int64(c(1,1,1,1,1)))
show("uint128 | integer64", uint128(c(0,0,0,0,0)) | b)
show("integer64 | uint128", b | uint128(c(0,0,0,0,0)))
show("oracle", TRUE & c(-2,-1,0,3,NA)); show("oracle |", FALSE | c(-2,-1,0,3,NA))
show("xor", xor(int64(c(0,0,0,0,0)), b))
show("isTRUE(all.equal(int64, integer64 differing))", all.equal(int64(c(-2,-1,0,3,NA)), b))
if (mode != "never") { registerS3method("is.double", "zu_uint64", function(x) FALSE, envir = asNamespace("bit64"))
  show("fixed? b * u", b * uint64(5)); show("b / u", b / uint64(5)); show("b ^ u", b ^ uint64(5)) }
