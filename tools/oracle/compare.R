# Compares two recordings of the engines' answers (tools/oracle/record):
# the committed fixture and a fresh one. Every key and every answer must be
# identical; the provenance (dates and versions) may differ.
#
#   Rscript tools/oracle/compare.R tests/testthat/fixtures/engines.rds /tmp/e.rds
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
old <- readRDS(args[[1L]])
new <- readRDS(args[[2L]])
show <- function(label, p) {
  cat(
    label,
    "",
    p$recorded,
    p$r,
    paste(names(p$packages), p$packages),
    sep = "\n  "
  )
}
show("committed:", attr(old, "provenance"))
show("recorded now:", attr(new, "provenance"))
attr(old, "provenance") <- NULL
attr(new, "provenance") <- NULL
gone <- setdiff(names(old), names(new))
added <- setdiff(names(new), names(old))
both <- intersect(names(old), names(new))
changed <- both[!vapply(both, function(k) identical(old[[k]], new[[k]]), NA)]
cat(sprintf(
  "\n%d answers: %d no longer asked, %d new, %d changed\n",
  length(old),
  length(gone),
  length(added),
  length(changed)
))
for (k in changed) {
  cat("\n--", k, "\n")
  str(list(committed = old[[k]], now = new[[k]]))
}
if (length(gone) || length(added) || length(changed)) {
  quit(save = "no", status = 1L)
}
