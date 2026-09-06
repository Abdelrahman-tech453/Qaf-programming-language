# Types & values

Qaf is **dynamically typed**: values carry their type with them at runtime,
and a variable can hold any type at any time. There are five value types.

| Type | Literal example | Runtime tag |
|------|-----------------|-------------|
| int | `42`, `-7` | 0 |
| float | `3.14`, `1e0` is not a literal — write `1.5` | 1 |
| bool | `true`, `false` | 2 |
| str | `"hello"` | 3 |
| list | `list(1, 2)` | 4 |

Internally every value is a single 64-bit word whose low 3 bits are the type
tag, so values compare and switch types with zero overhead:

```
int  = (int64 << 3) | 0
float = double bits, sign preserved, | 1
bool = 0x02 (false) or 0x0A (true)
str  = heap pointer | 3   (byte length stored just before the bytes)
list = heap pointer | 4   (cap, len, then the items)
```

## int

64-bit signed integers. Everything between about ±9.2 quintillion.
`7 / 2` is integer division and truncates to `3`; `7 % 3` is `1`.

## float

IEEE-754 double precision. Write them with a decimal point: `3.14`, `0.5`,
`-2.75`. Mixing an int and a float in an operation promotes the int to float.

`print` shows floats in decimal form. The math builtins `floor`, `sqrt`,
`exp`, `log` return floats.

## bool

`true` and `false`. All comparisons return booleans. In conditions, any
truthiness comes from the boolean itself — Qaf does **not** coerce numbers
in `if` conditions, so write `if (x != 0)` rather than `if (x)`.

## str

Immutable, double-quoted strings. They byte-length-prefixed internally, so
they can hold anything including NUL bytes, and `len(s)` reports bytes.

Two strings index like Python:

```qf
s = "hello";
print s[0];             # h   (a 1-character string, not an int)
print len(s);           # 5
```

Strings are **immutable**: indexing write like `s[0] = "H"` is a runtime
error. Build new strings instead — `str_set(s, 0, "H")` returns a new copy.

Escapes inside string literals: `\n` `\t` `\r` `\0` `\\` `\"`.

## list

Mutable, growable arrays of any values (mixed types allowed, nests allowed).

```qf
xs = list(10, 20);
push(xs, 30);
print len(xs);        # 3
print xs[1];          # 20
xs[0] = 99;           # in-place mutation
print pop(xs);        # 30
```

Lists hold **references** to their values. Indexing returns the stored value;
index assignment writes in place.

## Conversions

See [Built-in functions](builtins.md) for `int2str`, `str2int`, `int2float`,
`float2int`, `bool2int`, `int2bool`, and the `to_*` helpers in `stdlib.qf`.

`type(x)` is the honest way to know what you have:

```qf
print type(5);       # 0
print type(5.0);     # 1
print type(true);    # 2
print type("x");     # 3
print type(list());  # 4
```