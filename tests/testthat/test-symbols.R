# CRAN's compiled-code check, enforced: no stdio, abort, exit or system RNG
# may be linked into the shared object, even unused (CLAUDE.md).
test_that("the shared object links no forbidden symbols", {
  skip_on_cran()
  skip_on_os("windows")
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
  syms <- sub("^_", "", trimws(sub("^.*\\s", "", out)))
  forbidden <- c(
    "printf",
    "fprintf",
    "vprintf",
    "vfprintf",
    "puts",
    "fputs",
    "putchar",
    "fputc",
    "putc",
    "fwrite",
    "stdout",
    "stderr",
    "abort",
    "exit",
    "_exit",
    "rand",
    "srand",
    "random",
    "srandom",
    "drand48",
    "srand48",
    "lrand48"
  )
  expect_identical(intersect(syms, forbidden), character())
  expect_true(length(syms) > 0)
})
