# zuint: Lossless Signed and Unsigned 64- And 128-Bit Integers

Wide integer vectors, signed and unsigned 64-bit and 128-bit, matching
the integer types of databases and columnar formats. The four types
share one 'C' core and one lossless promotion order, with exact
arithmetic, comparison, parsing and formatting, and explicit overflow
policies. The signed 64-bit type keeps the 'bit64' 'integer64' storage
layout. With 'zuarrow' installed, the types read and write Arrow columns
exactly.

## See also

Useful links:

- <https://pedrobtz.github.io/zuint/>

- <https://github.com/pedrobtz/zuint>

- Report bugs at <https://github.com/pedrobtz/zuint/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- The Apache Software Foundation (Arrow C Data Interface header in
  src/vendor/arrow/abi.h) \[copyright holder\]
