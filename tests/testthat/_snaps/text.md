# print shows exact values and stops at max.print

    Code
      print(int128(c("-170141183460469231731687303715884105727", "0", NA)))
    Output
      <int128[3]>
      [1] -170141183460469231731687303715884105727
      [2]                                        0
      [3]                                       NA
    Code
      print(uint64(1:30), max = 4)
    Output
      <uint64[30]>
      [1] 1 2 3 4
       [ reached 'max' / getOption("max.print") -- omitted 26 entries ]
    Code
      withr::with_options(list(max.print = 3), print(int64(1:10)))
    Output
      <int64[10]>
      [1] 1 2 3
       [ reached 'max' / getOption("max.print") -- omitted 7 entries ]
    Code
      print(format(int64(1234567), big.mark = ","))
    Output
      [1] "1,234,567"

