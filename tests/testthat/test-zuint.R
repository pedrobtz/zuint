test_that("the namespace loads and its shared object is registered", {
  expect_true(isNamespaceLoaded("zuint"))
  expect_true("zuint" %in% names(getLoadedDLLs()))
})
