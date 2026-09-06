# The Qaf guide
### From `print` to complete programs

This guide assumes nothing. By the end you will have used **every** construct
the language has: values, variables, operators, conditionals, loops, strings,
lists, functions, recursion, character I/O, modules, and the standard library.

Run every snippet with `./qafc file.qf`, or paste single statements into the
REPL (`./qafc`) where each line runs immediately.

---

## 1. Printing

The `print` statement evaluates one expression and prints it, followed by a
newline.

```qf
print 5;                  # 5
print 3.14;               # 3.14
print true;               # true
print "hi";               # hi
```

It works for every value type, including lists:

```qf
print list(1, 2, 3);      # [1, 2, 3]
```

---

## 2. Numbers and arithmetic

Two numeric types exist: 64-bit **integers** and IEEE-754 **doubles**
(floats). Integer literals have no decimal point; floats do.

```qf
print 7 + 3;     # 10
print 7 - 3;     # 4
print 7 * 3;     # 21
print 7 / 2;     # 3   (integer division, the result is truncated)
print 7 % 3;     # 1   (modulo)
print 7.0 / 2;   # 3.5 (float division)
print -7;        # -7  (unary minus)
```

Mixing int and float promotes to float. Division by zero is reported at
runtime (`qaf: division by zero`).

Operators, strongest to weakest:

| Level | Operators | Associativity |
|-------|-----------|---------------|
| unary | `-` `!` | right |
| multiply | `*` `/` `%` | left |
| add | `+` `-` | left |
| relational | `<` `>` `<=` `>=` | left |
| equality | `==` `!=` | left |
| logical and | `&&` | left, short-circuit |
| logical or | `\|\|` | left, short-circuit |

Use parentheses to group: `print (1 + 2) * 3;   # 9`.

---

## 3. Variables

Three ways to introduce a variable:

```qf
x = 5;        # mutable — created on first assignment
var y = 6;    # explicitly mutable
let z = 7;    # immutable — reassigning it is a runtime error
```

Reassign with `=`:

```qf
x = x + 1;
```

Assigning to a `let` gives `qaf: cannot assign to immutable variable`.
Variables are dynamically typed — the same name can hold an int now and a
string later.

```qf
n = 42;
n = "now a string";
print n;      # now a string
```

---

## 4. Booleans and comparisons

`true` and `false` are the two boolean literals.

```qf
print 1 < 2;       # true
print 3 >= 4;      # false
print 1 == 1;      # true
print 1 != 2;      # true
print !true;       # false   (logical not)
```

`&&` and `||` short-circuit: the right side only runs when needed.

```qf
a = 0;
if (a != 0 && 10 / a > 0) { print "nope"; }   # never divides by zero
```

---

## 5. `if` / `else`

Blocks `{ ... }` are mandatory around branches.

```qf
score = 85;

if (score >= 90) {
  print "A";
} else if (score >= 80) {
  print "B";
} else if (score >= 70) {
  print "C";
} else {
  print "fail";
}
```

A one-armed `if` is fine; `else` is optional.

```qf
if (score < 40) {
  print "too low";
}
```

---

## 6. `while` loops

```qf
i = 1;
while (i <= 5) {
  print i;
  i = i + 1;
}
```

`break` exits the loop immediately; `continue` jumps to the condition.

```qf
i = 0;
while (i < 20) {
  i = i + 1;
  if (i % 2 == 1) { continue; }   # skip odd numbers
  if (i > 10)     { break; }      # stop at 10, even numbers only
  print i;                        # 2 4 6 8 10
}
```

There is no `for` loop — write a `while` with a counter.

---

## 7. Strings

Strings are double-quoted, immutable, and index like Python: indexing yields a
**one-character string**, not an integer.

```qf
s = "hello";
print s;              # hello
print s[0];           # h        (a 1-char string)
print s[4];           # o
print len(s);         # 5
```

Escapes:
`\n` newline, `\t` tab, `\r` carriage return, `\0` NUL, `\\` backslash,
`\"` quote.

`+` concatenates two strings (it is overloaded over arithmetic):

```qf
print "foo" + "bar";           # foobar
```

The `str_*` builtins do the rest of the work — see
[builtins](builtins.md):

```qf
print str_get(s, 1);             # e
print str_set(s, 0, "H");        # Hello   (returns a new string)
print str_set(s, 2, 88);         # heXlo   (88 = codepoint for 'X')
print char(65);                  # A   (codepoint -> 1-char string)
print s;                         # hello  (strings are immutable; s unchanged)
```

---

## 8. Lists

Create a list with `list(...)`, grow it with `push`, shrink it with `pop`,
size it with `len`, and index it with `[i]`.

```qf
xs = list(10, 20, 30);
print xs;            # [10, 20, 30]
print xs[0];         # 10
print len(xs);       # 3

xs[0] = 99;          # index assignment mutates in place
push(xs, 40);        # append
print xs;            # [99, 20, 30, 40]
print pop(xs);       # 40    (pop returns the last element)
print xs;            # [99, 20, 30]
```

Lists nest freely (a matrix is a list of lists), and can hold mixed types:

```qf
m = list(list(1, 2), list(3, 4));
print m;             # [[1, 2], [3, 4]]
print m[1][0];       # 3
```

An empty list: `list()`.
Popping an empty list is a runtime error (`qaf: pop from empty list`).
Indexing out of range is a runtime error (`qaf: index out of bounds`).

---

## 9. Functions

Define with `fn`, call with parentheses. Up to **8 parameters**.

```qf
fn add(a, b) {
  return a + b;
}

print add(3, 4);     # 7
```

`return expr;` sends a value back. A function with a bare `return;` — or
without any `return` — returns `0`.

Functions close over nothing (no closures), but they **can** call themselves —
recursion works:

```qf
fn fib(n) {
  if (n < 2) { return n; }
  return fib(n - 1) + fib(n - 2);
}

print fib(10);       # 55
```

Each call gets its own isolated local frame, so parameter names never collide
with globals.

Functions are values in the sense that they are registered globally as soon as
they are parsed — so a function can call another function defined later in the
same file:

```qf
fn outer(x) {
  return later(x) + 1;
}

fn later(x) {
  return x * 2;
}

print outer(10);     # 21
```

---

## 10. Reading input (interactive programs)

Three low-level I/O keywords make programs interactive:

```qf
read();        # read one signed integer from stdin
getchar();     # read ONE byte from stdin, or -1 at EOF
putchar(c);    # write one byte (c is a codepoint 0..255)
```

A simple echo:

```qf
print "type a number: ";
a = read();
print "you typed: ";
print a;
```

Draw text with `putchar` — this prints the alphabet:

```qf
c = 65;
while (c <= 90) {
  putchar(c);
  c = c + 1;
}
putchar(10);   # newline
```

(`10` is the newline codepoint. `putchar(65)` writes `A`.)

---

## 11. Modules and the standard library

Split code across files with `import`:

```qf
from stdlib import *;          # every function the module defines
from math import gcd, fact;    # only the named ones
import math;                   # whole-module = same as from math import *
```

Library resolution searches, in order: the **current directory**, the
**program's directory**, the **qafc directory**, and **`<qafc dir>/lib`** —
each with and without a `.qf` suffix. So `from stdlib import *` works from
anywhere.

Two libraries ship with Qaf:

- **`stdlib.qf`** — type predicates, conversions, list helpers, math helpers.
- **`math.qf`** — more arithmetic helpers used by the examples.

Import only registers the imported module's **function definitions**; its
top-level statements are never executed, so library files are safe to import.
Imports nest, and import cycles are caught.

See [Imports & modules](imports.md) and [builtins.md](builtins.md).

```qf
from stdlib import *;

print is_int(5);         # true
print to_str(3.14);      # 3.14
print gcd(48, 18);       # 6
print reverse(list(1, 2, 3));   # [3, 2, 1]
```

---

## 12. Types, conversions, math builtins

Every value carries a runtime type; `type(x)` reports it:

| Tag | Type |
|-----|------|
| 0 | int |
| 1 | float |
| 2 | bool |
| 3 | string |
| 4 | list |

Conversions:

```qf
int2str(123)      # "123"        float2str(3.5)   # "3.5"
str2int("99")     # 99           str2float("2.25") # 2.25
int2float(7)      # 7.0          float2int(9.9)   # 9   (truncates)
bool2int(true)    # 1            int2bool(0)      # false
```

Math:

```qf
floor(3.7)   # 3       sqrt(16.0)  # 4
exp(1.0)     # 2.718…   log(exp(1)) # 1
```

---

## 13. Putting it all together

Two complete programs follow. The first is a classic algorithm; the second is
an interactive menu. Both are in `examples/`.

**Prime sieve (derived from `examples/primes.qf`):**

```qf
# print primes up to n
max = 50;
i = 2;
while (i <= max) {
  isprime = 1;
  d = 2;
  while (d * d <= i) {
    if (i % d == 0) {
      isprime = 0;
    }
    d = d + 1;
  }
  if (isprime == 1) {
    print i;
  }
  i = i + 1;
}
```

**A menu (see `examples/tui_menu.qf` for the full version):**

```qf
from stdlib import square;

run = 1;
while (run == 1) {
  print "1) greet   2) square   0) quit";
  c = read();
  if (c == 1) { print "Hello from Qaf!"; }
  if (c == 2) {
    print "enter n: ";
    n = read();
    print square(n);
  }
  if (c == 0) { run = 0; }
}
print "bye";
```

That is the whole language. You can write anything with these pieces: loops
and conditionals for control, functions and recursion for structure, strings
and lists for data, imports for libraries, and `read`/`getchar`/`putchar` for
interaction. Once you want numbers to move fast, run with the JIT (the
default) — `examples/body.qf` counts to 100,000,000 to demonstrate.

## 14. JIT vs interpreter

`./qafc prog.qf` compiles each function to native x86-64 code (with the same
runtime helpers as the interpreter) and runs it — fast. `./qafc prog.qf nojit`
runs the plain tree-walker. Both produce identical output.

## 15. Limits

The implementation is intentionally compact, so keep these ceilings in mind
(they are generous for a hobby/tool language):

| Limit | Value |
|-------|-------|
| source file size | 64 KiB |
| unique identifiers | 256 |
| registered functions | 64 |
| function parameters | 8 |
| call depth (recursion) | 256 frames |
| tokens per program | 16,384 |
| AST nodes | 16,384 |

See [guide] nothing after here — that's the language. Next: the
[quick reference](reference.md), [builtins](builtins.md), or
[architecture](architecture.md) to see how it all works.