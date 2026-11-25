# Methods on Suggests packages' generics, registered whenever those packages
# load, before or after zuint.
zu_lazy_methods <- list(
  zuarrow = "zu_register_zuarrow",
  vctrs = "zu_register_vctrs",
  bit64 = "zu_register_bit64",
  pillar = "zu_register_pillar"
)

.onLoad <- function(libname, pkgname) {
  for (pkg in names(zu_lazy_methods)) {
    register <- get(zu_lazy_methods[[pkg]], mode = "function")
    setHook(packageEvent(pkg, "onLoad"), register)
    if (isNamespaceLoaded(pkg)) {
      register()
    }
  }
}
