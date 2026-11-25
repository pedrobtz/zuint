# The workload for .github/workflows/alloc-failure.yaml: r-actions'
# alloc-failure.yml runs it once per allocation, failing a different one
# each time. It runs the C paths that allocate native memory or hold it
# across an R allocation: the Arrow export (malloc'd structs, buffers and
# metadata owned by finalized external pointers) and its import, then text,
# sorting, hashing and reductions. Keep it short; the sweep multiplies it.
#
# Run from anywhere, with zuint installed. Every error goes to the handler
# below, which prints the condition's class and message before R stops.
# The workflow's patterns read that line: an injected failure must end in
# zuint's "out of memory" error or R's own allocation error. A failed
# stopifnot() is a wrong result after an absorbed failure, and the sweep
# reports it.

suppressPackageStartupMessages(library(zuint))

withCallingHandlers(
  {
    from <- zuint:::zu_arrow_from
    to <- zuint:::zu_arrow_to(NA_integer_)
    tag <- zuint:::zu_arrow_tag

    # The Arrow export and import, every type, nulls included.
    for (x in list(
      int64(c(1, NA, -3)),
      uint64(c("18446744073709551614", NA)),
      int128(c("-170141183460469231731687303715884105727", NA, "0")),
      uint128(c("340282366920938463463374607431768211454", NA))
    )) {
      a <- from(x)
      stopifnot(identical(to(a, tag(a), "error"), x))
    }
    rm(a)
    invisible(gc())

    # Text in and out, sorting, hashing and reductions.
    y <- int128(c("0x7f", "-0b101", "1_000", NA, "42", "42"))
    stopifnot(
      identical(format_hex(y)[1], "0x7f"),
      identical(as.character(sort(y)), c("-5", "42", "42", "127", "1000")),
      length(unique(y)) == 5L,
      identical(as.character(sum(y, na.rm = TRUE)), "1206"),
      identical(as.character(cumsum(uint64(1:3))), c("1", "3", "6"))
    )
  },
  error = function(e) {
    cat(
      "alloc-exercise: ",
      paste(class(e), collapse = "/"),
      ": ",
      conditionMessage(e),
      "\n",
      sep = "",
      file = stderr()
    )
  }
)
