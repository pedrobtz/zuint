# tibbles print exact values with short type names

    Code
      print(tibble::tibble(i64 = int64(c("-9223372036854775807", NA)), u64 = uint64(c(
        "18446744073709551614", "0")), i128 = int128(c("-1",
        "170141183460469231731687303715884105727")), u128 = uint128(c(NA,
        "340282366920938463463374607431768211454"))))
    Output
      # A tibble: 2 x 4
                         i64                  u64
                       <i64>                <u64>
      1 -9223372036854775807 18446744073709551614
      2                   NA                    0
      # i 2 more variables: i128 <i128>, u128 <u128>

