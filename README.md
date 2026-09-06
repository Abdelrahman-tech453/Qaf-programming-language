# Qaf

**Qaf** is a small, embeddable programming language whose compiler/interpreter is
implemented entirely in hand-written x86-64 assembly. The lexer, parser, AST,
evaluator, and JIT are all assembly — there is no libc and no runtime
underneath; every I/O operation is a raw Linux syscall. Qaf source files use
the **`.qf`** extension and are run with the **`qafc`** executable.

Built and tested on x86-64 Linux with GNU `as`/`ld` (Intel syntax via 
`.intel_syntax noprefix`).

```
$ qafc hello.qf
Hello, Qaf!
```

---

## Table of contents
1. [Build & run](#build--run)
2. [Documentation](#documentation)
3. [Interactive REPL](#interactive-repl)
4. [Your first program](#your-first-program)
5. [Language overview](#language-overview)
6. [Types](#types)
7. [Variables & constants](#variables--constants)
8. [Operators](#operators)
9. [Strings](#strings)
10. [Lists](#lists)
11. [Functions](#functions)
12. [Control flow](#control-flow)
13. [Imports / modules](#imports--modules)
14. [Built-in functions](#built-in-functions)
15. [Standard library (`stdlib.qf`)](#standard-library-stdlibqf)
16. [Examples](#examples)
17. [JIT vs interpreter](#jit-vs-interpreter)
18. [Architecture](#architecture)
19. [Limitations & roadmap](#limitations--roadmap)

---

## Install & run

### Install (recommended)

One script gets you a built, tested, installed `qafc` plus a handy `qaf`
command:

```bash
git clone https://github.com/Abdelrahman-tech453/Qaf-programming-language.git
cd Qaf-programming-language
./install.sh                     # build + test + install (needs binutils & make)
```

`install.sh` checks the platform, the build dependencies (binutils, `make`),
and the optional ones (OpenCL loader, ICD vendors, GPU render node); runs the
full test suite; installs `qafc` + the `qaf` command + the standard library +
examples; and then verifies the installed copy end-to-end from a neutral
directory (imports, examples, REPL).

By default it installs under `/usr/local` (use `./install.sh --prefix ~/qaf`
for a custom prefix, or a fallback to `~/.local` is automatic when
`/usr/local` is not writable). Remove everything with `./install.sh --uninstall`.

### Build manually

```bash
make            # assemble + link the qafc binary
make test       # run the whole test suite in JIT and no-JIT modes
./qafc prog.qf           # run with the JIT (default, faster)
./qafc prog.qf nojit     # run with the tree-walking interpreter
./qafc                   # drop into the interactive REPL (also: ./qafc repl)
```

`qaf` is simply a symbolic link to `qafc` — `qaf prog.qf`, `qaf` (REPL) and
`qaf repl` all work.

Manual build:

```bash
as --64 -I src src/qaf.s -o qafc.o
ld -o qafc qafc.o
./qafc prog.qf
```

Source layout under `src/` is modular — one file per compiler stage, all
spliced together by `src/qaf.s` with `.include`:

| File | Contents |
|------|----------|
| `src/qaf.s` | master module that `.include`s everything below |
| `src/defs.s` | symbolic constants (`.equ`) |
| `src/bss.s` | global storage |
| `src/data.s` | read-only strings and fixed instruction encodings |
| `src/syscalls.s` | I/O wrappers, `load_import`, error handlers |
| `src/lexer.s` | source text → tokens |
| `src/parser.s` | tokens → AST |
| `src/imports.s` | module path resolution (CWD + main dir + qafc dir + `lib/`) |
| `src/eval.s` | tree-walking evaluator + executor |
| `src/runtime.s` | value helpers shared by interpreter and JIT |
| `src/jit.s` | native-code compiler |
| `src/repl.s` | interactive REPL |
| `src/main.s` | `_start` entry point |

> **Note on the executable name.** This repository already contains an unrelated
> `qaf/` directory (a separate borrow-checking compiler project), so the Qaf
> executable is named **`qafc`** to avoid clobbering it. The *language* is
> called **Qaf** and its files use the **`.qf`** extension — only the binary's
> filename is `qafc`.

No NASM, no cross-compiler, no dependencies beyond binutils.

---

## Documentation

Full documentation lives in `docs/` — a course and an exhaustive reference:

| Doc | Covers |
|-----|--------|
| [Getting started](docs/getting-started.md) | install, build, run your first program, the REPL |
| [The Qaf guide](docs/guide.md) | the hands-on course: `print` → complete programs, every construct |
| [Quick reference](docs/reference.md) | the complete syntax on one page |
| [Types & values](docs/types.md) | the five value types and the numeric model |
| [Built-in functions](docs/builtins.md) | every native builtin + `stdlib.qf` / `math.qf` reference |
| [Imports & modules](docs/imports.md) | the module system and resolution order |
| [The interactive REPL](docs/repl.md) | the `qafc` shell |
| [Architecture](docs/architecture.md) | lexer → parser → eval/JIT internals |
| [GPU support](docs/gpu.md) | the Vulkan / OpenCL / OpenGL roadmap |

Repository layout:

```
qafc            the compiler/interpreter binary
src/            assembly source — one module per pipeline stage
lib/            the standard library (stdlib.qf, math.qf) — importable from anywhere
examples/       example programs
tests/          the test suite (make test)
docs/           this documentation
qaf-highlighting/  editor syntax files
```

---

## Interactive REPL

Run `qafc` with no arguments (or `./qafc repl`) for an interactive shell.
Each line is tokenized, parsed, and executed immediately; errors print a
message and let you keep going instead of killing the process.

```
$ ./qafc
Qaf interactive shell
qaf> print 1 + 2;
3
qaf> fn sq(x) { return x * x; }
qaf> print sq(9);
81
qaf> x = 10;
qaf> print x * 2;
20
qaf> print 1 / 0;
qaf: division by zero
qaf> print "still alive";
still alive
qaf> [Ctrl+D]
```

State persists across lines — variables, functions, lists, and strings defined
earlier stay available. The REPL runs in interpreter mode (the JIT is used only
for whole-program runs).

---

## Your first program

```qf
# hello.qf
print "Hello, Qaf!";
```

Run it:

```bash
$ ./qafc hello.qf
Hello, Qaf!
```

A slightly bigger example — factorials and greatest-common-divisor:

```qf
fn fact(n) {
  if (n <= 1) {
    return 1;
  }
  return n * fact(n - 1);
}

fn gcd(a, b) {
  while (b != 0) {
    t = b;
    b = a % b;
    a = t;
  }
  return a;
}

print fact(5);     # 120
print gcd(48, 18); # 6
```

---

## Language overview

Qaf is an imperative language with:

- **Five value types**: 64-bit integers, IEEE-754 doubles (floats), booleans,
  strings, and growable lists.
- User-defined functions with recursion, multiple parameters, and return values
  (`return expr;` or implicit `0`).
- Real operator precedence, short-circuiting `&&` / `||`, comparisons,
  `if` / `else`, `while`, `break`, `continue`, `return`.
- `var` (mutable) and `let` (immutable) bindings, plus plain reassignment.
- First-class strings with a Python-like character model (indexing a string
  yields a 1-character string).
- Lists with index assignment, `push`/`pop`, and `len`.
- `from ... import ...` for multi-file programs.

It is Turing-complete and enough to write real (if simple) programs, including
small neural-network demos (see `examples/perceptron.qf`).

---

## Types

`type(x)` returns an integer tag:

| Tag | Type   |
|-----|--------|
| 0   | int    |
| 1   | float  |
| 2   | bool   |
| 3   | string |
| 4   | list   |

Internally each value is a 64-bit tagged word: ints are shifted left 3 bits,
floats live in the low bits of the double's mantissa (`value & -8 | 1`), bools
are `0x02`/`0x0A`, and strings/lists are pointers with low bits `3`/`4`. You
normally never see this — the built-in conversions (`int2str`, `str2int`, …) and
operators take care of it.

---

## Variables & constants

```qf
var x = 10;          # mutable variable
let pi = 3.14;       # immutable binding (reassigning it is a runtime error)
x = x + 1;           # ok
pi = 3;              # qaf: cannot assign to immutable variable
y = 42;              # bare assignment also creates a mutable local
```

Constants:

- **Integers**: `0`, `42`, `-7`, `100`.
- **Floats**: `0.0`, `3.14`, `-2.5`, `1e3`.
- **Booleans**: `true`, `false`.
- **Strings**: `"hello"`, with `\n \t \r \0 \\ \"` escapes.
- **Lists**: `list(1, 2, 3)` or built up with `push`.

---

## Operators

Precedence, highest to lowest:

| Level | Operators |
|-------|-----------|
| unary | `-` `!` |
| mul   | `*` `/` `%` |
| add   | `+` `-` |
| rel   | `<` `>` `<=` `>=` |
| eq    | `==` `!=` |
| and   | `&&` (short-circuit) |
| or    | ` ` (short-circuit) |

Examples:

```qf
print 1 + 2 * 3;        # 7
print 10 % 3;           # 1
print (1 < 2) && (3 > 0); # true
print !false;           # true
```

`+` is overloaded: on two strings it concatenates (`concat`), otherwise it does
numeric addition (int or float). Other arithmetic operators require numbers.

---

## Strings

Strings are first-class values. A character is just a **1-character string**
(Python-like):

```qf
s = "hello";
print s[0];            # "h"  (a 1-char string, not an int)
print str_get(s, 1);   # "e"
print str_set(s, 0, "H"); # "Hello" (returns a NEW string)
print str_set(s, 2, 88);  # "heXlo"  (codepoint 88 = 'X')
print concat("a", "b", "c"); # "abc"  (concat is variadic)
print len(s);          # 5
```

`str_set` takes a 1-char string **or** an integer codepoint. Strings are
immutable: `s[i] = c` (index assignment) on a string is a type error — use
`str_set(s, i, c)`.

---

## Lists

```qf
xs = list(10, 20, 30);
print len(xs);         # 3
print xs[1];           # 20
xs[0] = 99;            # index assignment mutates in place
print xs;              # [99, 20, 30]
push(xs, 40);
print xs;              # [99, 20, 30, 40]
print pop(xs);         # 40
print xs;              # [99, 20, 30]
```

Lists nest, so matrices are lists of row-lists (see the NN example in
`examples/perceptron.qf` and the math notes below).

---

## Functions

```qf
fn add(a, b) {
  return a + b;
}

fn fib(n) {
  if (n < 2) { return n; }
  return fib(n - 1) + fib(n - 2);
}

print add(3, 4);   # 7
print fib(10);     # 55
```

- Recursion and multiple parameters are supported.
- `return expr;` returns a value; a function with no `return` (or a bare
  `return;`) returns `0`.
- Each call runs in an isolated local stack frame.

---

## Control flow

```qf
if (x > 0) {
  print "positive";
} else if (x < 0) {
  print "negative";
} else {
  print "zero";
}

i = 0;
while (i < 5) {
  print i;
  i = i + 1;
}

# break / continue
i = 0;
while (i < 10) {
  i = i + 1;
  if (i % 2 == 0) { continue; }
  if (i == 9) { break; }
  print i;
}
```

Blocks are mandatory for control flow: `if (x) { ... }`, `while (x) { ... }`.

---

## Imports / modules

Qaf supports multi-file programs:

```qf
from math import *;          # import every function defined in math.qf
from test_functions import gcd, fact;  # import only named functions
```

- `from <module> import *` imports **every** function `<module>.qf` defines.
- `from <module> import a, b` imports only `a` and `b`.
- **Module resolution** searches, in order: the current working directory, the
  directory containing the top-level program file, the directory containing the
  `qafc` executable, **`<qafc dir>/lib`**, and **`<parent of qafc dir>/lib/qaf`**
  — each tried with the bare name and with a `.qf` suffix. That covers running
  `qafc` from the repository (`./lib`) and from an installed copy
  (`$prefix/lib/qaf`), with modules next to your program always found first. A
  module in the working directory shadows everything else.
- Imported files are processed at parse time: only their **function
  definitions** are registered — their top-level statements are not executed.
  This makes library files safe to import.
- Imports can nest; an unresolvable import reports `qaf: cannot open file`.

See `lib/stdlib.qf` (the standard library) and `examples/demo.qf` (a runnable
showcase that does `from stdlib import *`).

---

## Built-in functions

### Conversions
| Function | Description |
|----------|-------------|
| `int2str(i)` | int → string |
| `float2str(f)` | float → string |
| `str2int(s)` | string → int (0 if no digits) |
| `str2float(s)` | string → float |
| `int2float(i)` | int → float |
| `float2int(f)` | float → int (truncation) |
| `bool2int(b)` | bool → int (`true`→1, `false`→0) |
| `int2bool(i)` | int → bool (0→`false`, else `true`) |
| `char(n)` | int codepoint → 1-char string |
| `type(x)` | type tag (see [Types](#types)) |

### Math
| Function | Description |
|----------|-------------|
| `floor(f)` | float → largest int ≤ f |
| `sqrt(f)` | square root |
| `exp(f)` | e^x |
| `log(f)` | natural logarithm (ln) |

### Strings
| Function | Description |
|----------|-------------|
| `concat(a, b, …)` | concatenate two or more strings |
| `str_get(s, i)` | 1-char string at index `i` (die on out-of-bounds) |
| `str_set(s, i, c)` | new string with index `i` replaced by `c` (1-char string or int codepoint) |

### Lists
| Function | Description |
|----------|-------------|
| `list(a, b, …)` | create a list from the arguments |
| `len(x)` | length of a string or list |
| `push(xs, v)` | append `v` to list `xs` (returns `xs`) |
| `pop(xs)` | remove and return the last element (die if empty) |

### I/O
| Function | Description |
|----------|-------------|
| `print(x)` | print a value followed by a newline (strings as text, floats in decimal, lists as `[a, b, …]`, bools as `true`/`false`) |
| `putchar(c)` | write one byte |
| `getchar()` | read one byte, or `-1` at EOF |
| `read()` | parse a signed integer from stdin |

---

## Standard library (`lib/stdlib.qf`)

`lib/stdlib.qf` is a clean, importable library. Import it with
`from stdlib import *`.

**Type predicates**

```qf
is_int(x)    is_float(x)   is_bool(x)   is_str(x)    is_list(x)
```

**Conversions**

```qf
to_int(x)    to_float(x)   to_str(x)    to_bool(x)
```

`to_int("42")` → `42`, `to_float("3.5")` → `3.5`, `to_str(7)` → `"7"`,
`to_str(3.14)` → `"3.14"`, `to_bool(0)` → `false`.

**List helpers**

```qf
first(xs)    last(xs)      append(xs, x)  contains(xs, v)
sum_list(xs) reverse(xs)
```

**Math helpers**

```qf
square(x)  cube(x)  gcd(a, b)  fact(n)  fib(n)
```

`examples/demo.qf` exercises all of these (run `./qafc examples/demo.qf`).

---

## Examples

The repository ships example programs (`examples/`), library modules (`lib/`),
and the test suite (`tests/`, driven by `make test`):

| File | What it shows |
|------|---------------|
| `examples/fib.qf` | first Fibonacci numbers |
| `examples/fact.qf` | factorial |
| `examples/primes.qf` | primes up to 50 |
| `examples/collatz.qf` | Collatz step count from 27 |
| `examples/demo.qf` | runnable showcase of `stdlib.qf` |
| `examples/perceptron.qf` | a tiny feed-forward neural-network style function (imports `math`) |
| `examples/body.qf` | imports `perceptron` + `math` and runs an inference / stress test |
| `examples/tui_menu.qf` | a simple interactive text menu (uses `read`/`print`) |
| `examples/tui_calculator.qf` | a tiny interactive integer calculator |
| `lib/stdlib.qf` | the standard library (importable from anywhere) |
| `lib/math.qf` | reusable math helpers used by modules |
| `tests/test_*.qf` | the test suite (`make test`) |

A neural-network flavored snippet (from `perceptron.qf`):

```qf
from math import *;

fn perceptron3i(xo, xt, xth, t, lr) {
  wo = 0.5; wt = 0.3; wth = 0.8; b = 0.01;
  y = add4(multiply(xo, wo), multiply(xt, wt), multiply(xth, wth), b);
  e = t - y;
  if (y <= 0) { y = 0; } else { y = 1; }
  return y;
  # (weight-update code omitted in the demo; see "Limitations")
}
```

---

## JIT vs interpreter

`./qafc prog.qf` compiles each function to native x86-64 machine code (emitted
into executable memory) and runs it. `./qafc prog.qf nojit` falls back to the
tree-walking interpreter. Both produce identical results; the test suite runs
every program in both modes.

---

## Architecture

```
source text -> tokenize -> AST (parse) -> eval (tree-walk)  OR  jit_compile -> native code
```

**Storage.** Tokens, AST nodes, call frames, and the symbol table live in
fixed-size static arrays in `.bss`. Values that need heap storage (strings and
lists) use a bump allocator backed by `sys_brk`.

- `tok_type` / `tok_val` / `tok_line` — parallel token arrays.
- `node_type` / `node_a` / `node_b` / `node_c` / `node_next` — parallel AST arrays
  (node `0` is reserved for "null").
- `sym_name_ptr` / `sym_name_len` — linear-scan symbol table.
- `fn_sym` / `fn_param_count` / `fn_param_syms` / `fn_body` — registered function definitions.
- `call_stack` / `call_depth` — isolated activation frames with parameter and
  local variable storage per depth level.

**Lexer** (`src/lexer.s`, `tokenize`) walks the source once, tracking line
numbers. **Parser** (`src/parser.s`) is recursive-descent with precedence
climbing; `src/imports.s` handles module path resolution. **Evaluator**
(`src/eval.s`: `eval` / `exec_stmt` / `exec_list`) is a tree walk; statements
return status codes (`0 = OK`, `1 = BREAK`, `2 = CONTINUE`, `3 = RETURN`).
**JIT** (`src/jit.s`: `jit_compile`) translates each function into native code,
reusing the same runtime helpers (`src/runtime.s`) so value semantics match
exactly. `src/repl.s` hosts the interactive shell described above.

---

## Limitations & roadmap

- **Strings are immutable** (like Python); mutate via `str_set`, which returns a
  new string.
- **No automatic differentiation / tensors.** The language gives you lists
  (use nested lists for matrices) and `exp`/`log`/`sqrt`/`floor`, enough to
  hand-build small neural nets (see `perceptron.qf`), but there is no built-in
  autograd or tensor type yet. A composable `nns.qf` standard library (Linear
  layers, activations, MSE/binary-cross-entropy loss, SGD) is a planned
  addition.
- **Whole-number float printing.** `float2str(5.0)` prints `5.0`; `0.0` prints
  `0`.
- **Single-file recursion depth** is bounded by the call-stack size.
- **Other architectures** (ARM64 / RISC-V) and a richer standard library are
  future work.

Qaf is meant to be a compact, readable example of how a real language runtime
can be built from nothing but assembly and syscalls — and a fun base to extend.
