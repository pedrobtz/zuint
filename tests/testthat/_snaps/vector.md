# print, str and summary show exact values

    Code
      print(int64(c(a = "1", b = NA, c = "-9223372036854775807")))
    Output
      <int64[3]>
                         a                    b                    c 
                         1                   NA -9223372036854775807 
    Code
      print(uint128(c("340282366920938463463374607431768211454", "0")))
    Output
      <uint128[2]>
      [1] 340282366920938463463374607431768211454
      [2]                                       0
    Code
      print(int128())
    Output
      int128(0)
    Code
      str(uint64(c(1, 2, NA)))
    Output
       uint64 [1:3] 1 2 NA
    Code
      str(int128(-1))
    Output
       int128 -1
    Code
      str(int64(1:20))
    Output
       int64 [1:20] 1 2 3 4 5 6 7 8 9 10 ...
    Code
      summary(int128(c("-170141183460469231731687303715884105727", "5", NA)))
    Output
                                          Min. 
      -170141183460469231731687303715884105727 
                                          Max. 
                                             5 
                                          NA's 
                                             1 
    Code
      summary(uint64(1:3))
    Output
      Min. Max. 
         1    3 

