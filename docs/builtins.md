# Built-in functions

Two layers of functions:

1. **[native builtins](#native-builtins)** — implemented in the runtime
   (assembly), always available, no import needed.
2. **[standard library (`stdlib.qf`)](#stdlibqianchor)** — pure Qaf, loaded
   with `from stdlib import *;`. Two extra modules exist: `math.qf`.

`builtins.md` also lists [`math.qf`](#mathqf).

---

## Native builtins

### `list(...)` — build a list

```qf
xs = list(10, 20, 30);
empty = list();
```

### `len(x)` — size of a string or list

```qf
print len("hello");        # 5   (bytes)
print len(list(1, 2));     # 2
```

### `push(list, value)` — append in place, returns nothing

```qf
xs = list(1);
push(xs, 2);
```

### `pop(list)` — remove and return the last element

```qf
last = pop(xs);
```

`qaf: pop from empty list` on an empty list.

### `type(x)` — runtime type tag

```
0 int | 1 float | 2 bool | 3 str | 4 list
```

### Numeric / string conversions

| Call | Result |
|------|--------|
| `int2str(123)` | `"123"` |
| `float2str(3.5)` | `"3.5"` |
| `str2int("99")` | `99` |
| `str2float("2.25")` | `2.25` |
| `int2float(7)` | `7.0` |
| `float2int(9.9)` | `9` (truncates toward zero) |
| `bool2int(true)` | `1` |
| `int2bool(0)` | `false` (`0`→false, anything else→true) |

### String helpers

```qf
concat(a, b)      # same as a + b on strings: "abc" + "def" -> "abcdef"
char(n)           # codepoint 0..255 -> 1-character string, e.g. char(65) -> "A"
str_get(s, i)     # character at index i as a 1-char string (same as s[i])
str_set(s, i, c)  # new string with index i replaced by c (a char string or codepoint)
```

### Math

```qf
floor(3.7)    # 3.0
sqrt(16.0)    # 4.0
exp(1.0)      # 2.718281…
log(exp(1.0)) # 1.0
```

(These return floats; combine with `float2int` when you need an int.)

---

<a id="stdlibqianchor"></a>
## `stdlib.qf` — the standard library

Load with `from stdlib import *;`. Pure definitions only — importing never
executes side effects.

### Type predicates

```qf
is_int(x)     is_float(x)     is_bool(x)
is_str(x)     is_list(x)
```

All return `true`/`false` by comparing `type(x)`.

### Practical conversions

```qf
to_int(x)     # str -> int, float -> int, otherwise x
to_float(x)   # str -> float, int -> float, otherwise x
to_str(x)     # int/bool/float -> str (bool comes back as its int form), str stays
to_bool(x)    # int -> bool, otherwise x
```

### List helpers

```qf
first(xs)        # xs[0]
last(xs)         # xs[len(xs)-1]
append(xs, x)    # push + return xs (chainable)
contains(xs, v)  # true if some element == v
sum_list(xs)     # total of numeric elements
reverse(xs)      # a NEW list, reversed (input untouched)
```

### Math helpers

```qf
square(x)   # x * x
cube(x)     # x * x * x
gcd(a, b)   # greatest common divisor
fact(n)     # n! (recursive)
fib(n)      # n-th Fibonacci number (recursive)
```

---

<a id="mathqf"></a>
## `math.qf` — extra arithmetic module

Load with `from math import *;` (or `import math;`).

```qf
prime_count(i, n)   # prints the primes from i to n
multiply(x, y)      # x * y
cube(x)             # x^3
square(x)           # x^2
count(a, b)         # counts toward b (a + 1 until reaching b, then b)
add4(a,b,c,d)       # a + b + c + d
add(a, b)           # a + b
gcd(a, b)           # greatest common divisor
fact(n)             # n!
fib(n)              # n-th Fibonacci
poly(x, a, b, c)    # a*x^2 + b*x + c
random(x)           # identity (seed point for future RNG)
```

`math.qf` is intentionally a scratchpad library for experimenting — the
canonical helpers live in `stdlib.qf`.