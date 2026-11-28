# condition messages and the calls they report

    Code
      x <- int64(1.5)
    Condition
      Warning in `int64()`:
      1 value could not be represented as int64 and became NA.
    Code
      x <- int64(c(1.5, 2.5, 3.5))
    Condition
      Warning in `int64()`:
      3 values could not be represented as int64 and became NA.
    Code
      x <- int64(c(big, big, big)) + 1L
    Condition
      Warning in `Ops.zu_int64()`:
      3 results are out of range. NA produced.
    Code
      x <- as.double(uint64("18446744073709551614"))
    Condition
      Warning in `as.double.zu_uint64()`:
      1 value was rounded in the conversion to double.
    Code
      x <- int64(1:3) + int64(1:2)
    Condition
      Warning in `Ops.zu_int64()`:
      longer object length is not a multiple of shorter object length
    Code
      x <- min(int64())
    Condition
      Warning in `min()`:
      no non-missing arguments to min; returning Inf

---

    Code
      int128(1) + uint128(1)
    Condition
      Error in `Ops.zu_int128()`:
      ! int128 and uint128 have no common type; convert one explicitly.

---

    Code
      checked_add(int64(big), 1L)
    Condition
      Error in `checked_add()`:
      ! 1 result is out of range.

---

    Code
      checked_idiv(int64(1), 0L)
    Condition
      Error in `checked_idiv()`:
      ! Division by zero.

---

    Code
      int64(1) + 1.5
    Condition
      Error in `Ops.zu_int64()`:
      ! A double must be integral and in range of int64 to mix with it. Convert it explicitly, or set options(zuint.double = "allow").

---

    Code
      seq_zu(int64(1), int64(5), by = 0L)
    Condition
      Error in `seq_zu()`:
      ! `by` must not be zero.

---

    Code
      quantile(int64(1:3))
    Condition
      Error in `quantile.zu_int64()`:
      ! quantile() for zuint vectors comes after zuint 0.1.0.

---

    Code
      x <- int64(1) + 1.5
    Condition
      Warning in `Ops.zu_int64()`:
      A double is not an integral value in range of int64; computing in double.

