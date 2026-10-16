.onLoad <- function(libname, pkgname) {
  setHook(packageEvent("nanoarrow", "onLoad"), zu_register_nanoarrow)
  if (isNamespaceLoaded("nanoarrow")) {
    zu_register_nanoarrow()
  }
}
