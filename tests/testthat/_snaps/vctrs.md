# tibbles print exact values with short type names

    Code
      print(pillar_tbl(df))
    Output
      # A data frame: 2 x 4
                         i64                  u64
                       <i64>                <u64>
      1 -9223372036854775807 18446744073709551614
      2                   NA                    0
      # i 2 more variables: i128 <i128>, u128 <u128>

