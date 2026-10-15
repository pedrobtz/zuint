# bit64 parity (design 12): the same code must give the same results with
# bit64 attached and with bit64 never loaded. S3 methods stay registered once
# a namespace has loaded, so "never loaded" needs a fresh process; each state
# runs in its own Rscript.
#
# `code` is a string of R code. The result is its value (or the class of
# the error it raised) and the classes of the warnings it gave. In a
# development session (load_all) the child loads the same source tree;
# otherwise it loads the installed zuint the parent is testing.
bit64_states <- function(code) {
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
    attached = bit64_child(code, loader, attach = TRUE),
    absent = bit64_child(code, loader, attach = FALSE)
  )
}

bit64_child <- function(code, loader, attach) {
  out <- tempfile(fileext = ".rds")
  script <- tempfile(fileext = ".R")
  on.exit(unlink(c(out, script)))
  writeLines(
    c(
      if (attach) "suppressPackageStartupMessages(library(bit64))",
      loader,
      sprintf("stopifnot(isNamespaceLoaded('bit64') == %s)", attach),
      sprintf("code <- %s", deparse1(code)),
      "warns <- character()",
      "value <- withCallingHandlers(",
      "  tryCatch(eval(parse(text = code)), error = function(e) class(e)),",
      "  warning = function(w) {",
      "    warns <<- c(warns, class(w)[[1L]])",
      "    invokeRestart('muffleWarning')",
      "  }",
      ")",
      sprintf(
        "saveRDS(list(value = value, warnings = warns), %s)",
        deparse(out)
      )
    ),
    script
  )
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", shQuote(script)),
    env = sprintf(
      "R_LIBS=%s",
      paste(.libPaths(), collapse = .Platform$path.sep)
    ),
    stdout = FALSE,
    stderr = FALSE
  )
  if (status != 0L || !file.exists(out)) {
    stop("bit64 parity child failed with status ", status)
  }
  readRDS(out)
}
