# tibbles print exact values with short type names

    Code
      print(pillar_tbl(df))
    Output
      # A data frame: 2 x 4
        i64                  u64                  i128                           u128 
        <zu_int64>           <zu_unt64>           <zu_nt128>                     <zu_>
      1 -9223372036854775807 18446744073709551614                              ~     ~
      2                   NA                    0 17014118346046923173168730371~ 3402~

