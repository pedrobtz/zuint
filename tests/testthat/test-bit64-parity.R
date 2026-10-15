# Every int64 behaviour of this stage, run with bit64 attached and with bit64
# never loaded. A difference means bit64 has a method zuint lacks.
test_that("int64 behaves the same with bit64 attached and absent", {
  parity_code <- '
x <- int64(c(a = "-9223372036854775807", b = "-1", c = "0", d = "9007199254740993", e = NA))
y <- x
y[7] <- 5L
y[["b"]] <- "12"
z <- x
length(z) <- 6
is.na(z) <- 1
list(
  chr = as.character(x),
  storage = zu_storage(x),
  subset = zu_storage(x[c(2, 9, NA)]),
  sub2 = zu_storage(x[[4]]),
  assign = zu_storage(y),
  len = zu_storage(z),
  c = zu_storage(c(x, 1L, "2", NA)),
  rep = zu_storage(rep(x, 2)),
  rev = zu_storage(rev(x)),
  is_na = is.na(x),
  any_na = anyNA(x),
  dbl = suppressWarnings(as.double(x)),
  int = suppressWarnings(as.integer(x)),
  lgl = as.logical(x),
  list = lapply(as.list(x), zu_storage),
  format = format(x),
  print = capture.output(print(x)),
  str = capture.output(str(x)),
  summary = summary(x),
  df = capture.output(print(data.frame(v = x))),
  cast = zu_storage(int64(c(1.5, 2, NA))),
  uint = zu_storage(uint64(x)),
  wide = zu_storage(int128(x))
)
'
  res <- bit64_states(parity_code)
  expect_identical(res$attached, res$absent)
  # and the attached run is not vacuous
  expect_true(length(res$attached$value) > 10)
  expect_true("zuint_cast_warning" %in% res$attached$warnings)
})

test_that("int64 and bit64 integer64 mix in c() and [<-", {
  skip_if_not_installed("bit64")
  x <- c(int64(1), bit64::as.integer64("9007199254740993"))
  expect_identical(class(x), class(int64()))
  expect_identical(as.character(x), c("1", "9007199254740993"))
  x[1] <- bit64::as.integer64(-7)
  expect_identical(as.character(x), c("-7", "9007199254740993"))
})
