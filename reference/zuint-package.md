# zuint: Lossless 64- And 128-Bit Integers for 'Arrow' and 'DuckDB'

Wide integer vectors, signed and unsigned 64-bit and 128-bit, matching
the integer types of 'Apache Arrow' and 'DuckDB'. The four types share
one 'C' core and one lossless promotion order, with exact arithmetic,
comparison, parsing and formatting, and explicit overflow policies. The
signed 64-bit type keeps the 'bit64' 'integer64' storage layout, and
every type converts exactly to and from the 'Arrow' 'C' Data Interface.

## See also

Useful links:

- <https://pedrobtz.github.io/zuint/>

- <https://github.com/pedrobtz/zuint>

- Report bugs at <https://github.com/pedrobtz/zuint/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]
