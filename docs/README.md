# Qaf Documentation

Welcome to the **Qaf** documentation. Qaf is a small, embeddable programming
language whose entire compiler and interpreter are written in hand-written
x86-64 assembly — no libc, no external runtime, just Linux syscalls.

## Where to start

| Doc | What it covers |
|-----|----------------|
| [Getting started](getting-started.md) | install, build, run your first program, the REPL |
| [The Qaf guide](guide.md) | a hands-on course from `print` to full programs — every construct in the language |
| [Quick reference](reference.md) | the complete syntax on one page |
| [Types & values](types.md) | the five value types and the numeric model |
| [Built-in functions](builtins.md) | every builtin and every `stdlib.qf` helper |
| [Imports & modules](imports.md) | how multi-file programs work |
| [The interactive REPL](repl.md) | the `qafc` shell |
| [Architecture](architecture.md) | how the compiler works: lexer → parser → eval/JIT |
| [GPU support](gpu.md) | the roadmap for Vulkan / OpenCL / OpenGL bindings |

## Example programs

Working programs live in `examples/` and are a great second read after the
guide:

| File | Shows |
|------|-------|
| `examples/fib.qf` | recursion, printing |
| `examples/fact.qf` | recursion, arithmetic |
| `examples/primes.qf` | nested loops, conditionals |
| `examples/collatz.qf` | loops, arithmetic |
| `examples/demo.qf` | exercises the whole standard library |
| `examples/perceptron.qf` | floats + imports, a tiny neuron |
| `examples/body.qf` | imports and function composition |
| `examples/tui_menu.qf` | an interactive text menu |
| `examples/tui_calculator.qf` | an interactive calculator |

## Quick start

```bash
make                 # build qafc
./qafc examples/fib.qf              # run with the JIT (default)
./qafc examples/fib.qf nojit        # run interpreted
./qafc                              # start the interactive REPL
```

```qf
# hello.qf
print "Hello, Qaf!";
```

```bash
$ ./qafc hello.qf
Hello, Qaf!
```