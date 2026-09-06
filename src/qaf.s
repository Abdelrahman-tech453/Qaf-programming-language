#
# qaf.s — the Qaf programming language, implemented entirely in x86-64
# assembly. No libc, no external runtime: just Linux syscalls.
#
# Modular layout: this file only includes the implementation modules below.
#   defs.s      — symbolic constants (.equ)
#   bss.s       — global storage
#   data.s      — read-only strings and fixed encodings
#   syscalls.s  — IO wrappers, file loading, symbol resolution
#   lexer.s     — source text -> tokens
#   parser.s    — tokens -> AST
#   eval.s      — tree-walking evaluator + executor
#   runtime.s   — value helpers shared by interpreter and JIT
#   jit.s       — native-code compiler
#   repl.s      — interactive REPL / simple TUI
#   imports.s   — module (import) path resolution
#   dl.s        — minimal ELF dynamic loader + native-call support
#   main.s      — _start entry point
#
# Build:  as --64 -I src src/qaf.s -o qafc.o && ld -o qafc qafc.o
# Run:    ./qafc program.qf            (JIT)
#         ./qafc program.qf nojit      (interpreted)
#         ./qafc                       (interactive REPL)
#
.intel_syntax noprefix

.include "defs.s"
.include "bss.s"
.include "data.s"
.include "syscalls.s"
.include "lexer.s"
.include "parser.s"
.include "imports.s"
.include "eval.s"
.include "runtime.s"
.include "jit.s"
.include "repl.s"
.include "dl.s"
.include "main.s"
