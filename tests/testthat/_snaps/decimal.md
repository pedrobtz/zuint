# a warning counts each result an operand lost after recycling (#111)

    Code
      r <- big + decimal128(rep("0.1", 5), 10, 1)
    Condition
      Warning in `Ops.zu_decimal128()`:
      5 results are out of range. NA produced.

