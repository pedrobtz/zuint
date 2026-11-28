# the sentinel error is raised once, with zuarrow's fields

    Code
      conditionMessage(err)
    Output
      [1] "Column `m` (Arrow format `L`) can't be read exactly: 1 value equals 18446744073709551615, the bit pattern of uint64's NA. Use `lossy = \"warn\"` or `lossy = \"allow\"` to read it as NA."

# a lost value names the column, the format and the remedy (#167)

    Code
      conditionMessage(err)
    Output
      [1] "Column `x` (Arrow format `l`) can't be read exactly: 2 values can't be held by uint64, the first -1. Use `lossy = \"warn\"` or `lossy = \"allow\"` to read them as NA."

---

    Code
      conditionMessage(w)
    Output
      [1] "Column `x` (Arrow format `l`): 2 values that uint64 can't hold, read as NA."

---

    Code
      conditionMessage(err)
    Output
      [1] "Column `x` (Arrow format `d:38,0`) can't be read exactly: 1 value can't be held by uint128: -2. A decimal is read by value, and DuckDB writes `UHUGEINT` values of 2^127 and above as negative decimals unless `SET arrow_lossless_conversion = true`. Use `lossy = \"warn\"` or `lossy = \"allow\"` to read it as NA."

---

    Code
      zuarrow::arrow_to_r(a, to = uint128())
    Condition
      Error:
      ! The column (Arrow format `w:16`) can't be read exactly: 1 value can't be held by uint128: -1. Use `lossy = "warn"` or `lossy = "allow"` to read it as NA.

