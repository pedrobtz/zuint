# Raw storage of a zuint vector

`zu_storage()` returns the payload a zuint vector is stored in, and
`zu_from_storage()` makes a zuint vector of a payload. Names are kept
both ways, and no other attribute is. They are the public representation
contract: a package that reads or builds zuint vectors in C, such as an
Arrow or database reader, relies on these shapes and nothing else.

## Usage

``` r
zu_storage(x)

zu_from_storage(payload, type)
```

## Arguments

- x:

  A zuint vector.

- payload:

  A double or complex vector, as returned by `zu_storage()`.

- type:

  One of `"int64"`, `"uint64"`, `"int128"` or `"uint128"`.

## Value

`zu_storage()` returns a double or complex vector; `zu_from_storage()` a
zuint vector of `type`.

## Details

|  |  |  |
|----|----|----|
| Type | Payload | One value |
| `int64` | double | the bits of an `int64_t`, as bit64's `integer64` |
| `uint64` | double | the bits of a `uint64_t` |
| `int128` | complex | real part the low 64 bits, imaginary part the high 64 bits, two's complement |
| `uint128` | complex | real part the low 64 bits, imaginary part the high 64 bits |

The bits are in the machine's byte order, and are moved in and out of
the doubles with `memcpy()`, never through a conversion to `double`,
which would change NaN payloads.

Each type's `NA` is one bit pattern, which no value of the type has:

|  |  |  |
|----|----|----|
| Type | `NA` bit pattern | As the integer |
| `int64` | `0x8000000000000000` | `INT64_MIN`, bit64's `NA` |
| `uint64` | `0xFFFFFFFFFFFFFFFF` | `UINT64_MAX` |
| `int128` | high word `0x8000000000000000`, low word 0 | `INT128_MIN` |
| `uint128` | both words `0xFFFFFFFFFFFFFFFF` | `UINT128_MAX` |

So the value an engine can hold at that pattern, such as `UINT64_MAX` in
a `UBIGINT` column, has no zuint form, and a reader decides what to do
with it (zuarrow's `lossy` policy, see
[zuint-arrow](https://pedrobtz.github.io/zuint/reference/zuint-arrow.md)).

These shapes and patterns change only under the rule the R API follows:
with a deprecation, in a release whose `NEWS.md` says so. The payload is
not a number: printing it or computing with it is meaningless.

## Examples

``` r
p <- zu_storage(int128(-1))
p
#> [1] NaN+NaNi
zu_from_storage(p, "int128")
#> <int128[1]>
#> [1] -1
```
