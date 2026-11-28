# CRAN's compiled-code check, enforced: no stdio, abort, exit or system RNG
# may be linked into the shared object, even unused (CLAUDE.md).

# The names `nm -u` prints differ by platform: glibc versions them
# (`printf@GLIBC_2.2.5`), FORTIFY builds link `__printf_chk`, macOS prefixes
# one underscore (`_puts`, `___stderrp`). Strip the version, the underscores
# and a `_chk` suffix, then compare with the forbidden names (#72).
forbidden_symbols <- function(syms) {
  base <- sub("(_chk)?$", "", sub("^_+", "", sub("@.*$", "", syms)))
  forbidden <- paste0(
    "^(printf|fprintf|vprintf|vfprintf|puts|fputs|putchar|fputc|putc|fwrite",
    "|abort|exit|rand|srand|random|srandom|drand48|srand48|lrand48",
    "|std(out|err)p?)$"
  )
  syms[grepl(forbidden, base)]
}

test_that("the forbidden-symbol matcher catches every platform's spelling (#72)", {
  bad <- c(
    "printf@GLIBC_2.2.5",
    "__printf_chk@GLIBC_2.3.4",
    "__fprintf_chk@GLIBC_2.3.4",
    "abort@GLIBC_2.2.5",
    "stderr@GLIBC_2.2.5",
    "___stderrp",
    "___stdoutp",
    "_puts",
    "_exit",
    "_rand"
  )
  good <- c(
    "Rprintf",
    "REprintf",
    "Rf_error",
    "_Rprintf",
    "R_alloc",
    "memcpy@GLIBC_2.14"
  )
  expect_identical(forbidden_symbols(bad), bad)
  expect_identical(forbidden_symbols(good), character())
})

test_that("the shared object links no forbidden symbols", {
  skip_on_cran()
  skip_on_os("windows")
  # covr builds with --coverage, which links gcov's own stdio and exit
  skip_if(identical(Sys.getenv("R_COVR"), "true"), "coverage build")
  nm <- Sys.which("nm")
  skip_if(nm == "", "nm is not available")
  # load_all() loads a temporary copy and may have removed it; the build in
  # src/ or the installed libs/ is the same object
  ext <- .Platform$dynlib.ext
  candidates <- c(
    getLoadedDLLs()[["zuint"]][["path"]],
    file.path(
      getNamespaceInfo(asNamespace("zuint"), "path"),
      "src",
      paste0("zuint", ext)
    ),
    list.files(
      system.file("libs", package = "zuint"),
      paste0("^zuint\\", ext, "$"),
      recursive = TRUE,
      full.names = TRUE
    )
  )
  so <- candidates[file.exists(candidates)][1L]
  skip_if(is.na(so), "the shared object was not found")
  out <- system2(nm, c("-u", shQuote(so)), stdout = TRUE, stderr = FALSE)
  syms <- trimws(sub("^.*\\s", "", out))
  expect_identical(forbidden_symbols(syms), character())
  expect_true(length(syms) > 0)
})
