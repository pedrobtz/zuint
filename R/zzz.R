# Methods on Suggests packages' generics, registered whenever those packages
# load, before or after zuint.
zu_lazy_methods <- list(
  nanoarrow = "zu_register_nanoarrow",
  arrow = "zu_register_arrow",
  vctrs = "zu_register_vctrs",
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
