# The interactive REPL

`qafc` with **no arguments** — or `./qafc repl` — starts an interactive shell.
Type statements; they run the moment you press Enter.

```
$ ./qafc

Qaf interactive shell
qaf> print 1 + 1;
2
qaf>
```

## What works

Any statement, expression, or definition:

```
qaf> print "hello";
hello
qaf> x = 21 * 2;
qaf> print x;
42
qaf> fn triple(n) { return n * 3; }
qaf> print triple(4);
12
qaf> xs = list(1, 2, 3);
qaf> push(xs, 4);
qaf> print xs;
[1, 2, 3, 4]
qaf> from stdlib import *;
qaf> print gcd(12, 8);
4
```

## State carries across lines

Variables, functions, and imports defined in the session stay defined — like a
real interactive program. Function definitions from one line are callable in
the next (and later lines can define a function, so ordering is flexible).

## Errors don't kill the session

A parse error or a runtime error (division by zero, out-of-bounds, unknown
function, …) prints a message and returns control to the prompt:

```
qaf> print 1 / 0;
qaf: at line 1: division by zero
qaf> print "still alive";
still alive
qaf>
```

You keep all your variables and functions after a recoverable error.

## Exiting

* `Ctrl-D` (EOF) — exit
* or press `Ctrl-C` where supported — exit

## JIT

The REPL runs interpreted (the JIT is used for whole-file execution). The
behavior is identical — the REPL is for experimentation, a file is for speed.

## Try it

`examples/tui_menu.qf` and `examples/tui_calculator.qf` deliver what the REPL
implements programmatically — interactive Qaf programs you can study and
modify.