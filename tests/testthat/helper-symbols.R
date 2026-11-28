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
