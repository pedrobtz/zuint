# bit64 parity (design 12): the same code must give the same results with
# bit64 attached and with bit64 never loaded. S3 methods stay registered once
# a namespace has loaded, so "never loaded" needs a fresh process; each state
# runs in its own Rscript.
#
# `codes` is a named list of strings of R code, all evaluated in one child per
# state, each in a fresh environment: starting the processes is what costs.
# Each result is its value (or the class of the error it raised) and the
# classes of the warnings it gave, keyed by name. In a
# development session (load_all) the child loads the same source tree;
# otherwise it loads the installed zuint the parent is testing.
bit64_states <- function(codes) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("bit64")
  path <- getNamespaceInfo(asNamespace("zuint"), "path")
  # an installed package has its code in a lazy-load database; load_all()
  # points the namespace at the source tree instead
  dev <- !file.exists(file.path(path, "R", "zuint.rdb"))
  loader <- if (dev) {
    sprintf(
      "pkgload::load_all(%s, quiet = TRUE, export_all = FALSE)",
      deparse(path)
    )
  } else {
    sprintf("library(zuint, lib.loc = %s)", deparse(dirname(path)))
  }
  list(
    attached = bit64_child(codes, loader, attach = TRUE),
    absent = bit64_child(codes, loader, attach = FALSE)
  )
}

bit64_child <- function(codes, loader, attach) {
  out <- tempfile(fileext = ".rds")
  script <- tempfile(fileext = ".R")
  on.exit(unlink(c(out, script)))
  writeLines(
    c(
      # the parent's libraries; system2(env =) does not work on Windows
      sprintf(".libPaths(%s)", deparse1(.libPaths())),
      if (attach) "suppressPackageStartupMessages(library(bit64))",
      loader,
      sprintf("stopifnot(isNamespaceLoaded('bit64') == %s)", attach),
      sprintf("codes <- %s", deparse1(codes)),
      "run <- function(code) {",
      "  warns <- character()",
      "  value <- withCallingHandlers(",
      "    tryCatch(",
      "      eval(parse(text = code), envir = new.env(parent = globalenv())),",
      "      error = function(e) class(e)",
      "    ),",
      "    warning = function(w) {",
      "      warns <<- c(warns, class(w)[[1L]])",
      "      invokeRestart('muffleWarning')",
      "    }",
      "  )",
      "  list(value = value, warnings = warns)",
      "}",
      sprintf("saveRDS(lapply(codes, run), %s)", deparse(out))
    ),
    script
  )
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script)),
    stdout = FALSE,
    stderr = FALSE
  )
  if (status != 0L || !file.exists(out)) {
    stop("bit64 parity child failed with status ", status)
  }
  readRDS(out)
}

# The int64 behaviours the parity tests compare, evaluated once per test run
# for all of them: one process pair instead of one per test.
bit64_parity_code <- list(
  vector = '
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
',
  arithmetic = '
x <- int64(c("-9223372036854775807", "-3", "0", "7", "9007199254740993", NA))
y <- int64(c("2", "-2", "5", "0", "3", "1"))
list(
  add = zu_storage(suppressWarnings(x + y)),
  sub = zu_storage(suppressWarnings(x - y)),
  mul = zu_storage(suppressWarnings(x * y)),
  idiv = zu_storage(x %/% y),
  mod = zu_storage(x %% y),
  pow = zu_storage(suppressWarnings(int64(3)^40L)),
  neg = zu_storage(-x),
  abs = zu_storage(abs(x)),
  sign = zu_storage(sign(x)),
  div = x / y,
  cmp = list(x == y, x < y, x >= 1.5, x == 9007199254740992),
  int = zu_storage(x + 1L),
  dbl = zu_storage(x + 2),
  mixed = zu_storage(x + uint64(1)),
  checked = tryCatch(checked_add(x, x), error = function(e) class(e)),
  wrapping = zu_storage(wrapping_mul(x, y)),
  not = !x
)
',
  summaries = '
x <- int64(c("9007199254740993", "-3", NA, "9007199254740992", "-3", "0"))
list(
  sum = zu_storage(sum(x, na.rm = TRUE)),
  prod = zu_storage(prod(int64(c(2, -3)))),
  minmax = lapply(list(min(x, na.rm = TRUE), max(x, na.rm = TRUE), range(x, na.rm = TRUE)), zu_storage),
  mean = mean(x, na.rm = TRUE),
  median = median(x, na.rm = TRUE),
  sort = zu_storage(sort(x)),
  sort_desc = zu_storage(sort(x, decreasing = TRUE, na.last = TRUE)),
  xtfrm = xtfrm(x),
  unique = zu_storage(unique(x)),
  duplicated = duplicated(x),
  any_dup = anyDuplicated(x),
  cumsum = zu_storage(cumsum(int64(1:4))),
  cummax = zu_storage(cummax(int64(c(3, 1, 5)))),
  diff = zu_storage(diff(int64(c(1, 4, 9)))),
  summary = summary(x)
)
',
  predicates = '
x <- int64(c("-1", NA, "5", "9007199254740993"))
list(
  is_nan = is.nan(x), is_finite = is.finite(x), is_infinite = is.infinite(x),
  is_numeric = is.numeric(x), complex = suppressWarnings(as.complex(x[1:3])),
  raw = suppressWarnings(as.raw(x[c(1, 3)])), seq = zu_storage(seq(int64(1), int64(5))),
  all_equal = all.equal(x, x), date = as.Date(int64(1))
)
',
  decimal = '
x <- decimal128(c(a = "-12.34", b = "0.05", c = NA, d = "9999999.99"), 9, 2)
y <- x
y[6] <- "1.5"
y[["b"]] <- 7L
z <- x
length(z) <- 6
i <- int64(c("9223372036854775807", "-2", "0", "3"))
list(
  chr = as.character(x),
  storage = zu_storage(int128(decimal128(x, 20, 0))),
  subset = as.character(x[c(2, 9, NA)]),
  assign = as.character(y),
  len = as.character(z),
  c = as.character(c(x, 1L, "2.5", NA)),
  c_int64 = as.character(c(i, x)),
  rep = as.character(rep(x, 2)),
  is_na = is.na(x),
  dbl = as.double(x),
  int = suppressWarnings(as.integer(x)),
  to_int64 = zu_storage(suppressWarnings(int64(x))),
  add = as.character(suppressWarnings(x + i)),
  add_left = as.character(suppressWarnings(i + x)),
  mul = as.character(x * 3L),
  cmp = list(x < i, i == x, x > 0L),
  div = x / i,
  sum = as.character(sum(x, na.rm = TRUE)),
  minmax = as.character(c(min(x, na.rm = TRUE), max(i, x, na.rm = TRUE))),
  mean = mean(x, na.rm = TRUE),
  sort = as.character(sort(x)),
  unique = as.character(unique(c(x, x))),
  match = match(x, rev(x)),
  format = format(x),
  print = capture.output(print(x)),
  str = capture.output(str(x)),
  summary = summary(x),
  df = capture.output(print(data.frame(v = x))),
  predicates = list(is.numeric(x), is.nan(x), is.finite(x)),
  all_equal = all.equal(x, x)
)
',
  # a plain integer64 as an operand of zuint code (#150): with bit64 absent,
  # base is.na(), as.logical() and == read its bits, where -1 is NaN and NA
  # (-0.0) is a value
  operands = '
B <- function(...) as_integer64(int64(c(...)))
d <- decimal128(c("0.00", "-1.00", "2.50"), 10, 2)
list(
  and = int64(c(1, 1, 1)) & B(-1, 0, NA),
  or = int64(c(0, 0, 0)) | B(-1, 0, NA),
  xor = xor(int64(c(1, 1, 1)), B(-1, 0, NA)),
  match = zu_match(int64(c(NA, -1, 7)), B(-1, NA)),
  match_table = zu_match(B(-1, NA, 5), int64(c(5, NA, -1))),
  zin = int64(c(NA, 3, -1)) %zin% B(NA, 5),
  ifelse = zu_storage(zu_ifelse(B(1, 0, NA, -1), int64(1), int64(2))),
  idiv = zu_storage(checked_idiv(int64(c(5, 5)), B(NA, -1))),
  seq_by = zu_storage(seq_zu(int64(1), by = B(-1), length.out = 3)),
  seq_len = zu_storage(seq_zu(int64(1), length.out = B(3))),
  round = zu_storage(round(int64(1234), B(-2))),
  dec_cmp = d == B(NA, -1, 3),
  dec_lt = d < B(NA, 0, 3),
  dec_match = zu_match(decimal128(c("-1", NA), 10, 2), B(NA, -1)),
  dec_and = d & B(-1, 0, NA),
  dec_ifelse = as.character(zu_ifelse(B(-1, 0, NA), d[1:3], d[3:1]))
)
',
  operands_vctrs = '
B <- function(...) as_integer64(int64(c(...)))
lossy <- function(expr) {
  tryCatch(expr, vctrs_error_cast_lossy = function(e) "lossy")
}
list(
  int64 = zu_storage(vctrs::vec_cast(B(1, NA, -1), int64())),
  uint64 = lossy(vctrs::vec_cast(B(-1), uint64())),
  uint64_ok = zu_storage(vctrs::vec_cast(B(1, NA), uint64())),
  int128 = zu_storage(vctrs::vec_cast(B(-1, NA), int128())),
  decimal = as.character(vctrs::vec_cast(B(1, NA, -1), decimal128("0", 10, 2))),
  decimal_lossy = lossy(vctrs::vec_cast(B("9223372036854775807"), decimal128("0", 10, 2))),
  combine = zu_storage(vctrs::vec_c(int64(5), B(NA, -1)))
)
'
)

bit64_parity_cache <- new.env()

# One topic's results with bit64 attached and absent.
bit64_parity <- function(name) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("bit64")
  if (is.null(bit64_parity_cache$res)) {
    bit64_parity_cache$res <- bit64_states(bit64_parity_code)
  }
  res <- bit64_parity_cache$res
  list(attached = res$attached[[name]], absent = res$absent[[name]])
}

# The names a parity topic's value must have: those of the list() its code
# ends with. An error anywhere in a topic turns its value into the error's
# class in both processes, which would compare equal (#63), so every topic
# is held to these names as well as to parity.
bit64_parity_names <- function(name) {
  ex <- parse(text = bit64_parity_code[[name]])
  last <- ex[[length(ex)]]
  stopifnot(identical(last[[1L]], as.name("list")))
  names(as.list(last))[-1L]
}

expect_bit64_parity <- function(name) {
  res <- bit64_parity(name)
  testthat::expect_identical(res$attached, res$absent, label = name)
  for (state in c("attached", "absent")) {
    testthat::expect_type(res[[state]]$value, "list")
    testthat::expect_identical(
      names(res[[state]]$value),
      bit64_parity_names(name),
      label = paste(name, state)
    )
  }
  invisible(res)
}
