# Getting started

## 1. Build and install qafc

You need nothing but GNU binutils (`as`, `ld`), `make`, and a shell on an
x86-64 Linux system.

**One-step install** (builds, tests, installs, and verifies):

```bash
git clone https://github.com/Abdelrahman-tech453/Qaf-programming-language.git
cd Qaf-programming-language
./install.sh                # PREFIX=/usr/local, or --prefix DIR / ~/.local fallback
```

This gives you two identical commands — the real binary and a link:

```bash
qaf examples/fib.qf     # or: qafc examples/fib.qf
qaf                     # interactive REPL
```

**Manual build:**

```bash
make            # assemble src/qaf.s (includes all src/*.s modules) and link
make test       # run the full test suite in both JIT and interpreter modes
```

The resulting binary is `qafc`.

## 2. Run a program

```bash
./qafc examples/fib.qf      # compiled to native code via the JIT
./qafc examples/fib.qf nojit  # tree-walking interpreter instead
```

Both execution modes are guaranteed to produce identical results (the test
suite checks every program in both modes). Use `nojit` when you want a simple,
predictable interpreter trace.

## 3. Write a file

A Qaf source file is plain text with a `.qf` extension. The classic first
program:

```qf
# hello.qf
print "Hello, Qaf!";
```

Save it and run:

```bash
$ ./qafc hello.qf
Hello, Qaf!
```

`print` is a statement: it takes one expression, prints its value, and writes
a newline.

## 4. Talk to it interactively

Run `qafc` with no arguments (or `./qafc repl`) to get an interactive shell:

```
$ ./qafc
Qaf interactive shell
qaf> print 5 * 7;
35
qaf> fn square(x) { return x * x; }
qaf> print square(12);
144
qaf> [Ctrl-D]
```

See [The interactive REPL](repl.md) for details.

## 5. Where files live

```
qafc                    the compiler/interpreter binary
src/                    the assembly source (one module per pipeline stage)
lib/                    the standard library (stdlib.qf, math.qf)
examples/               example programs to learn from
tests/                  the test suite (make test)
docs/                   this documentation
install.sh              one-step build + test + install script
qaf-highlighting/       editor syntax files
```

`lib/` is the standard-library directory: any program can `from stdlib import *`
no matter what directory the interpreter is invoked from (see
[Imports & modules](imports.md)). In the repository the binary finds it as
`./lib`; after `./install.sh` the installed `qaf` command finds the same files
in `$prefix/lib/qaf`.

## 6. Next steps

Work through [The Qaf guide](guide.md) — it starts at `print` and builds up to
complete programs. Keep [the quick reference](reference.md) handy while you
write, and check [Built-in functions](builtins.md) when you need a function.