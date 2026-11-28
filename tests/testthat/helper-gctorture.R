# gctorture (r-actions' gctorture.yml, `gctorture2(step = 20)`) forces a
# collection every few allocations, so a test's cost there is its
# allocations times the live heap, not its work. A vector of a million
# strings is marked on every collection. The full suite took 5h28m of a
# 330-minute limit, so a test that only needs a large input for its size, not
# for what it checks, takes its small size here and its full size on every
# other leg (CLAUDE.md, Testing).

# Is this process running under gctorture? gctorture2() returns the step it
# replaces, so set it off and put it back. ZUINT_GCTORTURE=true says so
# without asking, for a harness that cannot be asked.
under_gctorture <- function() {
  if (isTRUE(as.logical(Sys.getenv("ZUINT_GCTORTURE")))) {
    return(TRUE)
  }
  step <- gctorture2(0L)
  if (step > 0L) {
    gctorture2(step)
  }
  step > 0L
}

# `full` everywhere but under gctorture, where it is `small`.
test_size <- function(full, small) {
  if (under_gctorture()) small else full
}

# `x` itself, or under gctorture every `every`th element of it, for a loop
# whose iterations only repeat one another's code paths over other values.
# Iterations are skipped whole, never changed: a test that replays an engine's
# answers (helper-engines.R) asks the same questions in either case.
test_thin <- function(x, every = 3L) {
  if (under_gctorture() && length(x) > 1L) {
    x[seq(1L, length(x), by = every)]
  } else {
    x
  }
}

# Timing means nothing under gctorture, where everything runs 100 times
# slower: skip a test that asserts a time.
skip_if_gctorture <- function() {
  testthat::skip_if(under_gctorture(), "timings mean nothing under gctorture")
}
