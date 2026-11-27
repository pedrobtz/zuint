# Compares two recordings of the engines' answers (tools/oracle/record):
# the committed fixture and a fresh one. Every key and every answer must be
# identical, an IPC stream in the values it reads as; the provenance (dates
# and versions) may differ.
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
# An IPC stream compares by what it reads as: DuckDB leaves arbitrary bytes
# under a NULL slot, so two exports of one result can differ there.
same <- function(a, b) {
  if (identical(a, b)) {
    return(TRUE)
  }
  is.raw(a) &&
    is.raw(b) &&
    identical(
      zuarrow::arrow_read(a, lossy = "allow"),
      zuarrow::arrow_read(b, lossy = "allow")
    )
}
changed <- both[!vapply(both, function(k) same(old[[k]], new[[k]]), NA)]
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
