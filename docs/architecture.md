# Architecture

Qaf is a real, working compiler **implemented entirely in x86-64 assembly**
(no libc, no external runtime, Linux syscalls only). Everything lives in
`src/*.s` and is assembled into a single static binary, `qafc`.

## Pipeline

```
 source text ──► lexer ──► tokens ──► recursive-descent parser ──► AST ──► evaluator
                                                      │
                            (optionally) fused into native code by the JIT
```

`src/qaf.s` is the master file: it `.include`s the modules in pipeline order.

| Module | Responsibility |
|--------|----------------|
| `defs.s` | syscall numbers, token kinds, AST node kinds, runtime type tags, all size limits |
| `bss.s` | every static buffer (source, tokens, AST, symbol table, import paths, REPL state) |
| `data.s` | string literals (messages, `/proc/self/exe`, REPL banner/prompt) |
| `syscalls.s` | raw syscall wrappers, file loading, import resolution driver, fatal error handlers with REPL recovery |
| `lexer.s` | character scanner: numbers, floats, strings (with escapes), identifiers, operators, keyword classification |
| `parser.s` | recursive-descent parser building a flat, index-linked AST; registers functions |
| `imports.s` | module path resolution (`try_import_path`), dir extraction, `compute_bin_dir` via `readlink("/proc/self/exe")` |
| `eval.s` | the tree-walking interpreter (`eval_node`) |
| `runtime.s` | the shared runtime helpers the JIT also calls: printing, arithmetic, heap allocation, str/list manipulation |
| `jit.s` | translates parsed structures into native x86-64 code in an executable arena |
| `repl.s` | the interactive shell (read line, parse, eval, recover from errors) |
| `main.s` | `_start`: registers builtins, resolves `qafc`'s own dir, dispatches REPL vs. program |

## The type system is the tag bits

Every value is one machine word whose low 3 bits identify the type, so
`type(x)` is effectively free:

```
tag 0  int     = (int64 << 3)
tag 1  float   = double bits (shifted, sign preserved) | 1
tag 2  bool    = 0x02 (false) | 0x0A (true)
tag 3  str     = heap pointer | 3, byte length stored at ptr[-8]
tag 4  list    = heap pointer | 4, layout: [cap][len][items...]
```

The tag is both the discriminator and the alignment marker, and the runtime
can add 1, extract a pointer, or tag a raw int with three instructions.

## Execution modes

1. **Interpreter** (`nojit`): `eval_node` walks the AST.
2. **JIT** (default): each function is compiled to native code in a 4 MiB
   `mmap(PROT_EXEC)` arena as the program loads. The generated code calls the
   same runtime helpers as the interpreter, so behavior is identical — but
   loops run orders of magnitude faster. Fixup tables resolve forward
   references (calls to later functions, loops, breaks, returns) after the
   pass. `examples/body.qf` deliberately counts high to demonstrate the JIT.

## Modules and imports

`qafc` resolves its own location via `readlink("/proc/self/exe")`
(`SYS_READLINK`), records the directory, and computes `<that dir>/lib` — the
standard library. `load_import` then tries, in order:

1. the current working directory,
2. the top-level program's directory,
3. `qafc`'s directory,
4. `<qafc dir>/lib`,

each with and without a `.qf` suffix. Imported modules contribute their
function definitions to the global function table; nothing executes.

## REPL error recovery

The REPL snapshots the stack pointer on entry; on a runtime error the handler
(`die_repl`) unwinds to the saved frame and returns to the loop, keeping the
global state so a typo never loses the session.

## Constants worth knowing

`MAXTOK 16k`, `MAXNODE 16k`, `MAXSYM 256`, `MAXFN 64`, `MAXPARAMS 8`,
`MAXFRAMES 256` (call depth), source/import buffers 64 KiB, heap grown in
1 MiB chunks, JIT arena 4 MiB.

## The GPU roadmap

See [GPU support](gpu.md) — it builds on this same trick of the JIT already
emitting native code: the future native-call builtins (`dlopen`, `dlsym`,
`call`) will reuse the JIT's ability to `call` arbitrary addresses.