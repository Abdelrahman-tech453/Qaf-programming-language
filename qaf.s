#
# qaf.s — the Qaf programming language, implemented entirely in x86-64
# assembly. No libc, no external runtime: just Linux syscalls.
#
# Pipeline:  source text -> lexer -> tokens -> recursive-descent parser
#            -> AST (flat arrays, index-linked) -> tree-walking evaluator
#
# Build:  as --64 qaf.s -o qaf.o && ld -o qaf qaf.o
# Run:    ./qaf program.qf
#
.intel_syntax noprefix

# ---------------------------------------------------------------- syscalls --
.equ SYS_READ,   0
.equ SYS_WRITE,  1
.equ SYS_OPEN,   2
.equ SYS_CLOSE,  3
.equ SYS_MMAP,   9
.equ SYS_MPROTECT, 10
.equ SYS_EXIT,   60

.equ PROT_READ,  1
.equ PROT_WRITE, 2
.equ PROT_EXEC,  4
.equ MAP_PRIVATE, 2
.equ MAP_ANONYMOUS, 0x20

.equ JIT_ARENA_SIZE, 0x400000  # 4 MiB executable arena
.equ JIT_MAX_FIXUPS, 4096
.equ JIT_MAX_CALLS,  512
.equ JIT_MAX_BREAKS, 512
.equ JIT_MAX_RETS,   512
.equ JIT_MAX_LOOPS,  64

# ------------------------------------------------------------- token kinds --
.equ TOK_EOF,      0
.equ TOK_NUM,      1
.equ TOK_IDENT,    2
.equ TOK_PLUS,     3
.equ TOK_MINUS,    4
.equ TOK_STAR,     5
.equ TOK_SLASH,    6
.equ TOK_PERCENT,  7
.equ TOK_ASSIGN,   8
.equ TOK_EQEQ,     9
.equ TOK_NE,       10
.equ TOK_LT,       11
.equ TOK_GT,       12
.equ TOK_LE,       13
.equ TOK_GE,       14
.equ TOK_LPAREN,   15
.equ TOK_RPAREN,   16
.equ TOK_LBRACE,   17
.equ TOK_RBRACE,   18
.equ TOK_SEMI,     19
.equ TOK_IF,       20
.equ TOK_ELSE,     21
.equ TOK_WHILE,    22
.equ TOK_PRINT,    23
.equ TOK_LOGAND,   24
.equ TOK_LOGOR,    25
.equ TOK_BANG,     26
.equ TOK_BREAK,    27
.equ TOK_CONTINUE, 28
.equ TOK_FN,       29
.equ TOK_RETURN,   30
.equ TOK_COMMA,    31
.equ TOK_STR,      32
.equ TOK_READ,     33
.equ TOK_PUTCHAR,  34
.equ TOK_GETCHAR,  35
.equ TOK_FROM,     36
.equ TOK_IMPORT,   37
.equ TOK_VAR,      38
.equ TOK_LET,      39
.equ TOK_FLOAT,    40
.equ TOK_LBRACKET, 41
.equ TOK_RBRACKET, 42
.equ TOK_BOOL,     43

# -------------------------------------------------------------- AST kinds --
.equ ND_NUM,       1
.equ ND_VAR,       2
.equ ND_NEG,       3
.equ ND_ADD,       4
.equ ND_SUB,       5
.equ ND_MUL,       6
.equ ND_DIV,       7
.equ ND_MOD,       8
.equ ND_EQ,        9
.equ ND_NE,        10
.equ ND_LT,        11
.equ ND_GT,        12
.equ ND_LE,        13
.equ ND_GE,        14
.equ ND_ASSIGN,    15
.equ ND_PRINT,     16
.equ ND_IF,        17
.equ ND_WHILE,     18
.equ ND_NOT,       19
.equ ND_AND,       20
.equ ND_OR,        21
.equ ND_BREAK,     22
.equ ND_CONTINUE,  23
.equ ND_FN,        24
.equ ND_RETURN,    25
.equ ND_CALL,      26
.equ ND_EXPR_STMT, 27
.equ ND_STR,       28
.equ ND_READ,      29
.equ ND_PUTCHAR,   30
.equ ND_GETCHAR,   31
.equ ND_IMPORT,    32
.equ ND_FLOAT,     33
.equ ND_VAR_DECL,  34
.equ ND_LIST_CALL, 35
.equ ND_LEN,       36
.equ ND_PUSH,      37
.equ ND_POP,       38
.equ ND_INDEX,     39
.equ ND_INDEX_ASSIGN, 40
.equ ND_TYPE,      41
.equ ND_INT2STR,   42
.equ ND_FLOAT2STR, 43
.equ ND_STR2INT,   44
.equ ND_STR2FLOAT, 45
.equ ND_INT2FLOAT, 46
.equ ND_FLOAT2INT, 47
.equ ND_BOOL2INT,  48
.equ ND_INT2BOOL,  49
.equ ND_CONCAT,    50
.equ ND_CHAR,      51
.equ ND_STR_GET,   52
.equ ND_STR_SET,   53
.equ ND_FLOOR,     54
.equ ND_SQRT,      55
.equ ND_EXP,       56
.equ ND_LOG,       57

# ------------------------------------------------------- runtime type tags --
# Hybrid dynamic typing: every value's low 3 bits are its type tag.
#   tag 0 (000): int     — value stored as (int64 << 3)
#   tag 1 (001): float   — double bits shifted <<3, sign kept in bit 63, |1
#   tag 2 (010): bool    — BOOL_FALSE / BOOL_TRUE
#   tag 3 (011): str     — heap pointer | 3, ptr[-8] = byte length
#   tag 4 (100): list    — heap pointer | 4, [ptr]=cap, [ptr+8]=len, [ptr+16]=items
.equ TAG_FLOAT,    1
.equ TAG_BOOL,     2
.equ TAG_STR,      3
.equ TAG_LIST,     4
.equ BOOL_FALSE,   0x02
.equ BOOL_TRUE,    0x0A

.equ HEAP_CHUNK,   0x100000     # 1 MiB heap chunks for str/list allocations

.equ MAXTOK,       16384
.equ MAXNODE,      16384
.equ MAXSYM,       256
.equ MAXFN,        64
.equ MAXPARAMS,    8
.equ MAXFRAMES,    256
.equ MAXSTR,       512
.equ STRPOOL_SIZE, 65536

# =============================================================== storage ==
.section .bss
src_buf:        .skip 65536       # raw source text
src_len:        .skip 8

tok_type:       .skip MAXTOK*8    # parallel token arrays
tok_val:        .skip MAXTOK*8
tok_line:       .skip MAXTOK*8    # source line number per token
cur_tok:        .skip 8           # parser cursor into tok_* arrays

# AST: parallel arrays, node 0 is reserved as the "null" node.
node_type:      .skip MAXNODE*8
node_a:         .skip MAXNODE*8
node_b:         .skip MAXNODE*8
node_c:         .skip MAXNODE*8
node_next:      .skip MAXNODE*8
node_n:         .skip 8

sym_name_ptr:   .skip MAXSYM*8    # symbol table: pointer into sym_name_pool per name
sym_name_len:   .skip MAXSYM*8
sym_name_pool:  .skip MAXSYM*64   # persistent name storage (names are copied here)
sym_pool_pos:   .skip 8
sym_n:          .skip 8
sym_mutable:    .skip MAXSYM*8    # 1 = declared with `let` (immutable)
digitbuf:       .skip 64          # scratch for number -> decimal (int and float formatting)
fmtbuf:         .skip 96          # scratch for float -> decimal digits
program_root:   .skip 8

# Functions & Call Stack
fn_sym:         .skip MAXFN*8
fn_param_count: .skip MAXFN*8
fn_param_syms:  .skip MAXFN*MAXPARAMS*8
fn_body:        .skip MAXFN*8
fn_n:           .skip 8

call_depth:     .skip 8
call_stack:     .skip MAXFRAMES*MAXSYM*8 # 256 frames x 256 variables x 8 bytes
return_val:     .skip 8

# String Pool & Character I/O
str_pool_buf:   .skip STRPOOL_SIZE
str_pool_ptr:   .skip MAXSTR*8
str_pool_len:   .skip MAXSTR*8
str_pool_pos:   .skip 8
str_n:          .skip 8
char_io_buf:    .skip 16

# Imports: the lexer reads from lex_src_ptr (main buffer or import_buf),
# writing tokens from tok_write_pos onward; tok_count tracks the end of
# all tokens seen so far (including each file's TOK_EOF).
lex_src_ptr:    .skip 8
tok_write_pos:  .skip 8
tok_count:      .skip 8
import_mode:    .skip 8           # 1 while parsing an imported file (defer fn registration)
import_all:     .skip 8           # 1 if "import *"
import_count:   .skip 8
import_depth:   .skip 8           # guards against import cycles
import_syms:    .skip MAXSYM*8    # names requested in the import statement
# Per-depth import filter (saved so nested imports don't clobber it):
# slots are indexed by import_depth, each holding import_all/count/syms.
import_filter_all:   .skip 64*8
import_filter_count: .skip 64*8
import_filter_syms:  .skip 64*MAXSYM*8
import_name_buf: .skip 256        # NUL-terminated filename scratch
import_buf:     .skip 65536       # source text of the file currently being imported

# Heap (mmap bump allocator) for str values and lists
heap_base:      .skip 8
heap_pos:       .skip 8
heap_end:       .skip 8

# Symbol IDs of the builtin functions (registered at _start)
builtin_list_sym:    .skip 8
builtin_len_sym:     .skip 8
builtin_push_sym:    .skip 8
builtin_pop_sym:     .skip 8
builtin_type_sym:    .skip 8
builtin_int2str_sym: .skip 8
builtin_float2str_sym: .skip 8
builtin_str2int_sym: .skip 8
builtin_str2float_sym: .skip 8
builtin_int2float_sym: .skip 8
builtin_float2int_sym: .skip 8
builtin_bool2int_sym: .skip 8
builtin_int2bool_sym: .skip 8
builtin_concat_sym:  .skip 8
builtin_char_sym:    .skip 8
builtin_str_get_sym: .skip 8
builtin_str_set_sym: .skip 8
builtin_floor_sym:   .skip 8
builtin_sqrt_sym:    .skip 8
builtin_exp_sym:     .skip 8
builtin_log_sym:     .skip 8
f_tmp:            .skip 8           # 8-byte scratch for FPU transcendentals

# Pending function definitions from the imported file, filtered into the
# real function table only for the requested names.
pend_fn_sym:         .skip MAXFN*8
pend_fn_param_count: .skip MAXFN*8
pend_fn_param_syms:  .skip MAXFN*MAXPARAMS*8
pend_fn_body:        .skip MAXFN*8
pend_fn_n:           .skip 8

# JIT: native code addresses per function (0 = run interpreted)
fn_jit:         .skip MAXFN*8
jit_arena:      .skip 8            # base of the mmap'd code arena
jit_pos:        .skip 8            # absolute next-emit address
jit_end:        .skip 8            # absolute end of the arena
jit_depth:      .skip 8            # runtime nesting counter for native frames
jit_failed:     .skip 8            # 1 = compile overflow/failure in progress
jit_code_start: .skip 8            # emit address at current fn start (rollback point)
jit_fn_index:   .skip 8            # current fn index (debugging)
jit_fn_end:     .skip 8            # emit address of the fn epilogue label
jit_frame_size: .skip 8

# Slot map: symbol id -> frame slot (slot i lives at [rbp - (i+1)*8])
jit_slot_sym:   .skip MAXSYM*8
jit_slot_off:   .skip MAXSYM*8
jit_slot_n:     .skip 8

# Loop stack (native compile-time): continue target + first-break index
jit_loop_cnt:       .skip 8
jit_loop_cont:      .skip JIT_MAX_LOOPS*8
jit_loop_brk_start: .skip JIT_MAX_LOOPS*8

# Pending break jump positions (E9 + placeholder), patched at loop end
jit_brk_pos:        .skip JIT_MAX_BREAKS*8
jit_brk_n:          .skip 8

# Forward-jump fixups: position of each rel32 field, patched via jit_set_label
jit_fix_pos:        .skip JIT_MAX_FIXUPS*8
jit_fix_n:          .skip 8
jit_fix_base:       .skip 8        # fixup index range start for the current fn

# Return-jump fixups (indices into jit_fix_pos), patched to the fn epilogue
jit_ret_fix:        .skip JIT_MAX_RETS*8
jit_ret_n:          .skip 8

# Call sites: position of the imm64 target placeholder + fn index; patched
# after all functions have been compiled
jit_call_pos:       .skip JIT_MAX_CALLS*8
jit_call_fn:        .skip JIT_MAX_CALLS*8
jit_call_n:         .skip 8

.section .data
msg_usage:          .ascii "usage: qafc <program.qf>\n"
msg_usage_len = . - msg_usage
msg_open:           .ascii "qaf: cannot open file\n"
msg_open_len = . - msg_open
msg_parse_p1:       .ascii "qaf: parse error on line "
msg_parse_p1_len = . - msg_parse_p1
msg_divzero:        .ascii "qaf: division by zero\n"
msg_divzero_len = . - msg_divzero
msg_undef_fn:       .ascii "qaf: undefined function\n"
msg_undef_fn_len = . - msg_undef_fn
msg_stackoverflow:  .ascii "qaf: stack overflow\n"
msg_stackoverflow_len = . - msg_stackoverflow
msg_imm:            .ascii "qaf: cannot assign to immutable variable\n"
msg_imm_len = . - msg_imm
msg_idx:            .ascii "qaf: index out of bounds\n"
msg_idx_len = . - msg_idx
msg_empty:          .ascii "qaf: pop from empty list\n"
msg_empty_len = . - msg_empty
msg_type:           .ascii "qaf: type error\n"
msg_type_len = . - msg_type
msg_oom:            .ascii "qaf: out of memory\n"
msg_oom_len = . - msg_oom
msg_newline:        .ascii "\n"
msg_newline_len = . - msg_newline
msg_inf:            .ascii "inf\n"
msg_inf_len = . - msg_inf
msg_nan:            .ascii "nan\n"
msg_nan_len = . - msg_nan
msg_true:           .ascii "true"
msg_true_len = . - msg_true
msg_false:          .ascii "false"
msg_false_len = . - msg_false
msg_lbracket:       .ascii "["
msg_lbracket_len = . - msg_lbracket
msg_rbracket:       .ascii "]"
msg_rbracket_len = . - msg_rbracket
msg_comma:          .ascii ", "
msg_comma_len = . - msg_comma
msg_dot:            .ascii "."
msg_dot_len = . - msg_dot
msg_e:              .ascii "e"
msg_e_len = . - msg_e
msg_minus:          .ascii "-"
msg_minus_len = . - msg_minus
msg_zero:           .ascii "0"
msg_zero_len = . - msg_zero

bname_list:     .ascii "list"
bname_len:      .ascii "len"
bname_push:     .ascii "push"
bname_pop:      .ascii "pop"
bname_type:     .ascii "type"
bname_int2str:  .ascii "int2str"
bname_float2str: .ascii "float2str"
bname_str2int:  .ascii "str2int"
bname_str2float: .ascii "str2float"
bname_int2float: .ascii "int2float"
bname_float2int: .ascii "float2int"
bname_bool2int: .ascii "bool2int"
bname_int2bool: .ascii "int2bool"
bname_concat:   .ascii "concat"
bname_char:     .ascii "char"
bname_str_get:  .ascii "str_get"
bname_str_set:  .ascii "str_set"
bname_floor:    .ascii "floor"
bname_sqrt:     .ascii "sqrt"
bname_exp:      .ascii "exp"
bname_log:      .ascii "log"

f_const_10:         .double 10.0
f_const_05:         .double 0.5
f_const_1:          .double 1.0
f_const_2:          .double 2.0

qword_sign_mask:    .quad 0x8000000000000000
qword_frac_mask:    .quad 0x7FFFFFFFFFFFFFFF
qword_exp_mask:     .quad 0x7FF0000000000000
qword_mant_mask:    .quad 0x000FFFFFFFFFFFFF

# Fixed instruction encodings used by the JIT emitter.
enc_push_rax:      .byte 0x50
enc_pop_rax:       .byte 0x58
enc_pop_rcx:       .byte 0x59
enc_test_rax:      .byte 0x48, 0x85, 0xC0
enc_test_rcx:      .byte 0x48, 0x85, 0xC9
enc_cmp_rax_rcx:   .byte 0x48, 0x39, 0xC8
enc_add_rax_rcx:   .byte 0x48, 0x01, 0xC8
enc_sub_rax_rcx:   .byte 0x48, 0x29, 0xC8
enc_imul_rax_rcx:  .byte 0x48, 0x0F, 0xAF, 0xC1
enc_neg_rax:       .byte 0x48, 0xF7, 0xD8
enc_cqo:           .byte 0x48, 0x99
enc_idiv_rcx:      .byte 0x48, 0xF7, 0xF9
enc_mov_rax_rdx:   .byte 0x48, 0x89, 0xD0
enc_mov_rdi_rax:   .byte 0x48, 0x89, 0xC7
enc_mov_rcx_rax:   .byte 0x48, 0x89, 0xC1
enc_mov_rsi_rax:   .byte 0x48, 0x89, 0xC6
enc_mov_rdx_rax:   .byte 0x48, 0x89, 0xC2
enc_sar_rax_3:     .byte 0x48, 0xC1, 0xF8, 0x03
enc_sar_rdi_3:     .byte 0x48, 0xC1, 0xFF, 0x03
enc_shl_rax_3:     .byte 0x48, 0xC1, 0xE0, 0x03
enc_xor_rax_8:     .byte 0x48, 0x83, 0xF0, 0x08
enc_cmp_rax_imm8:  .byte 0x48, 0x83, 0xF8
enc_xor_eax_eax:   .byte 0x31, 0xC0
enc_mov_rax_1:     .byte 0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00
enc_sete_al:       .byte 0x0F, 0x94, 0xC0
enc_setne_al:      .byte 0x0F, 0x95, 0xC0
enc_setl_al:       .byte 0x0F, 0x9C, 0xC0
enc_setg_al:       .byte 0x0F, 0x9F, 0xC0
enc_setle_al:      .byte 0x0F, 0x9E, 0xC0
enc_setge_al:      .byte 0x0F, 0x9D, 0xC0
enc_movzx_eax_al:  .byte 0x0F, 0xB6, 0xC0
enc_call_rax:      .byte 0xFF, 0xD0
enc_mov_rdi_rsp:   .byte 0x48, 0x89, 0xE7
enc_mov_rbp_rsp:   .byte 0x48, 0x89, 0xE5
enc_push_rbp:      .byte 0x55
enc_mov_r8_rdi:    .byte 0x49, 0x89, 0xF8
enc_rep_stosq:     .byte 0xF3, 0x48, 0xAB
enc_leave:         .byte 0xC9
enc_ret:           .byte 0xC3
enc_dec_rax:       .byte 0x48, 0xFF, 0xC8
enc_inc_rax:       .byte 0x48, 0xFF, 0xC0
enc_sub_rsp_imm8:  .byte 0x48, 0x83, 0xEC
enc_sub_rsp_imm32: .byte 0x48, 0x81, 0xEC
enc_add_rsp_imm8:  .byte 0x48, 0x83, 0xC4
enc_add_rsp_imm32: .byte 0x48, 0x81, 0xC4
enc_mov_rcx_imm32: .byte 0x48, 0xC7, 0xC1
enc_cmp_rax_imm32: .byte 0x48, 0x3D

# ================================================================= code ===
.section .text
.global _start

# ---------------------------------------------------------------- write_str
# rdi=ptr rsi=len
write_str:
    push rax
    push rdi
    push rsi
    push rdx
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    mov rax, SYS_WRITE
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

# ---------------------------------------------------------------------- die
# rdi=ptr rsi=len ; prints message to stdout and exits with status 1
die:
    call write_str
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# ------------------------------------------------------------ die_parse_err
# Uses tok_line[cur_tok*8] to print "qaf: parse error on line <N>\n" and exit 1
die_parse_error:
    lea rdi, [msg_parse_p1]
    mov rsi, msg_parse_p1_len
    call write_str
    mov rax, [cur_tok]
    mov rdi, [tok_line + rax*8]
    test rdi, rdi
    jnz die_parse_error_num
    mov rdi, 1
die_parse_error_num:
    call print_int
    lea rdi, [msg_newline]
    mov rsi, 1
    call write_str
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# ---------------------------------------------------------------- print_int
# rdi = signed 64-bit value; writes decimal representation + newline
print_int:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    lea r13, [digitbuf + 31]
    mov r14, 0
    mov rax, r12
    test rax, rax
    jns print_int_mag_ok
    neg rax
print_int_mag_ok:
print_int_loop:
    xor rdx, rdx
    mov rcx, 10
    div rcx
    add dl, '0'
    dec r13
    mov [r13], dl
    inc r14
    test rax, rax
    jnz print_int_loop
    cmp r12, 0
    jge print_int_out
    dec r13
    mov byte ptr [r13], '-'
    inc r14
print_int_out:
    mov rdi, r13
    mov rsi, r14
    call write_str
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ----------------------------------------------------------------- read_int
# Reads signed 64-bit decimal integer from stdin (fd 0)
read_int:
    push rbx
    push r12
    push r13
    push r14
    xor r12, r12            # accumulated number
    xor r13, r13            # sign (0 = pos, 1 = neg)
    xor r14, r14            # digits seen count
read_int_skip_ws:
    lea rsi, [char_io_buf]
    mov rdx, 1
    xor rdi, rdi            # stdin
    mov rax, SYS_READ
    syscall
    cmp rax, 1
    jl read_int_done        # EOF reached
    movzx ebx, byte ptr [char_io_buf]
    cmp bl, ' '
    je read_int_skip_ws
    cmp bl, 9
    je read_int_skip_ws
    cmp bl, 10
    je read_int_skip_ws
    cmp bl, 13
    je read_int_skip_ws
    cmp bl, '-'
    jne read_int_check_digit
    mov r13, 1              # negative
    jmp read_int_digits
read_int_check_digit:
    cmp bl, '+'
    je read_int_digits
    cmp bl, '0'
    jl read_int_done
    cmp bl, '9'
    jg read_int_done
    sub bl, '0'
    movzx r12, bl
    mov r14, 1
read_int_digits:
    lea rsi, [char_io_buf]
    mov rdx, 1
    xor rdi, rdi            # stdin
    mov rax, SYS_READ
    syscall
    cmp rax, 1
    jl read_int_done        # EOF reached
    movzx ebx, byte ptr [char_io_buf]
    cmp bl, '0'
    jl read_int_done
    cmp bl, '9'
    jg read_int_done
    imul r12, r12, 10
    sub bl, '0'
    movzx rbx, bl
    add r12, rbx
    inc r14
    jmp read_int_digits
read_int_done:
    mov rax, r12
    test r13, r13
    jz read_int_out
    neg rax
read_int_out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# -------------------------------------------------------------- putchar_int
# rdi = char code -> writes 1 byte to stdout, returns char code
putchar_int:
    push rbx
    mov rbx, rdi
    mov [char_io_buf], bl
    lea rsi, [char_io_buf]
    mov rdx, 1
    mov rdi, 1
    mov rax, SYS_WRITE
    syscall
    mov rax, rbx
    pop rbx
    ret

# -------------------------------------------------------------- getchar_int
# Returns: rax = byte code (0..255) or -1 on EOF
getchar_int:
    lea rsi, [char_io_buf]
    mov rdx, 1
    xor rdi, rdi
    mov rax, SYS_READ
    syscall
    cmp rax, 1
    jl getchar_eof
    movzx eax, byte ptr [char_io_buf]
    ret
getchar_eof:
    mov rax, -1
    ret

# -------------------------------------------------------------- load_source
# rdi = pointer to NUL-free filename
load_source:
    push r12
    xor rsi, rsi          # O_RDONLY
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    cmp rax, 0
    jl load_source_err
    mov r12, rax
    mov rdi, r12
    lea rsi, [src_buf]
    mov rdx, 65536
    mov rax, SYS_READ
    syscall
    cmp rax, 0
    jl load_source_err
    mov [src_len], rax
    mov rdi, r12
    mov rax, SYS_CLOSE
    syscall
    pop r12
    ret
load_source_err:
    lea rdi, [msg_open]
    mov rsi, msg_open_len
    call die

# ---------------------------------------------------------------- load_import
# rdi = NUL-terminated filename. Reads the file into import_buf, sets
# src_len and lex_src_ptr. Returns rax = 0 on success, -1 on failure
# (does not die — the caller may retry with a ".qf" suffix).
load_import:
    push rbx
    push r12
    mov rbx, rdi
    xor rsi, rsi          # O_RDONLY
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    cmp rax, 0
    jl load_import_fail
    mov r12, rax
    mov rdi, r12
    lea rsi, [import_buf]
    mov rdx, 65536
    mov rax, SYS_READ
    syscall
    cmp rax, 0
    jl load_import_fail
    mov [src_len], rax
    mov rdi, r12
    mov rax, SYS_CLOSE
    syscall
    lea rax, [import_buf]
    mov [lex_src_ptr], rax
    xor rax, rax
    pop r12
    pop rbx
    ret
load_import_fail:
    pop r12
    pop rbx
    mov rax, -1
    ret

# -------------------------------------------------------------- append_qf_ext
# rdi = NUL-terminated string; appends ".qf" before the final NUL.
append_qf_ext:
    xor rcx, rcx
append_qf_ext_find:
    cmp byte ptr [rdi + rcx], 0
    je append_qf_ext_found
    inc rcx
    cmp rcx, 254
    jge die_parse_error
    jmp append_qf_ext_find
append_qf_ext_found:
    mov byte ptr [rdi + rcx], '.'
    mov byte ptr [rdi + rcx + 1], 'q'
    mov byte ptr [rdi + rcx + 2], 'f'
    mov byte ptr [rdi + rcx + 3], 0
    ret

# ------------------------------------------------------------- resolve_symbol
# rsi=ptr rdx=len -> rax=symbol index
resolve_symbol:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rsi
    mov r15, rdx
    xor rbx, rbx
    mov r13, [sym_n]
resolve_symbol_loop:
    cmp rbx, r13
    jge resolve_symbol_new
    mov rax, [sym_name_len + rbx*8]
    cmp rax, r15
    jne resolve_symbol_next
    mov r12, [sym_name_ptr + rbx*8]
    xor rcx, rcx
resolve_symbol_cmp:
    cmp rcx, r15
    jge resolve_symbol_match
    mov al, [r12 + rcx]
    mov dl, [r14 + rcx]
    cmp al, dl
    jne resolve_symbol_next
    inc rcx
    jmp resolve_symbol_cmp
resolve_symbol_match:
    mov rax, rbx
    jmp resolve_symbol_done
resolve_symbol_next:
    inc rbx
    jmp resolve_symbol_loop
resolve_symbol_new:
    cmp r13, MAXSYM
    jge die_parse_error
    # Copy the name into the persistent pool so entries stay valid even
    # when the source buffer (src_buf/import_buf) is reused.
    mov rax, [sym_pool_pos]
    lea rdi, [sym_name_pool + rax]
    mov [sym_name_ptr + r13*8], rdi
    mov [sym_name_len + r13*8], r15
    xor rcx, rcx
resolve_symbol_copy:
    cmp rcx, r15
    jge resolve_symbol_copy_done
    mov al, [r14 + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp resolve_symbol_copy
resolve_symbol_copy_done:
    add [sym_pool_pos], r15
    mov rax, r13
    inc r13
    mov [sym_n], r13
resolve_symbol_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ------------------------------------------------------------- classify_word
# rsi=ptr to word start, rdx=length -> rax=token type, rcx=value.
classify_word:
    cmp rdx, 2
    jne classify_word_try4
    mov al, [rsi]
    cmp al, 'i'
    je classify_word_if
    cmp al, 'f'
    je classify_word_fn
    jmp classify_word_ident
classify_word_if:
    mov al, [rsi+1]
    cmp al, 'f'
    jne classify_word_ident
    mov rax, TOK_IF
    ret
classify_word_fn:
    mov al, [rsi+1]
    cmp al, 'n'
    jne classify_word_ident
    mov rax, TOK_FN
    ret
classify_word_try4:
    cmp rdx, 4
    jne classify_word_try3
    mov al, [rsi]
    cmp al, 'e'
    je classify_word_else
    cmp al, 't'
    je classify_word_true
    cmp al, 'r'
    je classify_word_read
    cmp al, 'f'
    je classify_word_from
    jmp classify_word_ident
classify_word_try3:
    cmp rdx, 3
    jne classify_word_try5
    mov al, [rsi]
    cmp al, 'v'
    je classify_word_var
    cmp al, 'l'
    je classify_word_let
    jmp classify_word_ident
classify_word_var:
    mov al, [rsi+1]
    cmp al, 'a'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'r'
    jne classify_word_ident
    mov rax, TOK_VAR
    ret
classify_word_let:
    mov al, [rsi+1]
    cmp al, 'e'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 't'
    jne classify_word_ident
    mov rax, TOK_LET
    ret
classify_word_else:
    mov al, [rsi+1]
    cmp al, 'l'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 's'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'e'
    jne classify_word_ident
    mov rax, TOK_ELSE
    ret
classify_word_true:
    mov al, [rsi+1]
    cmp al, 'r'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'u'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'e'
    jne classify_word_ident
    mov rax, TOK_BOOL
    mov rcx, BOOL_TRUE
    ret
classify_word_read:
    mov al, [rsi+1]
    cmp al, 'e'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'a'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'd'
    jne classify_word_ident
    mov rax, TOK_READ
    ret
classify_word_from:
    mov al, [rsi+1]
    cmp al, 'r'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'o'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'm'
    jne classify_word_ident
    mov rax, TOK_FROM
    ret
classify_word_try5:
    cmp rdx, 5
    jne classify_word_try6
    mov al, [rsi]
    cmp al, 'w'
    je classify_word_while
    cmp al, 'p'
    je classify_word_print
    cmp al, 'f'
    je classify_word_false
    cmp al, 'b'
    je classify_word_break
    jmp classify_word_ident
classify_word_while:
    mov al, [rsi+1]
    cmp al, 'h'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'i'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'l'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'e'
    jne classify_word_ident
    mov rax, TOK_WHILE
    ret
classify_word_print:
    mov al, [rsi+1]
    cmp al, 'r'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'i'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'n'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 't'
    jne classify_word_ident
    mov rax, TOK_PRINT
    ret
classify_word_false:
    mov al, [rsi+1]
    cmp al, 'a'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'l'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 's'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'e'
    jne classify_word_ident
    mov rax, TOK_BOOL
    mov rcx, BOOL_FALSE
    ret
classify_word_break:
    mov al, [rsi+1]
    cmp al, 'r'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'e'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'a'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'k'
    jne classify_word_ident
    mov rax, TOK_BREAK
    ret
classify_word_try6:
    cmp rdx, 6
    jne classify_word_try7
    mov al, [rsi]
    cmp al, 'r'
    je classify_word_return
    cmp al, 'i'
    je classify_word_import
    jmp classify_word_ident
classify_word_return:
    mov al, [rsi+1]
    cmp al, 'e'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 't'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'u'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'r'
    jne classify_word_ident
    mov al, [rsi+5]
    cmp al, 'n'
    jne classify_word_ident
    mov rax, TOK_RETURN
    ret
classify_word_import:
    mov al, [rsi+1]
    cmp al, 'm'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'p'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'o'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'r'
    jne classify_word_ident
    mov al, [rsi+5]
    cmp al, 't'
    jne classify_word_ident
    mov rax, TOK_IMPORT
    ret
classify_word_try7:
    cmp rdx, 7
    jne classify_word_try8
    mov al, [rsi]
    cmp al, 'p'
    je classify_word_putchar
    cmp al, 'g'
    je classify_word_getchar
    jmp classify_word_ident
classify_word_putchar:
    mov al, [rsi+1]
    cmp al, 'u'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 't'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'c'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'h'
    jne classify_word_ident
    mov al, [rsi+5]
    cmp al, 'a'
    jne classify_word_ident
    mov al, [rsi+6]
    cmp al, 'r'
    jne classify_word_ident
    mov rax, TOK_PUTCHAR
    ret
classify_word_getchar:
    mov al, [rsi+1]
    cmp al, 'e'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 't'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 'c'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'h'
    jne classify_word_ident
    mov al, [rsi+5]
    cmp al, 'a'
    jne classify_word_ident
    mov al, [rsi+6]
    cmp al, 'r'
    jne classify_word_ident
    mov rax, TOK_GETCHAR
    ret
classify_word_try8:
    cmp rdx, 8
    jne classify_word_ident
    mov al, [rsi]
    cmp al, 'c'
    jne classify_word_ident
    mov al, [rsi+1]
    cmp al, 'o'
    jne classify_word_ident
    mov al, [rsi+2]
    cmp al, 'n'
    jne classify_word_ident
    mov al, [rsi+3]
    cmp al, 't'
    jne classify_word_ident
    mov al, [rsi+4]
    cmp al, 'i'
    jne classify_word_ident
    mov al, [rsi+5]
    cmp al, 'n'
    jne classify_word_ident
    mov al, [rsi+6]
    cmp al, 'u'
    jne classify_word_ident
    mov al, [rsi+7]
    cmp al, 'e'
    jne classify_word_ident
    mov rax, TOK_CONTINUE
    ret
classify_word_ident:
    call resolve_symbol
    mov rcx, rax
    mov rax, TOK_IDENT
    ret

# ------------------------------------------------------------------ tokenize
# Reads source from lex_src_ptr/src_len, fills tok_type/tok_val/tok_line
# starting at index tok_write_pos, ends with TOK_EOF. On return cur_tok is
# set to tok_write_pos and tok_count is the total token count (incl. EOF).
tokenize:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor rbx, rbx            # rbx = source index
    mov r12, [tok_write_pos]# r12 = token index
    mov r13, [src_len]      # r13 = source length
    mov r11, 1              # r11 = source line number
    mov r10, [lex_src_ptr]  # r10 = source buffer
tokenize_main:
    cmp r12, MAXTOK
    jge tokenize_too_many
tokenize_ws:
    cmp rbx, r13
    jge tokenize_emit_eof
    movzx eax, byte ptr [r10 + rbx]
    cmp al, ' '
    je tokenize_ws_next
    cmp al, 9
    je tokenize_ws_next
    cmp al, 10
    jne tokenize_ws_try_cr
    inc r11
    jmp tokenize_ws_next
tokenize_ws_try_cr:
    cmp al, 13
    je tokenize_ws_next
    cmp al, '#'
    je tokenize_comment
    jmp tokenize_tok_start
tokenize_ws_next:
    inc rbx
    jmp tokenize_ws
tokenize_comment:
    inc rbx
tokenize_comment_loop:
    cmp rbx, r13
    jge tokenize_emit_eof
    movzx eax, byte ptr [r10 + rbx]
    cmp al, 10
    jne tokenize_comment_next
    inc r11
    inc rbx
    jmp tokenize_ws
tokenize_comment_next:
    inc rbx
    jmp tokenize_comment_loop

tokenize_tok_start:
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '"'
    je tokenize_str
    cmp al, '0'
    jl tokenize_try_alpha
    cmp al, '9'
    jg tokenize_try_alpha
    xor rcx, rcx
tokenize_num_loop:
    cmp rbx, r13
    jge tokenize_num_try_dot
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '0'
    jl tokenize_num_try_dot
    cmp al, '9'
    jg tokenize_num_try_dot
    imul rcx, rcx, 10
    sub al, '0'
    movzx rdx, al
    add rcx, rdx
    inc rbx
    jmp tokenize_num_loop
tokenize_num_try_dot:
    cmp al, '.'
    jne tokenize_num_done
    inc rbx                   # skip '.'
    xor r14, r14              # fractional digit count
    xor r9, r9                # decimal exponent accumulator
tokenize_num_frac:
    cmp rbx, r13
    jge tokenize_num_float_mk
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '0'
    jl tokenize_num_try_exp
    cmp al, '9'
    jg tokenize_num_try_exp
    imul rcx, rcx, 10
    sub al, '0'
    movzx rdx, al
    add rcx, rdx
    inc r14
    inc rbx
    jmp tokenize_num_frac
tokenize_num_try_exp:
    cmp al, 'e'
    je tokenize_num_exp_sign
    cmp al, 'E'
    jne tokenize_num_float_mk
tokenize_num_exp_sign:
    inc rbx
    xor r8, r8                # exponent sign: 0 = +, 1 = -
    cmp rbx, r13
    jge tokenize_num_float_mk
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '-'
    jne tokenize_num_exp_plus
    mov r8, 1
    inc rbx
    jmp tokenize_num_exp_loop
tokenize_num_exp_plus:
    cmp al, '+'
    jne tokenize_num_exp_loop
    inc rbx
tokenize_num_exp_loop:
    cmp rbx, r13
    jge tokenize_num_exp_done
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '0'
    jl tokenize_num_exp_done
    cmp al, '9'
    jg tokenize_num_exp_done
    imul r9, r9, 10
    sub al, '0'
    movzx rdx, al
    add r9, rdx
    inc rbx
    jmp tokenize_num_exp_loop
tokenize_num_exp_done:
    test r8, r8
    jz tokenize_num_float_mk
    neg r9
tokenize_num_float_mk:
    mov rdi, rcx
    mov rsi, r14
    mov rdx, r9
    call mk_float
    mov rcx, rax
    mov qword ptr [tok_type + r12*8], TOK_FLOAT
    mov [tok_val + r12*8], rcx
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_num_done:
    mov qword ptr [tok_type + r12*8], TOK_NUM
    mov [tok_val + r12*8], rcx
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main

tokenize_str:
    inc rbx                   # skip opening quote
    mov r14, [str_n]
    cmp r14, MAXSTR
    jge die_parse_error
    mov r15, [str_pool_pos]   # start pos in str_pool_buf
    lea rdi, [str_pool_buf + r15]
    mov [str_pool_ptr + r14*8], rdi
    xor rcx, rcx              # string byte length
tokenize_str_loop:
    cmp rbx, r13
    jge die_parse_error       # unterminated string
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '"'
    je tokenize_str_done
    cmp al, 10
    je die_parse_error        # newline inside string without \n
    cmp al, '\\'
    je tokenize_str_escape
    lea rdx, [str_pool_buf + r15]
    mov [rdx + rcx], al
    inc rcx
    inc rbx
    jmp tokenize_str_loop
tokenize_str_escape:
    inc rbx
    cmp rbx, r13
    jge die_parse_error
    movzx eax, byte ptr [r10 + rbx]
    cmp al, 'n'
    je tokenize_str_esc_n
    cmp al, 't'
    je tokenize_str_esc_t
    cmp al, 'r'
    je tokenize_str_esc_r
    cmp al, '0'
    je tokenize_str_esc_0
    cmp al, '\\'
    je tokenize_str_esc_slash
    cmp al, '"'
    je tokenize_str_esc_quote
    jmp tokenize_str_esc_store
tokenize_str_esc_n:
    mov al, 10
    jmp tokenize_str_esc_store
tokenize_str_esc_t:
    mov al, 9
    jmp tokenize_str_esc_store
tokenize_str_esc_r:
    mov al, 13
    jmp tokenize_str_esc_store
tokenize_str_esc_0:
    mov al, 0
    jmp tokenize_str_esc_store
tokenize_str_esc_slash:
    mov al, '\\'
    jmp tokenize_str_esc_store
tokenize_str_esc_quote:
    mov al, '"'
tokenize_str_esc_store:
    lea rdx, [str_pool_buf + r15]
    mov [rdx + rcx], al
    inc rcx
    inc rbx
    jmp tokenize_str_loop
tokenize_str_done:
    inc rbx                   # skip closing quote
    mov [str_pool_len + r14*8], rcx
    add [str_pool_pos], rcx
    mov qword ptr [tok_type + r12*8], TOK_STR
    mov [tok_val + r12*8], r14
    mov [tok_line + r12*8], r11
    inc r14
    mov [str_n], r14
    inc r12
    jmp tokenize_main

tokenize_try_alpha:
    cmp al, 'a'
    jl tokenize_try_upper
    cmp al, 'z'
    jle tokenize_is_ident_start
tokenize_try_upper:
    cmp al, 'A'
    jl tokenize_try_under
    cmp al, 'Z'
    jle tokenize_is_ident_start
tokenize_try_under:
    cmp al, '_'
    je tokenize_is_ident_start
    jmp tokenize_try_op

tokenize_is_ident_start:
    mov r14, rbx             # word start
    xor r15, r15             # word length
tokenize_word_loop:
    cmp rbx, r13
    jge tokenize_word_done
    movzx eax, byte ptr [r10 + rbx]
    cmp al, 'a'
    jl tokenize_word_chk_upper
    cmp al, 'z'
    jle tokenize_word_char_ok
tokenize_word_chk_upper:
    cmp al, 'A'
    jl tokenize_word_chk_digit
    cmp al, 'Z'
    jle tokenize_word_char_ok
tokenize_word_chk_digit:
    cmp al, '0'
    jl tokenize_word_chk_under
    cmp al, '9'
    jle tokenize_word_char_ok
tokenize_word_chk_under:
    cmp al, '_'
    je tokenize_word_char_ok
    jmp tokenize_word_done
tokenize_word_char_ok:
    inc rbx
    inc r15
    cmp r15, 63
    jl tokenize_word_loop
tokenize_word_done:
    lea rsi, [r10 + r14]
    mov rdx, r15
    call classify_word
    mov [tok_type + r12*8], rax
    mov [tok_val + r12*8], rcx
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main

tokenize_try_op:
    cmp al, '('
    jne tokenize_op2
    mov qword ptr [tok_type + r12*8], TOK_LPAREN
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op2:
    cmp al, ')'
    jne tokenize_op3
    mov qword ptr [tok_type + r12*8], TOK_RPAREN
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op3:
    cmp al, '{'
    jne tokenize_op4
    mov qword ptr [tok_type + r12*8], TOK_LBRACE
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op4:
    cmp al, '}'
    jne tokenize_op5
    mov qword ptr [tok_type + r12*8], TOK_RBRACE
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op5:
    cmp al, ';'
    jne tokenize_op6
    mov qword ptr [tok_type + r12*8], TOK_SEMI
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op6:
    cmp al, ','
    jne tokenize_op7
    mov qword ptr [tok_type + r12*8], TOK_COMMA
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op7:
    cmp al, '+'
    jne tokenize_op8
    mov qword ptr [tok_type + r12*8], TOK_PLUS
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op8:
    cmp al, '-'
    jne tokenize_op9
    mov qword ptr [tok_type + r12*8], TOK_MINUS
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op9:
    cmp al, '*'
    jne tokenize_op10
    mov qword ptr [tok_type + r12*8], TOK_STAR
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op10:
    cmp al, '/'
    jne tokenize_op11
    mov qword ptr [tok_type + r12*8], TOK_SLASH
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op11:
    cmp al, '%'
    jne tokenize_op_lbracket
    mov qword ptr [tok_type + r12*8], TOK_PERCENT
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op_lbracket:
    cmp al, '['
    jne tokenize_op_rbracket
    mov qword ptr [tok_type + r12*8], TOK_LBRACKET
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op_rbracket:
    cmp al, ']'
    jne tokenize_op_and
    mov qword ptr [tok_type + r12*8], TOK_RBRACKET
    mov [tok_line + r12*8], r11
    inc rbx
    inc r12
    jmp tokenize_main
tokenize_op_and:
    cmp al, '&'
    jne tokenize_op_or
    inc rbx
    cmp rbx, r13
    jge tokenize_bad_char
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '&'
    jne tokenize_bad_char
    inc rbx
    mov qword ptr [tok_type + r12*8], TOK_LOGAND
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_op_or:
    cmp al, '|'
    jne tokenize_op12
    inc rbx
    cmp rbx, r13
    jge tokenize_bad_char
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '|'
    jne tokenize_bad_char
    inc rbx
    mov qword ptr [tok_type + r12*8], TOK_LOGOR
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_op12:
    cmp al, '='
    jne tokenize_op13
    inc rbx
    cmp rbx, r13
    jge tokenize_assign_only
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '='
    jne tokenize_assign_only
    inc rbx
    mov qword ptr [tok_type + r12*8], TOK_EQEQ
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_assign_only:
    mov qword ptr [tok_type + r12*8], TOK_ASSIGN
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_op13:
    cmp al, '!'
    jne tokenize_op14
    inc rbx
    cmp rbx, r13
    jge tokenize_bang_only
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '='
    jne tokenize_bang_only
    inc rbx
    mov qword ptr [tok_type + r12*8], TOK_NE
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_bang_only:
    mov qword ptr [tok_type + r12*8], TOK_BANG
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_op14:
    cmp al, '<'
    jne tokenize_op15
    inc rbx
    cmp rbx, r13
    jge tokenize_lt_only
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '='
    jne tokenize_lt_only
    inc rbx
    mov qword ptr [tok_type + r12*8], TOK_LE
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_lt_only:
    mov qword ptr [tok_type + r12*8], TOK_LT
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_op15:
    cmp al, '>'
    jne tokenize_bad_char
    inc rbx
    cmp rbx, r13
    jge tokenize_gt_only
    movzx eax, byte ptr [r10 + rbx]
    cmp al, '='
    jne tokenize_gt_only
    inc rbx
    mov qword ptr [tok_type + r12*8], TOK_GE
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_gt_only:
    mov qword ptr [tok_type + r12*8], TOK_GT
    mov [tok_line + r12*8], r11
    inc r12
    jmp tokenize_main
tokenize_bad_char:
    mov [tok_line + r12*8], r11
    mov [cur_tok], r12
    jmp die_parse_error
tokenize_emit_eof:
    mov qword ptr [tok_type + r12*8], TOK_EOF
    mov [tok_line + r12*8], r11
    inc r12
    mov [tok_count], r12
    mov rax, [tok_write_pos]
    mov [cur_tok], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
tokenize_too_many:
    mov [cur_tok], r12
    jmp die_parse_error

# ------------------------------------------------------------------ mk_float
# rdi = integer+frac digit accumulator, rsi = fractional digit count,
# rdx = decimal exponent (from `e` suffix) -> rax = tagged float value.
# value = acc * 10^(rdx - frac_count)
mk_float:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rdx
    sub r13, rsi
    cvtsi2sd xmm0, r12
    mov rbx, r13
    test rbx, rbx
    jz mk_float_tag
    jns mk_float_mul
    neg rbx
mk_float_div:
    test rbx, rbx
    jz mk_float_tag
    movsd xmm1, [f_const_10]
    divsd xmm0, xmm1
    dec rbx
    jmp mk_float_div
mk_float_mul:
    test rbx, rbx
    jz mk_float_tag
    movsd xmm1, [f_const_10]
    mulsd xmm0, xmm1
    dec rbx
    jmp mk_float_mul
mk_float_tag:
    movq rax, xmm0
    and rax, -8
    or rax, 1
    pop r13
    pop r12
    pop rbx
    ret

# ------------------------------------------------------------------ new_node
# rdi=type rsi=a rdx=b rcx=c -> rax = new node index
new_node:
    mov r8, [node_n]
    mov [node_type + r8*8], rdi
    mov [node_a + r8*8], rsi
    mov [node_b + r8*8], rdx
    mov [node_c + r8*8], rcx
    mov qword ptr [node_next + r8*8], 0
    mov rax, r8
    inc r8
    mov [node_n], r8
    ret

# ----------------------------------------------------------- token cursor --
peek_type:
    mov rax, [cur_tok]
    mov rax, [tok_type + rax*8]
    ret

advance_tok:
    mov rcx, [cur_tok]
    mov rax, [tok_type + rcx*8]
    mov rdx, [tok_val + rcx*8]
    inc rcx
    mov [cur_tok], rcx
    ret

# rdi = expected token type; consumes it or dies with a parse error
expect_tok:
    push rdi
    call peek_type
    pop rdi
    cmp rax, rdi
    jne die_parse_error
    call advance_tok
    ret

# ------------------------------------------------------- expression parser --
# Precedence climbing:
# logical_or (||) -> logical_and (&&) -> equality (==, !=) -> relational (<, >, <=, >=)
# -> additive (+, -) -> mult (*, /, %) -> unary (-, !) -> primary

parse_primary:
    call peek_type
    cmp rax, TOK_NUM
    jne parse_primary_try_bool
    call advance_tok
    shl rdx, 3                # ints are stored shifted left by 3 (tag 0)
    mov rdi, ND_NUM
    mov rsi, rdx
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_bool:
    cmp rax, TOK_BOOL
    jne parse_primary_try_float
    call advance_tok
    mov rdi, ND_NUM
    mov rsi, rdx              # bool literals are already tagged values
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_float:
    cmp rax, TOK_FLOAT
    jne parse_primary_try_str
    call advance_tok
    mov rdi, ND_FLOAT
    mov rsi, rdx
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_str:
    cmp rax, TOK_STR
    jne parse_primary_try_read
    call advance_tok
    mov rdi, ND_STR
    mov rsi, rdx              # str_id
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_read:
    cmp rax, TOK_READ
    jne parse_primary_try_putchar
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    mov rdi, TOK_RPAREN
    call expect_tok
    mov rdi, ND_READ
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_putchar:
    cmp rax, TOK_PUTCHAR
    jne parse_primary_try_getchar
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_RPAREN
    call expect_tok
    pop rax
    mov rdi, ND_PUTCHAR
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_getchar:
    cmp rax, TOK_GETCHAR
    jne parse_primary_try_ident
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    mov rdi, TOK_RPAREN
    call expect_tok
    mov rdi, ND_GETCHAR
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_ident:
    cmp rax, TOK_IDENT
    jne parse_primary_try_lparen
    call advance_tok
    mov r8, rdx               # symbol ID (caller-saved r8)
    call peek_type
    cmp rax, TOK_LPAREN
    je parse_call
    mov rdi, ND_VAR
    mov rsi, r8
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_lparen:
    cmp rax, TOK_LPAREN
    jne die_parse_error
    call advance_tok
    call parse_expr
    push rax
    mov rdi, TOK_RPAREN
    call expect_tok
    pop rax
    ret

# parse_call: r8 = function name symbol index
parse_call:
    call advance_tok          # consume '('
    push r8                   # save fn sym id
    push r12                  # save caller's r12
    push r13                  # save caller's r13
    call peek_type
    cmp rax, TOK_RPAREN
    je parse_call_no_args
    call parse_expr
    mov r12, rax              # r12 = first arg node
    mov r13, rax              # r13 = tail of arg list
parse_call_args_loop:
    call peek_type
    cmp rax, TOK_COMMA
    jne parse_call_args_done
    call advance_tok
    call parse_expr
    mov [node_next + r13*8], rax
    mov r13, rax
    jmp parse_call_args_loop
parse_call_args_done:
    mov rdi, TOK_RPAREN
    call expect_tok
    mov rdx, r12              # rdx = first arg node
    jmp parse_call_mk
parse_call_no_args:
    mov rdi, TOK_RPAREN
    call expect_tok
    xor rdx, rdx              # rdx = 0
parse_call_mk:
    pop r13                   # restore caller's r13
    pop r12                   # restore caller's r12
    pop rsi                   # restore fn sym id into rsi
    mov rdi, ND_CALL
    cmp rsi, [builtin_list_sym]
    je parse_builtin_list
    cmp rsi, [builtin_len_sym]
    je parse_builtin_len
    cmp rsi, [builtin_push_sym]
    je parse_builtin_push
    cmp rsi, [builtin_pop_sym]
    je parse_builtin_pop
    cmp rsi, [builtin_type_sym]
    je parse_builtin_type
    cmp rsi, [builtin_int2str_sym]
    je parse_builtin_int2str
    cmp rsi, [builtin_float2str_sym]
    je parse_builtin_float2str
    cmp rsi, [builtin_str2int_sym]
    je parse_builtin_str2int
    cmp rsi, [builtin_str2float_sym]
    je parse_builtin_str2float
    cmp rsi, [builtin_int2float_sym]
    je parse_builtin_int2float
    cmp rsi, [builtin_float2int_sym]
    je parse_builtin_float2int
    cmp rsi, [builtin_bool2int_sym]
    je parse_builtin_bool2int
    cmp rsi, [builtin_int2bool_sym]
    je parse_builtin_int2bool
    cmp rsi, [builtin_concat_sym]
    je parse_builtin_concat
    cmp rsi, [builtin_char_sym]
    je parse_builtin_char
    cmp rsi, [builtin_str_get_sym]
    je parse_builtin_str_get
    cmp rsi, [builtin_str_set_sym]
    je parse_builtin_str_set
    cmp rsi, [builtin_floor_sym]
    je parse_builtin_floor
    cmp rsi, [builtin_sqrt_sym]
    je parse_builtin_sqrt
    cmp rsi, [builtin_exp_sym]
    je parse_builtin_exp
    cmp rsi, [builtin_log_sym]
    je parse_builtin_log
    xor rcx, rcx
    call new_node
    ret

parse_builtin_list:
    xor rcx, rcx              # count args
    mov rax, rdx
parse_builtin_list_count:
    test rax, rax
    jz parse_builtin_list_done
    inc rcx
    mov rax, [node_next + rax*8]
    jmp parse_builtin_list_count
parse_builtin_list_done:
    mov rdi, ND_LIST_CALL
    mov rsi, rcx              # arg count
    xor rcx, rcx
    call new_node
    ret
parse_builtin_len:    mov rdi, ND_LEN;      jmp parse_builtin_1
parse_builtin_pop:    mov rdi, ND_POP;      jmp parse_builtin_1
parse_builtin_type:   mov rdi, ND_TYPE;     jmp parse_builtin_1
parse_builtin_int2str:    mov rdi, ND_INT2STR;   jmp parse_builtin_1
parse_builtin_float2str:  mov rdi, ND_FLOAT2STR; jmp parse_builtin_1
parse_builtin_str2int:    mov rdi, ND_STR2INT;   jmp parse_builtin_1
parse_builtin_str2float:  mov rdi, ND_STR2FLOAT; jmp parse_builtin_1
parse_builtin_int2float:  mov rdi, ND_INT2FLOAT; jmp parse_builtin_1
parse_builtin_float2int:  mov rdi, ND_FLOAT2INT; jmp parse_builtin_1
parse_builtin_bool2int:   mov rdi, ND_BOOL2INT;  jmp parse_builtin_1
parse_builtin_int2bool:   mov rdi, ND_INT2BOOL;  jmp parse_builtin_1
parse_builtin_char:   mov rdi, ND_CHAR;     jmp parse_builtin_1
parse_builtin_floor:  mov rdi, ND_FLOOR;    jmp parse_builtin_1
parse_builtin_sqrt:   mov rdi, ND_SQRT;     jmp parse_builtin_1
parse_builtin_exp:     mov rdi, ND_EXP;      jmp parse_builtin_1
parse_builtin_log:     mov rdi, ND_LOG;      jmp parse_builtin_1
parse_builtin_1:
    mov rsi, rdx              # arg node (rdx = first arg)
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_builtin_push:
    mov rdi, ND_PUSH
    jmp parse_builtin_2
parse_builtin_concat:
    xor rcx, rcx
    mov rax, rdx
parse_builtin_concat_count:
    test rax, rax
    jz parse_builtin_concat_done
    inc rcx
    mov rax, [node_next + rax*8]
    jmp parse_builtin_concat_count
parse_builtin_concat_done:
    mov rdi, ND_CONCAT
    mov rsi, rcx
    xor rcx, rcx
    call new_node
    ret
parse_builtin_str_get:
    mov rdi, ND_STR_GET
    jmp parse_builtin_2
parse_builtin_2:
    mov rsi, rdx
    mov rdx, [node_next + rdx*8]
    xor rcx, rcx
    call new_node
    ret
parse_builtin_str_set:
    mov rdi, ND_STR_SET
    mov rsi, rdx              # str node
    mov rax, [node_next + rdx*8]
    mov rdx, rax              # index node
    mov rcx, [node_next + rax*8]  # value node
    call new_node
    ret

parse_unary:
    call peek_type
    cmp rax, TOK_MINUS
    je parse_unary_neg
    cmp rax, TOK_BANG
    je parse_unary_not
    jmp parse_postfix
parse_unary_neg:
    call advance_tok
    call parse_unary
    mov rdi, ND_NEG
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_unary_not:
    call advance_tok
    call parse_unary
    mov rdi, ND_NOT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_postfix:
    push rbx
    call parse_primary
    mov rbx, rax
parse_postfix_loop:
    call peek_type
    cmp rax, TOK_LBRACKET
    jne parse_postfix_done
    call advance_tok
    call parse_expr
    push rax
    mov rdi, TOK_RBRACKET
    call expect_tok
    pop rax
    mov rdi, ND_INDEX
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_postfix_loop
parse_postfix_done:
    mov rax, rbx
    pop rbx
    ret

parse_mult:
    push rbx
    push r15
    call parse_unary
    mov rbx, rax
parse_mult_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_STAR
    je parse_mult_op
    cmp r15, TOK_SLASH
    je parse_mult_op
    cmp r15, TOK_PERCENT
    je parse_mult_op
    jmp parse_mult_done
parse_mult_op:
    call advance_tok
    call parse_unary
    mov rdi, ND_MUL
    cmp r15, TOK_STAR
    je parse_mult_settype
    mov rdi, ND_DIV
    cmp r15, TOK_SLASH
    je parse_mult_settype
    mov rdi, ND_MOD
parse_mult_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_mult_loop
parse_mult_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_additive:
    push rbx
    push r15
    call parse_mult
    mov rbx, rax
parse_additive_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_PLUS
    je parse_additive_op
    cmp r15, TOK_MINUS
    je parse_additive_op
    jmp parse_additive_done
parse_additive_op:
    call advance_tok
    call parse_mult
    mov rdi, ND_ADD
    cmp r15, TOK_PLUS
    je parse_additive_settype
    mov rdi, ND_SUB
parse_additive_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_additive_loop
parse_additive_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_relational:
    push rbx
    push r15
    call parse_additive
    mov rbx, rax
parse_relational_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_LT
    je parse_relational_op
    cmp r15, TOK_GT
    je parse_relational_op
    cmp r15, TOK_LE
    je parse_relational_op
    cmp r15, TOK_GE
    je parse_relational_op
    jmp parse_relational_done
parse_relational_op:
    call advance_tok
    call parse_additive
    mov rdi, ND_LT
    cmp r15, TOK_LT
    je parse_relational_settype
    mov rdi, ND_GT
    cmp r15, TOK_GT
    je parse_relational_settype
    mov rdi, ND_LE
    cmp r15, TOK_LE
    je parse_relational_settype
    mov rdi, ND_GE
parse_relational_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_relational_loop
parse_relational_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_equality:
    push rbx
    push r15
    call parse_relational
    mov rbx, rax
parse_equality_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_EQEQ
    je parse_equality_op
    cmp r15, TOK_NE
    je parse_equality_op
    jmp parse_equality_done
parse_equality_op:
    call advance_tok
    call parse_relational
    mov rdi, ND_EQ
    cmp r15, TOK_EQEQ
    je parse_equality_settype
    mov rdi, ND_NE
parse_equality_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_equality_loop
parse_equality_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_logical_and:
    push rbx
    push r15
    call parse_equality
    mov rbx, rax
parse_logical_and_loop:
    call peek_type
    cmp rax, TOK_LOGAND
    jne parse_logical_and_done
    call advance_tok
    call parse_equality
    mov rdi, ND_AND
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_logical_and_loop
parse_logical_and_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_logical_or:
    push rbx
    push r15
    call parse_logical_and
    mov rbx, rax
parse_logical_or_loop:
    call peek_type
    cmp rax, TOK_LOGOR
    jne parse_logical_or_done
    call advance_tok
    call parse_logical_and
    mov rdi, ND_OR
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_logical_or_loop
parse_logical_or_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_expr:
    jmp parse_logical_or

# --------------------------------------------------------- statement parser
# rdi = terminator token type -> rax = index of first stmt (0 if none).
# Links statements via node_next; does not consume the terminator.
parse_stmts_until:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor rbx, rbx
    xor r13, r13
parse_stmts_until_loop:
    call peek_type
    cmp rax, r12
    je parse_stmts_until_done
    cmp rax, TOK_EOF
    je parse_stmts_until_done
    call parse_stmt
    test rbx, rbx
    jnz parse_stmts_until_link
    mov rbx, rax
    mov r13, rax
    jmp parse_stmts_until_loop
parse_stmts_until_link:
    mov [node_next + r13*8], rax
    mov r13, rax
    jmp parse_stmts_until_loop
parse_stmts_until_done:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

parse_block:
    mov rdi, TOK_LBRACE
    call expect_tok
    mov rdi, TOK_RBRACE
    call parse_stmts_until
    push rax
    mov rdi, TOK_RBRACE
    call expect_tok
    pop rax
    ret

parse_program:
    mov rdi, TOK_EOF
    call parse_stmts_until
    ret

parse_stmt:
    call peek_type
    cmp rax, TOK_IF
    je parse_stmt_if
    cmp rax, TOK_WHILE
    je parse_stmt_while
    cmp rax, TOK_PRINT
    je parse_stmt_print
    cmp rax, TOK_BREAK
    je parse_stmt_break
    cmp rax, TOK_CONTINUE
    je parse_stmt_continue
    cmp rax, TOK_FN
    je parse_stmt_fn
    cmp rax, TOK_RETURN
    je parse_stmt_return
    cmp rax, TOK_FROM
    je parse_stmt_import
    cmp rax, TOK_IMPORT
    je parse_stmt_import_whole
    cmp rax, TOK_VAR
    je parse_stmt_var
    cmp rax, TOK_LET
    je parse_stmt_var
    cmp rax, TOK_IDENT
    je parse_stmt_ident
    # Fallback to expression statement
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_EXPR_STMT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_stmt_if:
    jmp parse_if
parse_stmt_while:
    jmp parse_while
parse_stmt_print:
    jmp parse_print
parse_stmt_break:
    jmp parse_break
parse_stmt_continue:
    jmp parse_continue
parse_stmt_fn:
    jmp parse_fn
parse_stmt_return:
    jmp parse_return
parse_stmt_import:
    jmp parse_import
parse_stmt_import_whole:
    jmp parse_import_whole
parse_stmt_var:
    jmp parse_var_decl
parse_stmt_ident:
    mov rax, [cur_tok]
    mov rcx, [tok_type + rax*8 + 8] # peek next token
    cmp rcx, TOK_ASSIGN
    je parse_assign
    cmp rcx, TOK_LBRACKET
    je parse_index_assign
    # Expression statement
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_EXPR_STMT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# var/let x = expr;  ->  ND_VAR_DECL {a: sym id, b: expr, c: mutable flag}
parse_var_decl:
    push rbx
    call peek_type
    cmp rax, TOK_LET
    je parse_var_decl_let
    xor rbx, rbx
    jmp parse_var_decl_kw_done
parse_var_decl_let:
    mov rbx, 1
parse_var_decl_kw_done:
    call advance_tok
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rcx, rdx              # sym id
    mov [sym_mutable + rcx*8], rbx
    mov rdi, TOK_ASSIGN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_VAR_DECL
    mov rsi, rcx
    mov rdx, rax
    mov rcx, rbx
    call new_node
    pop rbx
    ret

# x[i] = v;  ->  ND_INDEX_ASSIGN {a: sym id, b: value expr, c: index expr}
parse_index_assign:
    push rbx
    push r15
    call advance_tok          # consume ident
    mov rbx, rdx              # target sym id
    call advance_tok          # consume '['
    call parse_expr
    mov r15, rax              # index expr
    mov rdi, TOK_RBRACKET
    call expect_tok
    mov rdi, TOK_ASSIGN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_INDEX_ASSIGN
    mov rsi, rbx
    mov rdx, rax
    mov rcx, r15
    call new_node
    pop r15
    pop rbx
    ret

# fn ident ( [param, ...] ) block
parse_fn:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call advance_tok          # consume 'fn'
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rbx, rdx              # function name sym id
    mov rdi, TOK_LPAREN
    call expect_tok
    xor r14, r14              # param count
    mov rax, [import_mode]
    test rax, rax
    jz parse_fn_slot_real
    mov r15, [pend_fn_n]      # pending slot (imported file being parsed)
    cmp r15, MAXFN
    jge die_parse_error
    imul r13, r15, MAXPARAMS  # r13 = base index in pend_fn_param_syms
    jmp parse_fn_slot_done
parse_fn_slot_real:
    mov r15, [fn_n]
    cmp r15, MAXFN
    jge die_parse_error
    imul r13, r15, MAXPARAMS  # r13 = base index in fn_param_syms
parse_fn_slot_done:
    call peek_type
    cmp rax, TOK_RPAREN
    je parse_fn_params_done
parse_fn_params_loop:
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok          # rdx = param sym id
    cmp r14, MAXPARAMS
    jge die_parse_error
    lea r8, [r13 + r14]
    mov r9, [import_mode]
    test r9, r9
    jnz parse_fn_param_store_pend
    mov [fn_param_syms + r8*8], rdx
    jmp parse_fn_param_store_done
parse_fn_param_store_pend:
    mov [pend_fn_param_syms + r8*8], rdx
parse_fn_param_store_done:
    inc r14
    call peek_type
    cmp rax, TOK_COMMA
    jne parse_fn_params_done
    call advance_tok
    jmp parse_fn_params_loop
parse_fn_params_done:
    mov rdi, TOK_RPAREN
    call expect_tok
    call parse_block
    mov r12, rax              # body AST node
    mov r9, [import_mode]
    test r9, r9
    jnz parse_fn_reg_pend
    # Register function in the real table
    mov [fn_sym + r15*8], rbx
    mov [fn_param_count + r15*8], r14
    mov [fn_body + r15*8], r12
    inc r15
    mov [fn_n], r15
    jmp parse_fn_reg_done
parse_fn_reg_pend:
    # Defer registration: keep it pending until the import is resolved
    mov [pend_fn_sym + r15*8], rbx
    mov [pend_fn_param_count + r15*8], r14
    mov [pend_fn_body + r15*8], r12
    inc r15
    mov [pend_fn_n], r15
parse_fn_reg_done:
    # Return ND_FN node
    mov rdi, ND_FN
    mov rsi, r15
    dec rsi
    mov rdx, r12
    xor rcx, rcx
    call new_node
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# import IDENT;  -- whole-file import (like `from IDENT import *`). Same
# load/parse/register machinery as `from`-imports, reached via parse_import_after_names.
parse_import_whole:
    push rbx
    push r12
    push r13
    push r14
    call advance_tok          # consume 'import'
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rbx, rdx              # rbx = filename sym id
    mov rdi, TOK_SEMI
    call expect_tok
    mov qword ptr [import_all], 1
    xor r14, r14
    mov [import_count], r14
    jmp parse_import_after_names

# from IDENT "import" (IDENT ("," IDENT)* | "*") ";"
# Processed at parse time: loads the file (trying the name as-is, then with
# a ".qf" suffix), tokenizes it appended after the last known EOF, parses it
# in defer mode, then registers only the requested function names. Top-level
# statements of the imported file are parsed but never executed.
parse_import:
    push rbx
    push r12
    push r13
    push r14
    call advance_tok          # consume 'from'
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rbx, rdx              # rbx = filename sym id
    mov rdi, TOK_IMPORT
    call expect_tok
    call peek_type
    cmp rax, TOK_STAR
    je parse_import_star
    xor r14, r14              # r14 = number of names to import
parse_import_names_loop:
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    cmp r14, MAXSYM
    jge die_parse_error
    mov [import_syms + r14*8], rdx
    inc r14
    call peek_type
    cmp rax, TOK_COMMA
    jne parse_import_names_done
    call advance_tok
    jmp parse_import_names_loop
parse_import_names_done:
    mov qword ptr [import_all], 0
    jmp parse_import_after_names
parse_import_star:
    call advance_tok          # consume '*'
    mov qword ptr [import_all], 1
    xor r14, r14
parse_import_after_names:
    mov [import_count], r14
    call peek_type
    cmp rax, TOK_SEMI
    jne parse_import_after_semi
    call advance_tok
parse_import_after_semi:
    # Guard against import cycles
    mov rax, [import_depth]
    cmp rax, 64
    jge die_parse_error
    inc rax
    mov [import_depth], rax
    # Save this import's filter into the per-depth slot (nested imports
    # parse with their own filter and must not clobber this one).
    mov r9, [import_all]
    mov [import_filter_all + rax*8], r9
    mov [import_filter_count + rax*8], r14
    imul r9, rax, MAXSYM
    xor rcx, rcx
parse_import_filter_copy:
    cmp rcx, r14
    jge parse_import_filter_done
    mov rdx, [import_syms + rcx*8]
    mov [import_filter_syms + r9*8], rdx
    inc rcx
    add r9, 8
    jmp parse_import_filter_copy
parse_import_filter_done:
    # Build the filename in import_name_buf (cap 252 chars, room for ".qf")
    mov rax, [sym_name_len + rbx*8]
    mov rcx, rax
    cmp rcx, 252
    jle parse_import_fname_len_ok
    mov rcx, 252
parse_import_fname_len_ok:
    mov rsi, [sym_name_ptr + rbx*8]
    lea rdi, [import_name_buf]
    xor rdx, rdx
parse_import_fname_copy:
    cmp rdx, rcx
    jge parse_import_fname_done
    mov al, [rsi + rdx]
    mov [rdi + rdx], al
    inc rdx
    jmp parse_import_fname_copy
parse_import_fname_done:
    mov byte ptr [import_name_buf + rcx], 0
    # Try the exact name first, then with a ".qf" extension
    lea rdi, [import_name_buf]
    call load_import
    test rax, rax
    jz parse_import_loaded
    lea rdi, [import_name_buf]
    call append_qf_ext
    lea rdi, [import_name_buf]
    call load_import
    test rax, rax
    jz parse_import_loaded
    lea rdi, [msg_open]
    mov rsi, msg_open_len
    call die
parse_import_loaded:
    mov r12, [cur_tok]        # save parser cursor
    mov rax, [tok_count]      # append new tokens after the last EOF
    mov [tok_write_pos], rax
    call tokenize
    mov r13, [import_mode]    # save outer mode
    mov qword ptr [import_mode], 1
    call parse_program
    mov [import_mode], r13    # restore outer mode
    call register_imports
    mov [cur_tok], r12        # restore parser cursor
    dec qword ptr [import_depth]
    pop r14
    pop r13
    pop r12
    pop rbx
    # No-op node at runtime (all import work happens at parse time)
    mov rdi, ND_IMPORT
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# Register the pending function definitions whose symbol is in the current
# import's filter slot (or all of them for "import *"). Clears the pending
# list.
register_imports:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, [import_depth]       # this import's filter slot
    xor rbx, rbx              # pending index
register_imports_loop:
    mov rax, [pend_fn_n]
    cmp rbx, rax
    jge register_imports_done
    mov r12, [pend_fn_sym + rbx*8]
    mov rax, [import_filter_all + r15*8]
    test rax, rax
    jnz register_imports_take
    mov r14, [import_filter_count + r15*8]
    imul r13, r15, MAXSYM
    xor rcx, rcx
register_imports_search:
    cmp rcx, r14
    jge register_imports_next
    mov rax, [import_filter_syms + r13*8]
    cmp rax, r12
    je register_imports_take
    inc rcx
    add r13, 8
    jmp register_imports_search
register_imports_take:
    mov rcx, [fn_n]
    cmp rcx, MAXFN
    jge die_parse_error
    mov rax, [pend_fn_sym + rbx*8]
    mov [fn_sym + rcx*8], rax
    mov rax, [pend_fn_param_count + rbx*8]
    mov [fn_param_count + rcx*8], rax
    mov rax, [pend_fn_body + rbx*8]
    mov [fn_body + rcx*8], rax
    imul rdx, rbx, MAXPARAMS
    imul r8, rcx, MAXPARAMS
    xor r13, r13
register_imports_copy_params:
    cmp r13, MAXPARAMS
    jge register_imports_copy_done
    mov rax, [pend_fn_param_syms + rdx*8]
    mov [fn_param_syms + r8*8], rax
    inc r13
    inc rdx
    inc r8
    jmp register_imports_copy_params
register_imports_copy_done:
    inc rcx
    mov [fn_n], rcx
register_imports_next:
    inc rbx
    jmp register_imports_loop
register_imports_done:
    mov qword ptr [pend_fn_n], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# return [expr] ;
parse_return:
    call advance_tok          # consume 'return'
    call peek_type
    cmp rax, TOK_SEMI
    je parse_return_empty
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_RETURN
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_return_empty:
    call advance_tok          # consume ';'
    mov rdi, ND_RETURN
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# if ( expr ) block [else block]
parse_if:
    push rbx
    push r14
    push r15
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    call parse_expr
    mov rbx, rax
    mov rdi, TOK_RPAREN
    call expect_tok
    call parse_block
    mov r14, rax
    xor r15, r15
    call peek_type
    cmp rax, TOK_ELSE
    jne parse_if_mk
    call advance_tok
    call parse_block
    mov r15, rax
parse_if_mk:
    mov rdi, ND_IF
    mov rsi, rbx
    mov rdx, r14
    mov rcx, r15
    call new_node
    pop r15
    pop r14
    pop rbx
    ret

# while ( expr ) block
parse_while:
    push rbx
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    call parse_expr
    mov rbx, rax
    mov rdi, TOK_RPAREN
    call expect_tok
    call parse_block
    mov rdi, ND_WHILE
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    pop rbx
    ret

# print expr ;
parse_print:
    call advance_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_PRINT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# break ;
parse_break:
    call advance_tok
    mov rdi, TOK_SEMI
    call expect_tok
    mov rdi, ND_BREAK
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# continue ;
parse_continue:
    call advance_tok
    mov rdi, TOK_SEMI
    call expect_tok
    mov rdi, ND_CONTINUE
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# ident = expr ;
parse_assign:
    push rbx
    call peek_type
    cmp rax, TOK_IDENT
    je parse_assign_ok
    jmp die_parse_error
parse_assign_ok:
    call advance_tok
    mov rbx, rdx
    mov rdi, TOK_ASSIGN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_ASSIGN
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    pop rbx
    ret

# ------------------------------------------------------------- evaluator --
# cmp_helper: r12 = comparison node (set by caller). Evaluates node_a and
# node_b and leaves FLAGS set from `cmp left, right`.
cmp_helper:
    push rbx
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    cmp rbx, rax
    pop rbx
    ret

# eval: rdi = node index -> rax = value
eval:
    push rbx
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_NUM
    je eval_num
    cmp rax, ND_VAR
    je eval_var
    cmp rax, ND_NEG
    je eval_neg
    cmp rax, ND_ADD
    je eval_add
    cmp rax, ND_SUB
    je eval_sub
    cmp rax, ND_MUL
    je eval_mul
    cmp rax, ND_DIV
    je eval_div
    cmp rax, ND_MOD
    je eval_mod
    cmp rax, ND_EQ
    je eval_eq
    cmp rax, ND_NE
    je eval_ne
    cmp rax, ND_LT
    je eval_lt
    cmp rax, ND_GT
    je eval_gt
    cmp rax, ND_LE
    je eval_le
    cmp rax, ND_GE
    je eval_ge
    cmp rax, ND_NOT
    je eval_not
    cmp rax, ND_AND
    je eval_and
    cmp rax, ND_OR
    je eval_or
    cmp rax, ND_CALL
    je eval_call
    cmp rax, ND_STR
    je eval_str
    cmp rax, ND_READ
    je eval_read
    cmp rax, ND_PUTCHAR
    je eval_putchar
    cmp rax, ND_GETCHAR
    je eval_getchar
    cmp rax, ND_FLOAT
    je eval_float
    cmp rax, ND_LIST_CALL
    je eval_list_call
    cmp rax, ND_LEN
    je eval_len
    cmp rax, ND_PUSH
    je eval_push
    cmp rax, ND_POP
    je eval_pop
    cmp rax, ND_INDEX
    je eval_index
    cmp rax, ND_TYPE
    je eval_type
    cmp rax, ND_INT2STR
    je eval_int2str
    cmp rax, ND_FLOAT2STR
    je eval_float2str
    cmp rax, ND_STR2INT
    je eval_str2int
    cmp rax, ND_STR2FLOAT
    je eval_str2float
    cmp rax, ND_INT2FLOAT
    je eval_int2float
    cmp rax, ND_FLOAT2INT
    je eval_float2int
    cmp rax, ND_BOOL2INT
    je eval_bool2int
    cmp rax, ND_INT2BOOL
    je eval_int2bool
    cmp rax, ND_CONCAT
    je eval_concat
    cmp rax, ND_CHAR
    je eval_char
    cmp rax, ND_STR_GET
    je eval_str_get
    cmp rax, ND_STR_SET
    je eval_str_set
    cmp rax, ND_FLOOR
    je eval_floor
    cmp rax, ND_SQRT
    je eval_sqrt
    cmp rax, ND_EXP
    je eval_exp
    cmp rax, ND_LOG
    je eval_log
    jmp die_parse_error

eval_num:
    mov rax, [node_a + r12*8]
    jmp eval_out

eval_float:
    mov rax, [node_a + r12*8]
    jmp eval_out

eval_str:
    mov rdi, [node_a + r12*8]
    call make_str
    jmp eval_out

eval_read:
    call read_int
    shl rax, 3
    jmp eval_out

eval_putchar:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    sar rdi, 3
    call putchar_int
    shl rax, 3
    jmp eval_out

eval_getchar:
    call getchar_tagged
    jmp eval_out

eval_var:
    mov rax, [node_a + r12*8]     # sym_id
    mov rbx, [call_depth]
    imul rcx, rbx, MAXSYM
    add rcx, rax
    mov rax, [call_stack + rcx*8]
    jmp eval_out

eval_neg:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call builtin_neg
    jmp eval_out

eval_not:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    xor rax, 8
    jmp eval_out

eval_add:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_add
    jmp eval_out

eval_sub:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_sub
    jmp eval_out

eval_mul:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_mul
    jmp eval_out

eval_div:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_div
    jmp eval_out

eval_mod:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_mod
    jmp eval_out

eval_eq:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_eq
    jmp eval_out

eval_ne:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_ne
    jmp eval_out

eval_lt:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_lt
    jmp eval_out

eval_gt:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_gt
    jmp eval_out

eval_le:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_le
    jmp eval_out

eval_ge:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_ge
    jmp eval_out

eval_and:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    je eval_and_false
    mov rdi, [node_b + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    jmp eval_out
eval_and_false:
    mov rax, BOOL_FALSE
    jmp eval_out

eval_or:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    jne eval_or_true
    mov rdi, [node_b + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    jmp eval_out
eval_or_true:
    mov rax, BOOL_TRUE
    jmp eval_out

eval_list_call:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    xor rbp, rbp
    mov r13, [node_b + r12*8]
eval_list_call_args:
    test r13, r13
    jz eval_list_call_args_done
    mov rdi, r13
    call eval
    push rax
    inc rbp
    mov r13, [node_next + r13*8]
    jmp eval_list_call_args
eval_list_call_args_done:
    mov rdi, rbp
    call list_make
    lea rsp, [rsp + rbp*8]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

eval_len:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call builtin_len
    jmp eval_out

eval_push:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call list_push
    jmp eval_out

eval_pop:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call list_pop
    jmp eval_out

eval_index:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call builtin_index
    jmp eval_out

eval_type:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call builtin_type
    jmp eval_out

eval_int2str:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call int2str_builtin
    jmp eval_out

eval_float2str:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call float2str_builtin
    jmp eval_out

eval_str2int:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call str2int
    jmp eval_out

eval_str2float:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call str2float
    jmp eval_out

eval_int2float:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call int_to_float_tagged
    jmp eval_out

eval_float2int:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call float2int_builtin
    jmp eval_out

eval_bool2int:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call bool2int_builtin
    jmp eval_out

eval_int2bool:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call int2bool_builtin
    jmp eval_out

eval_concat:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    xor rbp, rbp
    mov r13, [node_b + r12*8]
eval_concat_args:
    test r13, r13
    jz eval_concat_args_done
    mov rdi, r13
    call eval
    push rax
    inc rbp
    mov r13, [node_next + r13*8]
    jmp eval_concat_args
eval_concat_args_done:
    mov rdi, rbp
    call str_concat_all
    lea rsp, [rsp + rbp*8]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

eval_char:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call char_of_int
    jmp eval_out

eval_str_get:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call str_index
    jmp eval_out

eval_str_set:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rcx, rax
    mov rdi, [node_c + r12*8]
    call eval
    mov rdx, rax
    mov rdi, rbx
    mov rsi, rcx
    call str_set
    jmp eval_out

eval_floor:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call floor_builtin
    jmp eval_out

eval_sqrt:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call sqrt_builtin
    jmp eval_out

eval_exp:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call exp_builtin
    jmp eval_out

eval_log:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call log_builtin
    jmp eval_out

# eval_call: node_a = fn_sym_id, node_b = first arg node (0 if none)
eval_call:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    mov r14, [node_a + r12*8] # function symbol ID
    xor rbx, rbx
    mov r15, [fn_n]
eval_call_lookup:
    cmp rbx, r15
    jge die_undef_fn
    cmp [fn_sym + rbx*8], r14
    je eval_call_found
    inc rbx
    jmp eval_call_lookup
eval_call_found:
    # rbx = function index
    mov r13, [node_b + r12*8] # first arg node
    xor rbp, rbp              # number of arguments pushed
eval_call_eval_args:
    test r13, r13
    jz eval_call_args_done
    mov rdi, r13
    call eval
    push rax                  # push evaluated argument
    inc rbp
    mov r13, [node_next + r13*8]
    jmp eval_call_eval_args
eval_call_args_done:
    # JIT fast path: call the native code if this function was compiled.
    # rbx = fn index, rbp = number of arguments pushed (rsp = last arg).
    mov rax, [fn_jit + rbx*8]
    test rax, rax
    jz eval_call_interp
    test rbp, rbp
    jz eval_call_native_zero
    lea rdi, [rsp + rbp*8 - 8]    # argv: first argument
    jmp eval_call_native_call
eval_call_native_zero:
    mov rdi, rsp
eval_call_native_call:
    call rax
    lea rsp, [rsp + rbp*8]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out
eval_call_interp:
    # Check max call depth
    mov rax, [call_depth]
    cmp rax, MAXFRAMES - 1
    jge die_stackoverflow
    inc rax
    mov [call_depth], rax     # rax = new depth D
    # Zero out new frame variable storage
    imul rdi, rax, MAXSYM*8
    lea rdi, [call_stack + rdi]
    xor rax, rax
    mov rcx, MAXSYM
    rep stosq
    # Pop evaluated arguments into new frame
    mov rcx, rbp
eval_call_pop_args:
    test rcx, rcx
    jz eval_call_pop_done
    dec rcx
    pop rax                   # rax = argument value
    cmp rcx, [fn_param_count + rbx*8]
    jge eval_call_pop_args    # ignore excess args
    imul r8, rbx, MAXPARAMS
    add r8, rcx
    mov r8, [fn_param_syms + r8*8] # r8 = param symbol ID
    mov r9, [call_depth]
    imul r9, r9, MAXSYM
    add r9, r8
    mov [call_stack + r9*8], rax
    jmp eval_call_pop_args
eval_call_pop_done:
    mov qword ptr [return_val], 0
    mov rdi, [fn_body + rbx*8]
    call exec_list
    dec qword ptr [call_depth]
    mov rax, [return_val]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

die_undef_fn:
    lea rdi, [msg_undef_fn]
    mov rsi, msg_undef_fn_len
    call die

die_stackoverflow:
    lea rdi, [msg_stackoverflow]
    mov rsi, msg_stackoverflow_len
    call die

eval_out:
    pop r12
    pop rbx
    ret

# ------------------------------------------------------------- executor --
# exec_list: rdi = index of first statement in a block (0 = empty)
# Returns rax: 0 = OK, 1 = BREAK, 2 = CONTINUE, 3 = RETURN
exec_list:
    push rbx
    mov rbx, rdi
    xor rax, rax
exec_list_loop:
    test rbx, rbx
    jz exec_list_done
    mov rdi, rbx
    call exec_stmt
    test rax, rax
    jnz exec_list_done
    mov rbx, [node_next + rbx*8]
    jmp exec_list_loop
exec_list_done:
    pop rbx
    ret

# exec_stmt: rdi = statement node index
# Returns rax: 0 = OK, 1 = BREAK, 2 = CONTINUE, 3 = RETURN
exec_stmt:
    push rbx
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_ASSIGN
    je exec_stmt_assign
    cmp rax, ND_PRINT
    je exec_stmt_print
    cmp rax, ND_IF
    je exec_stmt_if
    cmp rax, ND_WHILE
    je exec_stmt_while_check
    cmp rax, ND_BREAK
    je exec_stmt_break
    cmp rax, ND_CONTINUE
    je exec_stmt_continue
    cmp rax, ND_FN
    je exec_stmt_fn
    cmp rax, ND_RETURN
    je exec_stmt_return
    cmp rax, ND_EXPR_STMT
    je exec_stmt_expr
    cmp rax, ND_IMPORT
    je exec_stmt_fn
    cmp rax, ND_VAR_DECL
    je exec_stmt_var_decl
    cmp rax, ND_INDEX_ASSIGN
    je exec_stmt_index_assign
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_var_decl:
    mov rdi, [node_b + r12*8]
    call eval
    mov rcx, [node_a + r12*8]
    mov r8, [call_depth]
    imul rdx, r8, MAXSYM
    add rdx, rcx
    mov [call_stack + rdx*8], rax
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_assign:
    mov rdi, [node_b + r12*8]
    call eval
    mov rcx, [node_a + r12*8]
    cmp qword ptr [sym_mutable + rcx*8], 1
    je exec_stmt_assign_imm
    mov r8, [call_depth]
    imul rdx, r8, MAXSYM
    add rdx, rcx
    mov [call_stack + rdx*8], rax
    xor rax, rax
    jmp exec_stmt_done
exec_stmt_assign_imm:
    lea rdi, [msg_imm]
    mov rsi, msg_imm_len
    call die

exec_stmt_index_assign:
    mov rdi, [node_c + r12*8]
    call eval
    mov rcx, rax              # index
    mov rdi, [node_b + r12*8]
    call eval
    mov rdx, rax              # value
    mov rax, [node_a + r12*8] # sym id
    mov r8, [call_depth]
    imul r8, r8, MAXSYM
    add r8, rax
    mov rdi, [call_stack + r8*8]   # current target value
    mov rbx, rdi
    and rbx, 7
    cmp rbx, TAG_LIST
    jne exec_stmt_index_assign_bad
    mov rsi, rcx
    call list_index_assign
    xor rax, rax
    jmp exec_stmt_done
exec_stmt_index_assign_bad:
    jmp die_type_err

exec_stmt_print:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call print_value
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_if:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    je exec_stmt_else
    mov rdi, [node_b + r12*8]
    call exec_list
    jmp exec_stmt_done
exec_stmt_else:
    mov rdi, [node_c + r12*8]
    call exec_list
    jmp exec_stmt_done

exec_stmt_while_check:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    je exec_stmt_while_done_ok
    mov rdi, [node_b + r12*8]
    call exec_list
    cmp rax, 1                 # STATUS_BREAK
    je exec_stmt_while_done_ok
    cmp rax, 3                 # STATUS_RETURN
    je exec_stmt_done          # propagate return out of while immediately
    # STATUS_CONTINUE (2) or STATUS_OK (0): loop again
    jmp exec_stmt_while_check
exec_stmt_while_done_ok:
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_break:
    mov rax, 1
    jmp exec_stmt_done

exec_stmt_continue:
    mov rax, 2
    jmp exec_stmt_done

exec_stmt_fn:
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_return:
    mov rdi, [node_a + r12*8]
    test rdi, rdi
    jz exec_stmt_return_zero
    call eval
    mov [return_val], rax
    mov rax, 3                 # STATUS_RETURN
    jmp exec_stmt_done
exec_stmt_return_zero:
    mov qword ptr [return_val], 0
    mov rax, 3                 # STATUS_RETURN
    jmp exec_stmt_done

exec_stmt_expr:
    mov rdi, [node_a + r12*8]
    call eval
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_done:
    pop r12
    pop rbx
    ret

# ==================================================== runtime type helpers ==
# Called from the interpreter (eval/exec) AND from JIT-generated code.
# ABI: preserve rbx/r12-r15 and r8 (argv pointer in JIT frames); rax, rcx,
# rdx, rdi, rsi, r9-r11 are scratch.
# ---------------------------------------------------------------------------

die_type_err:
    lea rdi, [msg_type]
    mov rsi, msg_type_len
    call die

# heap_alloc: rdi = size -> rax = 16-byte-aligned bump pointer (new mmap chunk on demand)
heap_alloc:
    push rbx
    push r8
    lea rbx, [rdi + 15]
    and rbx, -16
    mov rax, [heap_pos]
    lea rcx, [rax + rbx]
    cmp rcx, [heap_end]
    jle heap_alloc_fit
    xor edi, edi
    mov esi, HEAP_CHUNK
    mov edx, 3                  # PROT_READ|PROT_WRITE
    mov r10d, 0x22              # MAP_PRIVATE|MAP_ANONYMOUS
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    js heap_alloc_fail
    mov [heap_base], rax
    mov [heap_pos], rax
    lea rcx, [rax + HEAP_CHUNK]
    mov [heap_end], rcx
heap_alloc_fit:
    mov rax, [heap_pos]
    lea rcx, [rax + rbx]
    mov [heap_pos], rcx
    pop r8
    pop rbx
    ret
heap_alloc_fail:
    lea rdi, [msg_oom]
    mov rsi, msg_oom_len
    call die

# to_fp: rdi = tagged value -> xmm0 = double (int promoted, float untagged)
to_fp:
    mov rax, rdi
    and rax, 7
    cmp rax, 1
    je to_fp_float
    test rax, rax
    jnz die_type_err
    sar rdi, 3
    cvtsi2sd xmm0, rdi
    ret
to_fp_float:
    mov rax, rdi
    and rax, -8
    movq xmm0, rax
    ret

# float_tag: xmm0 = double -> rax = tagged float
float_tag:
    movq rax, xmm0
    and rax, -8
    or rax, 1
    ret

# int_to_float_tagged: rdi = tagged int -> rax = tagged float
int_to_float_tagged:
    sar rdi, 3
    cvtsi2sd xmm0, rdi
    jmp float_tag

# builtin_neg: rdi = value -> rax = negated value (int or float)
builtin_neg:
    push r8
    mov rax, rdi
    test rax, 1
    jnz builtin_neg_f
    neg rax
    pop r8
    ret
builtin_neg_f:
    xor rax, [qword_sign_mask]
    pop r8
    ret

# builtin_len: rdi = str or list -> rax = tagged int length
builtin_len:
    push r8
    mov rax, rdi
    and rax, 7
    cmp rax, 3
    je builtin_len_str
    call list_len
    pop r8
    ret
builtin_len_str:
    call str_len
    pop r8
    ret

# builtin_index: rdi = str or list, rsi = tagged idx -> rax = value
builtin_index:
    push r8
    mov rax, rdi
    and rax, 7
    cmp rax, 3
    je builtin_index_str
    call list_index
    pop r8
    ret
builtin_index_str:
    call str_index
    pop r8
    ret

# is_truthy: rdi = value -> rax = BOOL_TRUE / BOOL_FALSE
is_truthy:
    mov rax, rdi
    and rax, 7
    cmp rax, 2
    jne is_truthy_not_bool
    cmp rdi, BOOL_FALSE
    je is_truthy_false
    mov rax, BOOL_TRUE
    ret
is_truthy_not_bool:
    test rdi, rdi
    jz is_truthy_false
    mov rax, BOOL_TRUE
    ret
is_truthy_false:
    mov rax, BOOL_FALSE
    ret

# bin_add/bin_sub/bin_mul/bin_div/bin_mod: rdi = a, rsi = b -> rax
# +: dispatch on type: string+string -> concat, else int/float arithmetic.
# -, *, /, %: int/float arithmetic on the v<<3 / float encodings.
bin_add:
    mov rax, rdi
    and rax, 7
    cmp rax, TAG_STR
    jne bin_add_intfloat
    mov rax, rsi
    and rax, 7
    cmp rax, TAG_STR
    jne die_type_err
    call str_concat
    ret
bin_add_intfloat:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_fp_add
    lea rax, [rdi + rsi]
    ret
bin_sub:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_fp_sub
    mov rax, rdi
    sub rax, rsi
    ret
bin_mul:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_fp_mul
    sar rdi, 3
    sar rsi, 3
    mov rax, rdi
    imul rax, rsi
    shl rax, 3
    ret
bin_div:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_fp_div
    sar rdi, 3
    sar rsi, 3
    test rsi, rsi
    jnz bin_div_ok
    lea rdi, [msg_divzero]
    mov rsi, msg_divzero_len
    call die
bin_div_ok:
    mov rax, rdi
    cqo
    idiv rsi
    shl rax, 3
    ret
bin_mod:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz die_type_err
    sar rdi, 3
    sar rsi, 3
    test rsi, rsi
    jnz bin_mod_ok
    lea rdi, [msg_divzero]
    mov rsi, msg_divzero_len
    call die
bin_mod_ok:
    mov rax, rdi
    cqo
    idiv rsi
    mov rax, rdx
    shl rax, 3
    ret

bin_fp_add:
    push rbx
    push r8
    mov rbx, rsi
    call to_fp
    movsd xmm1, xmm0
    mov rdi, rbx
    call to_fp
    addsd xmm0, xmm1
    pop r8
    pop rbx
    jmp float_tag
bin_fp_sub:
    push rbx
    push r8
    mov rbx, rsi
    call to_fp
    movsd xmm1, xmm0
    mov rdi, rbx
    call to_fp
    subsd xmm1, xmm0
    movsd xmm0, xmm1
    pop r8
    pop rbx
    jmp float_tag
bin_fp_mul:
    push rbx
    push r8
    mov rbx, rsi
    call to_fp
    movsd xmm1, xmm0
    mov rdi, rbx
    call to_fp
    mulsd xmm0, xmm1
    pop r8
    pop rbx
    jmp float_tag
bin_fp_div:
    push rbx
    push r8
    mov rbx, rsi
    call to_fp
    movsd xmm1, xmm0
    mov rdi, rbx
    call to_fp
    divsd xmm1, xmm0
    movsd xmm0, xmm1
    pop r8
    pop rbx
    jmp float_tag

# bin_fp_cmp: rdi = a, rsi = b -> flags of ucomisd xmm0(a), xmm1(b)
bin_fp_cmp:
    push rbx
    push r8
    mov rbx, rsi
    call to_fp
    movsd xmm1, xmm0
    mov rdi, rbx
    call to_fp
    ucomisd xmm1, xmm0
    pop r8
    pop rbx
    ret

bin_eq:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_eq_fp
    cmp rdi, rsi
    sete al
    jmp bin_boolize
bin_eq_fp:
    call bin_fp_cmp
    sete al
    jmp bin_boolize
bin_ne:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_ne_fp
    cmp rdi, rsi
    setne al
    jmp bin_boolize
bin_ne_fp:
    call bin_fp_cmp
    setne al
    jmp bin_boolize
bin_lt:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_lt_fp
    cmp rdi, rsi
    setl al
    jmp bin_boolize
bin_lt_fp:
    call bin_fp_cmp
    setb al
    jmp bin_boolize
bin_gt:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_gt_fp
    cmp rdi, rsi
    setg al
    jmp bin_boolize
bin_gt_fp:
    call bin_fp_cmp
    seta al
    jmp bin_boolize
bin_le:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_le_fp
    cmp rdi, rsi
    setle al
    jmp bin_boolize
bin_le_fp:
    call bin_fp_cmp
    setbe al
    jmp bin_boolize
bin_ge:
    mov rax, rdi
    or rax, rsi
    test rax, 1
    jnz bin_ge_fp
    cmp rdi, rsi
    setge al
    jmp bin_boolize
bin_ge_fp:
    call bin_fp_cmp
    setae al
bin_boolize:
    movzx rax, al
    shl rax, 3
    or rax, BOOL_FALSE
    ret

# getchar_tagged: rax = tagged int char code (-1 as tagged -8 on EOF)
getchar_tagged:
    call getchar_int
    cmp rax, -1
    je getchar_tagged_eof
    shl rax, 3
    ret
getchar_tagged_eof:
    mov rax, -8
    ret

# fmt_int: rdi = tagged int -> rax = ptr to digits, rdx = length (no newline)
fmt_int:
    push rbx
    push r12
    push r13
    sar rdi, 3
    mov r12, rdi
    lea r13, [digitbuf + 31]
    mov rax, r12
    test rax, rax
    jns fmt_int_mag
    neg rax
fmt_int_mag:
fmt_int_loop:
    xor rdx, rdx
    mov rcx, 10
    div rcx
    add dl, '0'
    dec r13
    mov [r13], dl
    test rax, rax
    jnz fmt_int_loop
    cmp r12, 0
    jge fmt_int_out
    dec r13
    mov byte ptr [r13], '-'
fmt_int_out:
    lea rax, [digitbuf + 31]
    sub rax, r13
    mov rdx, rax
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

# make_str: rdi = str_id -> rax = tagged str value (heap copy)
make_str:
    push rbx
    push r12
    push r13
    push r8
    mov r12, rdi
    mov r13, [str_pool_len + r12*8]
    lea rdi, [r13 + 9]
    call heap_alloc
    mov rbx, rax
    mov [rbx], r13
    lea rdi, [rbx + 8]
    mov rsi, [str_pool_ptr + r12*8]
    mov rcx, r13
    rep movsb
    mov byte ptr [rdi], 0
    lea rax, [rbx + 3]
    pop r8
    pop r13
    pop r12
    pop rbx
    ret

# fmt_float: rdi = tagged float, rsi = output buffer -> rax = ptr, rdx = len
fmt_float:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r8
    mov r9, rsi               # out start
    mov r12, rsi              # out cursor
    mov r13, rdi              # keep tagged
    test rdi, [qword_sign_mask]
    jz fmt_float_nosign
    mov byte ptr [r12], '-'
    inc r12
    mov rdi, r13
    and rdi, [qword_frac_mask]
fmt_float_nosign:
    call to_fp
    movq rax, xmm0
    test rax, rax
    jnz fmt_float_nz
    mov byte ptr [r12], '0'
    inc r12
    mov rax, r12
    mov rdx, rax
    sub rdx, rsi
    mov rax, rsi
    jmp fmt_float_out
fmt_float_nz:
    mov r14, rax
    and r14, [qword_exp_mask]
    cmp r14, [qword_exp_mask]
    jne fmt_float_finite
    # inf / nan
    mov r14, rax
    and r14, [qword_mant_mask]
    test r14, r14
    jnz fmt_float_nan
    mov rax, 'f'
    mov [r12], rax
    mov rax, 'n'
    mov [r12+1], rax
    add r12, 2
    jmp fmt_float_strout
fmt_float_nan:
    mov rax, 'n'
    mov [r12], rax
    mov rax, 'a'
    mov [r12+1], rax
    mov rax, 'n'
    mov [r12+2], rax
    add r12, 3
fmt_float_strout:
    mov rax, r12
    mov rdx, rax
    sub rdx, rsi
    mov rax, rsi
    jmp fmt_float_out
fmt_float_finite:
    # normalize x into [1,10), r14 = decimal exponent
    xor r14, r14
fmt_float_norm_hi:
    movsd xmm1, [f_const_10]
    comisd xmm0, xmm1
    jb fmt_float_norm_lo
    divsd xmm0, xmm1
    inc r14
    jmp fmt_float_norm_hi
fmt_float_norm_lo:
    movsd xmm1, [f_const_1]
    comisd xmm0, xmm1
    jae fmt_float_norm_done
    movsd xmm1, [f_const_10]
    mulsd xmm0, xmm1
    dec r14
    jmp fmt_float_norm_lo
fmt_float_norm_done:
    # digits[0..15] = 16 significant digits
    lea r15, [digitbuf]
    xor rbx, rbx
fmt_float_digits:
    cmp rbx, 16
    jge fmt_float_round
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    add al, '0'
    mov [r15 + rbx], al
    subsd xmm0, xmm1
    mulsd xmm0, [f_const_10]
    inc rbx
    jmp fmt_float_digits
fmt_float_round:
    mov al, [r15 + 15]
    cmp al, '5'
    jl fmt_float_strip
    mov rbx, 14
fmt_float_round_loop:
    cmp rbx, 0
    jl fmt_float_round_carry
    mov al, [r15 + rbx]
    cmp al, '9'
    jne fmt_float_round_inc
    mov byte ptr [r15 + rbx], '0'
    dec rbx
    jmp fmt_float_round_loop
fmt_float_round_inc:
    inc al
    mov [r15 + rbx], al
    jmp fmt_float_strip
fmt_float_round_carry:
    mov byte ptr [r15], '1'
    inc r14
fmt_float_strip:
    mov rbx, 14
fmt_float_strip_loop:
    cmp rbx, 0
    jl fmt_float_emit
    cmp byte ptr [r15 + rbx], '0'
    jne fmt_float_emit
    dec rbx
    jmp fmt_float_strip_loop
fmt_float_emit:
    # rbx = last significant digit index; decide notation
    cmp r14, -4
    jl fmt_float_sci
    cmp r14, 15
    jge fmt_float_sci
    test r14, r14
    js fmt_float_fixed_neg
    # integer part: digits[0..e10]
    mov rcx, r14
    inc rcx
    lea rsi, [r15]
    lea rdi, [r12]
    call fmt_float_copy
    add r12, rcx
    mov rax, r14
    cmp rax, rbx
    jge fmt_float_emit_dot0
    mov byte ptr [r12], '.'
    inc r12
    lea rsi, [r15 + rax + 1]
    mov rcx, rbx
    sub rcx, rax
    lea rdi, [r12]
    call fmt_float_copy
    add r12, rcx
    jmp fmt_float_out_prep
fmt_float_emit_dot0:
    mov byte ptr [r12], '.'
    inc r12
    mov byte ptr [r12], '0'
    inc r12
    jmp fmt_float_out_prep
fmt_float_fixed_neg:
    mov byte ptr [r12], '0'
    inc r12
    mov byte ptr [r12], '.'
    inc r12
    mov rax, r14
    neg rax
    dec rax
    mov rcx, rax
fmt_float_zeros:
    test rcx, rcx
    jle fmt_float_fixed_frac
    mov byte ptr [r12], '0'
    inc r12
    dec rcx
    jmp fmt_float_zeros
fmt_float_fixed_frac:
    lea rsi, [r15]
    lea rdi, [r12]
    mov rcx, rbx
    inc rcx
    call fmt_float_copy
    add r12, rcx
    jmp fmt_float_out_prep
fmt_float_sci:
    lea rsi, [r15]
    lea rdi, [r12]
    mov rcx, 1
    call fmt_float_copy
    add r12, 1
    cmp rbx, 0
    jle fmt_float_sci_e
    mov byte ptr [r12], '.'
    inc r12
    lea rsi, [r15 + 1]
    mov rcx, rbx
    lea rdi, [r12]
    call fmt_float_copy
    add r12, rcx
fmt_float_sci_e:
    mov byte ptr [r12], 'e'
    inc r12
    mov rdi, r14
    call fmt_int
    push rdx
    lea rdi, [r12]
    mov rsi, rax
    mov rcx, rdx
    call fmt_float_copy
    pop rcx
    add r12, rcx
fmt_float_out_prep:
    mov rax, r9               # out start (saved at entry)
    mov rdx, r12
    sub rdx, rax
fmt_float_out:
    pop r8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# fmt_float_copy: rsi = src, rdi = dst, rcx = count (preserved)
fmt_float_copy:
    push rdx
    mov rdx, rcx
fmt_float_copy_loop:
    test rdx, rdx
    jz fmt_float_copy_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp fmt_float_copy_loop
fmt_float_copy_done:
    pop rdx
    ret

# print_float: rdi = tagged float -> prints value + newline
print_float:
    push rbx
    push r8
    lea rsi, [fmtbuf]
    call fmt_float
    mov rdi, rax
    mov rsi, rdx
    call write_str
    pop r8
    pop rbx
    ret

# print_value: rdi = value -> prints representation + newline
print_value:
    call print_value_repr
    lea rdi, [msg_newline]
    mov rsi, 1
    call write_str
    ret

print_value_repr:
    push rbx
    push r12
    push r13
    push r14
    push r8
    mov r12, rdi
    mov rax, rdi
    and rax, 7
    cmp rax, 0
    je print_value_int
    cmp rax, 1
    je print_value_float
    cmp rax, 2
    je print_value_bool
    cmp rax, 3
    je print_value_str
    cmp rax, 4
    je print_value_list
    jmp die_type_err
print_value_int:
    mov rdi, r12
    sar rdi, 3
    call print_int
    jmp print_value_done
print_value_float:
    mov rdi, r12
    call print_float
    jmp print_value_done
print_value_bool:
    cmp r12, BOOL_FALSE
    je print_value_false
    lea rdi, [msg_true]
    mov rsi, msg_true_len
    call write_str
    jmp print_value_done
print_value_false:
    lea rdi, [msg_false]
    mov rsi, msg_false_len
    call write_str
    jmp print_value_done
print_value_str:
    mov rax, r12
    and rax, -8
    mov rdx, [rax]
    lea rdi, [rax + 8]
    mov rsi, rdx
    call write_str
    jmp print_value_done
print_value_list:
    lea rdi, [msg_lbracket]
    mov rsi, msg_lbracket_len
    call write_str
    mov rax, r12
    and rax, -8
    mov rbx, rax
    mov r13, [rbx + 8]
    xor r14, r14
print_value_list_loop:
    cmp r14, r13
    jge print_value_list_close
    test r14, r14
    jz print_value_list_item
    lea rdi, [msg_comma]
    mov rsi, msg_comma_len
    call write_str
print_value_list_item:
    mov rdi, [rbx + 16 + r14*8]
    call print_value_repr
    inc r14
    jmp print_value_list_loop
print_value_list_close:
    lea rdi, [msg_rbracket]
    mov rsi, msg_rbracket_len
    call write_str
print_value_done:
    pop r8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# list_make: rdi = n, args on stack (arg1 deepest) -> rax = tagged list
# Allocates with slack capacity (min 4) so push can mutate in place.
list_make:
    push rbx
    push r12
    push r13
    push r8
    mov r12, rdi
    mov rax, r12
    cmp rax, 4
    jge list_make_cap_ok
    mov rax, 4
list_make_cap_ok:
    lea rdi, [rax*8 + 16]
    call heap_alloc
    mov rbx, rax
    mov [rbx], rax            # cap
    mov [rbx+8], r12          # len
    lea rsi, [rsp + 32 + r12*8]
    lea r13, [rbx + 16]
    xor rcx, rcx
list_make_loop:
    cmp rcx, r12
    jge list_make_done
    mov rax, [rsi]
    mov [r13 + rcx*8], rax
    sub rsi, 8
    inc rcx
    jmp list_make_loop
list_make_done:
    lea rax, [rbx + TAG_LIST]
    pop r8
    pop r13
    pop r12
    pop rbx
    ret

# list_push: rdi = list, rsi = val -> rax = list (may be a new object after growth)
list_push:
    push rbx
    push r12
    push r13
    push r14
    push r8
    mov r14, rsi
    mov rbx, rdi
    and rbx, -8
    mov r12, [rbx]            # cap
    mov r13, [rbx+8]          # len
    cmp r13, r12
    jl list_push_fit
    lea r12, [r12*2]
    cmp r12, 4
    jge list_push_grow_ok
    mov r12, 4
list_push_grow_ok:
    lea rdi, [r12*8 + 16]
    call heap_alloc
    mov rdx, rax
    mov rax, [rbx+8]
    mov [rdx], r12
    mov [rdx+8], rax
    lea rdi, [rdx + 16]
    lea rsi, [rbx + 16]
    mov rcx, rax
    shl rcx, 3
    rep movsb
    mov rbx, rdx
list_push_fit:
    mov [rbx + 16 + r13*8], r14
    inc r13
    mov [rbx+8], r13
    lea rax, [rbx + TAG_LIST]
    pop r8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# list_pop: rdi = list -> rax = value (dies on empty)
list_pop:
    push rbx
    push r8
    mov rbx, rdi
    and rbx, -8
    mov rax, [rbx+8]
    test rax, rax
    jnz list_pop_ok
    lea rdi, [msg_empty]
    mov rsi, msg_empty_len
    call die
list_pop_ok:
    mov rdx, rax
    dec rax
    mov [rbx+8], rax
    dec rdx
    mov rax, [rbx + 16 + rdx*8]
    pop r8
    pop rbx
    ret

# list_len: rdi = list -> rax = tagged int length
list_len:
    push r8
    mov rax, rdi
    and rax, -8
    mov rax, [rax+8]
    shl rax, 3
    pop r8
    ret

# list_index: rdi = list, rsi = tagged idx -> rax = value (dies OOB)
list_index:
    push rbx
    push r8
    mov rbx, rdi
    and rbx, -8
    sar rsi, 3
    cmp rsi, 0
    jl list_index_oob
    cmp rsi, [rbx+8]
    jge list_index_oob
    mov rax, [rbx + 16 + rsi*8]
    pop r8
    pop rbx
    ret
list_index_oob:
    lea rdi, [msg_idx]
    mov rsi, msg_idx_len
    call die

# list_index_assign: rdi = list, rsi = tagged idx, rdx = val (dies OOB)
list_index_assign:
    push rbx
    push r8
    mov rbx, rdi
    and rbx, -8
    sar rsi, 3
    cmp rsi, 0
    jl list_index_assign_oob
    cmp rsi, [rbx+8]
    jge list_index_assign_oob
    mov [rbx + 16 + rsi*8], rdx
    pop r8
    pop rbx
    ret
list_index_assign_oob:
    lea rdi, [msg_idx]
    mov rsi, msg_idx_len
    call die

# str_len: rdi = str -> rax = tagged int length
str_len:
    push r8
    mov rax, rdi
    and rax, -8
    mov rax, [rax]
    shl rax, 3
    pop r8
    ret

# str_index: rdi = str, rsi = tagged idx -> rax = tagged 1-char str
str_index:
    push rbx
    push r8
    mov rbx, rdi
    and rbx, -8
    sar rsi, 3
    cmp rsi, 0
    jl str_index_oob
    cmp rsi, [rbx]
    jge str_index_oob
    movzx eax, byte ptr [rbx + 8 + rsi]   # the char byte
    mov rbx, rax                          # preserve char across heap_alloc
    mov rdi, 10
    call heap_alloc                        # rax = new 10-byte buffer
    mov qword ptr [rax], 1                 # length = 1
    mov [rax + 8], bl                      # store char
    mov byte ptr [rax + 9], 0              # NUL terminator
    lea rax, [rax + TAG_STR]
    pop r8
    pop rbx
    ret
str_index_oob:
    lea rdi, [msg_idx]
    mov rsi, msg_idx_len
    call die

# str_concat: rdi = str a, rsi = str b -> rax = new str
str_concat:
    push rbx
    push r12
    push r13
    push r14
    push r8
    mov r12, rdi
    mov r13, rsi
    mov rax, r12
    and rax, -8
    mov rbx, [rax]            # len a
    mov rax, r13
    and rax, -8
    mov r14, [rax]            # len b
    lea rdi, [rbx + r14 + 9]
    call heap_alloc
    mov rdx, rax              # hdr
    lea rax, [rbx + r14]
    mov [rdx], rax
    lea rdi, [rdx + 8]
    mov rax, r12
    and rax, -8
    lea rsi, [rax + 8]
    mov rcx, rbx
    rep movsb
    mov rax, r13
    and rax, -8
    lea rsi, [rax + 8]
    mov rcx, r14
    rep movsb
    mov byte ptr [rdi], 0
    lea rax, [rdx + TAG_STR]
    pop r8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# str_concat_all: rdi = n, args on stack (arg1 deepest) -> rax = new str
# Concatenates n strings. Dies with a type error if any arg is not a string.
str_concat_all:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    push r8
    mov r12, rdi              # n
    test r12, r12
    jz str_concat_all_empty
    # First pass: sum lengths and validate every arg is a string.
    xor r13, r13              # total length
    xor r14, r14              # i
    mov r15, r12
    shl r15, 3               # n*8
str_concat_all_len_loop:
    cmp r14, r12
    jge str_concat_all_len_done
    mov rax, [rsp + 56 + r15]
    sub r15, 8
    mov rbx, rax
    and rbx, 7
    cmp rbx, TAG_STR
    jne str_concat_all_type_err
    and rax, -8
    add r13, [rax]            # += string length
    inc r14
    jmp str_concat_all_len_loop
str_concat_all_len_done:
    lea rdi, [r13 + 9]
    call heap_alloc
    mov rbp, rax              # buffer header
    lea rdi, [rbp + 8]        # dest pointer
    xor r14, r14
    mov r15, r12
    shl r15, 3
str_concat_all_copy_loop:
    cmp r14, r12
    jge str_concat_all_done
    mov rax, [rsp + 56 + r15]
    sub r15, 8
    and rax, -8
    mov rbx, [rax]            # src length
    lea rsi, [rax + 8]        # src pointer
    mov rcx, rbx              # count
    rep movsb
    inc r14
    jmp str_concat_all_copy_loop
str_concat_all_done:
    mov byte ptr [rdi], 0
    lea rax, [rbp + TAG_STR]
    pop r8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
str_concat_all_empty:
    mov rdi, 9
    call heap_alloc
    mov qword ptr [rax], 0
    mov byte ptr [rax + 8], 0
    mov rbp, rax
    lea rdi, [rax + 8]
    jmp str_concat_all_done
str_concat_all_type_err:
    lea rdi, [msg_type]
    mov rsi, msg_type_len
    call die

# char_of_int: rdi = tagged int -> rax = 1-char str
char_of_int:
    push rbx
    push r8
    sar rdi, 3
    mov rbx, rdi
    mov rdi, 10
    call heap_alloc
    mov qword ptr [rax], 1
    mov [rax + 8], bl
    mov byte ptr [rax + 9], 0
    lea rax, [rax + TAG_STR]
    pop r8
    pop rbx
    ret

# str_set: rdi = str, rsi = tagged idx, rdx = 1-char str (or int codepoint) -> rax = new str
str_set:
    push rbx
    push r12
    push r13
    push r8
    push rdx
    mov r12, rdi
    mov r13, rsi
    sar r13, 3
    mov rax, r12
    and rax, -8
    mov rbx, [rax]
    cmp r13, 0
    jl str_set_oob
    cmp r13, rbx
    jge str_set_oob
    lea rdi, [rbx + 9]
    call heap_alloc
    mov rcx, rax
    mov [rcx], rbx
    lea rdi, [rcx + 8]
    mov rax, r12
    and rax, -8
    lea rsi, [rax + 8]
    mov r9, rbx
str_set_copy_loop:
    test r9, r9
    jz str_set_copy_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec r9
    jmp str_set_copy_loop
str_set_copy_done:
    mov byte ptr [rdi], 0
    mov rdx, [rsp]                # new value (tagged)
    mov rax, rdx
    and rax, 7
    cmp rax, TAG_STR
    je str_set_from_str
    mov rax, rdx
    sar rax, 3                    # treat as int codepoint
    jmp str_set_store
str_set_from_str:
    mov rax, rdx
    and rax, -8
    movzx eax, byte ptr [rax + 8] # first char of the 1-char string
str_set_store:
    mov r9, r13
    mov [rcx + 8 + r9], al
    lea rax, [rcx + TAG_STR]
    add rsp, 8
    pop r8
    pop r13
    pop r12
    pop rbx
    ret
str_set_oob:
    add rsp, 8
    lea rdi, [msg_idx]
    mov rsi, msg_idx_len
    call die

# str2int: rdi = str -> rax = tagged int (0 if no digits)
str2int:
    push rbx
    push r12
    push r13
    push r14
    push r8
    mov rax, rdi
    and rax, -8
    mov rbx, [rax]
    lea r12, [rax + 8]
    xor r13, r13
    xor r14, r14
    xor rcx, rcx
str2int_skip_ws:
    cmp rcx, rbx
    jge str2int_done
    movzx eax, byte ptr [r12 + rcx]
    cmp al, ' '
    jne str2int_sign
    inc rcx
    jmp str2int_skip_ws
str2int_sign:
    cmp al, '-'
    jne str2int_plus
    mov r14, 1
    inc rcx
    jmp str2int_digits
str2int_plus:
    cmp al, '+'
    jne str2int_digits
    inc rcx
str2int_digits:
    cmp rcx, rbx
    jge str2int_done
    movzx eax, byte ptr [r12 + rcx]
    cmp al, '0'
    jl str2int_done
    cmp al, '9'
    jg str2int_done
    imul r13, r13, 10
    sub al, '0'
    movzx rax, al
    add r13, rax
    inc rcx
    jmp str2int_digits
str2int_done:
    mov rax, r13
    test r14, r14
    jz str2int_out
    neg rax
str2int_out:
    shl rax, 3
    pop r8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# str2float: rdi = str -> rax = tagged float (0.0 if no digits)
str2float:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r8
    mov rax, rdi
    and rax, -8
    mov rbx, [rax]
    lea r12, [rax + 8]
    xor r13, r13
    xor r14, r14
    xor r15, r15
    xor rcx, rcx
str2float_skip_ws:
    cmp rcx, rbx
    jge str2float_mk
    movzx eax, byte ptr [r12 + rcx]
    cmp al, ' '
    jne str2float_sign
    inc rcx
    jmp str2float_skip_ws
str2float_sign:
    cmp al, '-'
    jne str2float_plus
    mov r15, 1
    inc rcx
    jmp str2float_int
str2float_plus:
    cmp al, '+'
    jne str2float_int
    inc rcx
str2float_int:
    cmp rcx, rbx
    jge str2float_mk
    movzx eax, byte ptr [r12 + rcx]
    cmp al, '0'
    jl str2float_dot
    cmp al, '9'
    jg str2float_dot
    imul r13, r13, 10
    sub al, '0'
    movzx rax, al
    add r13, rax
    inc rcx
    jmp str2float_int
str2float_dot:
    cmp al, '.'
    jne str2float_mk
    inc rcx
str2float_frac:
    cmp rcx, rbx
    jge str2float_mk
    movzx eax, byte ptr [r12 + rcx]
    cmp al, '0'
    jl str2float_mk
    cmp al, '9'
    jg str2float_mk
    imul r13, r13, 10
    sub al, '0'
    movzx rax, al
    add r13, rax
    inc r14
    inc rcx
    jmp str2float_frac
str2float_mk:
    mov rdi, r13
    mov rsi, r14
    xor rdx, rdx
    call mk_float
    test r15, r15
    jz str2float_out
    xor rax, [qword_sign_mask]
str2float_out:
    pop r8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# builtin_type: rdi = value -> rax = tagged int 0..4
builtin_type:
    push r8
    mov rax, rdi
    and rax, 7
    shl rax, 3
    pop r8
    ret

# int2str_builtin: rdi = tagged int -> rax = tagged str
int2str_builtin:
    push rbx
    push r12
    push r13
    push r8
    call fmt_int
    mov r12, rax
    mov r13, rdx
    lea rdi, [r13 + 9]
    call heap_alloc
    mov rbx, rax
    mov [rbx], r13
    lea rdi, [rbx + 8]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte ptr [rdi], 0
    lea rax, [rbx + 3]
    pop r8
    pop r13
    pop r12
    pop rbx
    ret

# float2str_builtin: rdi = tagged float -> rax = tagged str
float2str_builtin:
    push rbx
    push r12
    push r13
    push r8
    lea rsi, [fmtbuf]
    call fmt_float
    mov r12, rax
    mov r13, rdx
    lea rdi, [r13 + 9]
    call heap_alloc
    mov rbx, rax
    mov [rbx], r13
    lea rdi, [rbx + 8]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte ptr [rdi], 0
    lea rax, [rbx + 3]
    pop r8
    pop r13
    pop r12
    pop rbx
    ret

# float2int_builtin: rdi = tagged float -> rax = tagged int (truncated)
float2int_builtin:
    push r8
    call to_fp
    cvttsd2si rax, xmm0
    shl rax, 3
    pop r8
    ret

# bool2int_builtin: rdi = tagged bool -> rax = tagged int
bool2int_builtin:
    push r8
    cmp rdi, BOOL_FALSE
    je bool2int_false
    mov rax, 8
    pop r8
    ret
bool2int_false:
    xor rax, rax
    pop r8
    ret

# int2bool_builtin: rdi = tagged int -> rax = tagged bool
int2bool_builtin:
    push r8
    test rdi, rdi
    jz int2bool_builtin_f
    mov rax, BOOL_TRUE
    pop r8
    ret
int2bool_builtin_f:
    mov rax, BOOL_FALSE
    pop r8
    ret

# floor_builtin: rdi = tagged float -> rax = tagged float (floor)
floor_builtin:
    push r8
    call to_fp
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    ucomisd xmm0, xmm1
    jae floor_builtin_done
    dec rax
floor_builtin_done:
    cvtsi2sd xmm0, rax
    pop r8
    jmp float_tag

# sqrt_builtin: rdi = tagged float -> rax = tagged float
sqrt_builtin:
    push r8
    call to_fp
    sqrtsd xmm0, xmm0
    pop r8
    jmp float_tag

# exp_builtin: rdi = tagged float -> rax = tagged float (e^x), via x87 log2/exp
exp_builtin:
    push r8
    call to_fp
    movq [f_tmp], xmm0
    fld qword ptr [f_tmp]    # st0 = x
    fldl2e                   # st0 = log2(e), st1 = x
    fmulp                    # st0 = x*log2(e) = v
    fld st(0)                # st0 = v, st1 = v
    frndint                  # st0 = N (integer part), st1 = v
    fsub st(1), st(0)        # st1 = f = v - N, st0 = N
    fxch st(1)               # st0 = f, st1 = N
    f2xm1                    # st0 = 2^f - 1
    fld1                     # st0 = 1, st1 = 2^f - 1
    faddp                    # st0 = 2^f
    fscale                   # st0 = 2^f * 2^N = e^x, st1 = N
    fstp st(1)               # drop N
    fstp qword ptr [f_tmp]
    movq xmm0, [f_tmp]
    pop r8
    jmp float_tag

# log_builtin: rdi = tagged float -> rax = tagged float (ln x)
log_builtin:
    push r8
    call to_fp
    movq [f_tmp], xmm0
    fldln2                   # st0 = ln2
    fld qword ptr [f_tmp]    # st0 = x, st1 = ln2
    fyl2x                    # st0 = ln2 * log2(x) = ln(x)
    fstp qword ptr [f_tmp]
    movq xmm0, [f_tmp]
    pop r8
    jmp float_tag

# ================================================================= JIT ====
#
# After parsing, every function body is compiled into native x86-64 code in
# an mmap'd RWX arena (4 MiB). Function calls are patched after all functions
# are compiled; functions that could not be compiled stay interpreted.
#
# ABI: rdi = argv pointer (arg1 first), return value in rax. Native frames
# live below rbp; the frame is zeroed and params copied from argv. Helpers
# (print_int, write_str, read_int, putchar_int, getchar_int, die) preserve
# rbx/r12-r15; generated code only uses rax,rcx,rdx,rdi,rsi,r8-r11, rbp and
# r8 (argv). Generated code references .text/.bss addresses with absolute
# imm64 (the arena may be >2 GiB away), jit_depth is the only bss global
# touched at runtime, and internal branches use rel32 within the arena.
#
# jit_pos is an absolute address inside the arena; labels are absolute
# addresses, so rel32 = label - (fix_pos + 4) at every fixup site.

# ------------------------------------------------------------ emit primitives
jit_emit_byte:                     # al = byte; no-op on overflow (jit_failed)
    mov rdi, [jit_pos]
    lea rcx, [rdi + 16]
    cmp rcx, [jit_end]
    jg jit_emit_overflow
    mov [rdi], al
    inc rdi
    mov [jit_pos], rdi
    ret

jit_emit_dword:                    # eax = 4 bytes
    mov rdi, [jit_pos]
    lea rcx, [rdi + 16]
    cmp rcx, [jit_end]
    jg jit_emit_overflow
    mov [rdi], eax
    add rdi, 4
    mov [jit_pos], rdi
    ret

jit_emit_qword:                    # rax = 8 bytes
    mov rdi, [jit_pos]
    lea rcx, [rdi + 16]
    cmp rcx, [jit_end]
    jg jit_emit_overflow
    mov [rdi], rax
    add rdi, 8
    mov [jit_pos], rdi
    ret

jit_emit_overflow:
    mov qword ptr [jit_failed], 1
    ret

# jit_emit_bytes: rsi = ptr to bytes, rcx = count
# jit_emit_byte clobbers rcx, so keep the loop counter on the stack.
jit_emit_bytes:
    push rbx
    mov rbx, rcx
    xor rcx, rcx
jit_emit_bytes_loop:
    cmp rcx, rbx
    jge jit_emit_bytes_done
    mov al, [rsi + rcx]
    push rcx
    call jit_emit_byte
    pop rcx
    inc rcx
    jmp jit_emit_bytes_loop
jit_emit_bytes_done:
    pop rbx
    ret

# mov rX, imm64 emitters. Each takes the immediate in its own register:
# rdi (rax/rdi), rsi (rsi). Emit 48 B8/BF/BE + qword.
jit_emit_mov_rax_imm:
    push rdi
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xB8
    call jit_emit_byte
    pop rdi
    mov rax, rdi
    jmp jit_emit_qword

jit_emit_mov_rdi_imm:
    push rdi
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xBF
    call jit_emit_byte
    pop rdi
    mov rax, rdi
    jmp jit_emit_qword

jit_emit_mov_rsi_imm:
    push rsi
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xBE
    call jit_emit_byte
    pop rsi
    mov rax, rsi
    jmp jit_emit_qword

# mov rcx, imm32: 48 C7 C1 imm32
jit_emit_mov_rcx_imm32:            # rdi = value
    push rdi
    lea rsi, [enc_mov_rcx_imm32]
    mov rcx, 3
    call jit_emit_bytes
    pop rax
    jmp jit_emit_dword

# cmp rax, imm32: 48 3D imm32
jit_emit_cmp_rax_imm32:            # rdi = value
    push rdi
    lea rsi, [enc_cmp_rax_imm32]
    mov rcx, 2
    call jit_emit_bytes
    pop rax
    jmp jit_emit_dword

# add rsp, imm (skips if 0): 48 83 C4 ib / 48 81 C4 id
jit_emit_add_rsp:                  # rdi = amount
    test rdi, rdi
    jz jit_emit_add_rsp_done
    push rdi
    cmp rdi, 127
    jg jit_emit_add_rsp_d32
    lea rsi, [enc_add_rsp_imm8]
    mov rcx, 3
    call jit_emit_bytes
    pop rax
    call jit_emit_byte
    ret
jit_emit_add_rsp_d32:
    lea rsi, [enc_add_rsp_imm32]
    mov rcx, 3
    call jit_emit_bytes
    pop rax
    jmp jit_emit_dword
jit_emit_add_rsp_done:
    ret

# lea rdi, [rsp + disp]: 48 8D 7C 24 ib / 48 8D BC 24 id
jit_emit_lea_rdi_rsp_disp:         # rdi = disp (non-negative)
    push rdi
    cmp rdi, 127
    jg jit_emit_lea_rdi_rsp_d32
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x8D
    call jit_emit_byte
    mov al, 0x7C
    call jit_emit_byte
    mov al, 0x24
    call jit_emit_byte
    pop rax
    call jit_emit_byte
    ret
jit_emit_lea_rdi_rsp_d32:
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x8D
    call jit_emit_byte
    mov al, 0xBC
    call jit_emit_byte
    mov al, 0x24
    call jit_emit_byte
    pop rax
    jmp jit_emit_dword

# lea rdi, [rbp - frame]: 48 8D 7D ib / 48 8D BD id (negative disp)
jit_emit_lea_rdi_rbp_neg:          # rdi = frame size (non-negative)
    push rdi
    cmp rdi, 127
    jg jit_emit_lea_rdi_rbp_d32
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x8D
    call jit_emit_byte
    mov al, 0x7D
    call jit_emit_byte
    pop rax
    neg al
    call jit_emit_byte
    ret
jit_emit_lea_rdi_rbp_d32:
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x8D
    call jit_emit_byte
    mov al, 0xBD
    call jit_emit_byte
    pop rax
    neg rax
    jmp jit_emit_dword

# ------------------------------------------------------------ slot machinery
# jit_get_slot: rdi = symbol id -> rax = slot index (creates if missing).
# Only called during the scan phase / prologue (before the frame is fixed).
jit_get_slot:
    xor rcx, rcx
jit_get_slot_loop:
    mov rax, [jit_slot_n]
    cmp rcx, rax
    jge jit_get_slot_new
    mov rax, [jit_slot_sym + rcx*8]
    cmp rax, rdi
    je jit_get_slot_done
    inc rcx
    jmp jit_get_slot_loop
jit_get_slot_new:
    cmp rcx, MAXSYM
    jge jit_emit_overflow
    mov [jit_slot_sym + rcx*8], rdi
    lea rdx, [rcx + 1]
    shl rdx, 3                       # off = (slot+1)*8
    mov [jit_slot_off + rcx*8], rdx
    inc qword ptr [jit_slot_n]
jit_get_slot_done:
    mov rax, rcx
    ret

# jit_emit_load_slot: rdi = slot index; emits mov rax,[rbp-off]
jit_emit_load_slot:
    mov rax, [jit_slot_off + rdi*8]
    push rax
    cmp rax, 127
    jg jit_emit_load_slot_d32
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x8B
    call jit_emit_byte
    mov al, 0x45
    call jit_emit_byte
    pop rdx
    mov al, dl
    neg al
    call jit_emit_byte
    ret
jit_emit_load_slot_d32:
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x8B
    call jit_emit_byte
    mov al, 0x85
    call jit_emit_byte
    pop rdx
    mov rsi, rdx
    mov rax, rsi
    neg rax
    jmp jit_emit_dword

# jit_emit_store_slot: rdi = slot index; emits mov [rbp-off],rax
jit_emit_store_slot:
    push rbx
    mov rax, [jit_slot_off + rdi*8]
    push rax
    cmp rax, 127
    jg jit_emit_store_slot_d32
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x89
    call jit_emit_byte
    mov al, 0x45
    call jit_emit_byte
    pop rdx
    mov al, dl
    neg al
    call jit_emit_byte
    pop rbx
    ret
jit_emit_store_slot_d32:
    mov al, 0x48
    call jit_emit_byte
    mov al, 0x89
    call jit_emit_byte
    mov al, 0x85
    call jit_emit_byte
    pop rdx
    mov rsi, rdx
    neg rsi
    mov rax, rsi
    call jit_emit_dword
    pop rbx
    ret

# jit_emit_load_param: rdi = param index; emits mov rax,[r8-idx*8]
# Args are pushed left to right, so argv (r8) points at the LAST arg;
# param i lives at [r8 - i*8].
jit_emit_load_param:
    mov rax, rdi
    shl rax, 3
    push rax
    cmp rax, 127
    jg jit_emit_load_param_d32
    mov al, 0x49
    call jit_emit_byte
    mov al, 0x8B
    call jit_emit_byte
    mov al, 0x40
    call jit_emit_byte
    pop rax
    neg rax
    call jit_emit_byte
    ret
jit_emit_load_param_d32:
    mov al, 0x49
    call jit_emit_byte
    mov al, 0x8B
    call jit_emit_byte
    mov al, 0x80
    call jit_emit_byte
    pop rax
    neg rax
    jmp jit_emit_dword

# ------------------------------------------------------------ jump fixups
# Forward jcc/jmp rel32: record the position of the rel32 field, emit
# placeholder zeros, return the fixup index in rax.
jit_new_fix:
    mov rax, [jit_fix_n]
    mov rdx, [jit_pos]
    mov [jit_fix_pos + rax*8], rdx
    inc qword ptr [jit_fix_n]
    ret

jit_emit_jcc_fix:                  # al = second opcode byte (e.g. 0x84 = JZ)
    push rbx
    mov bl, al
    mov al, 0x0F
    call jit_emit_byte
    mov al, bl
    call jit_emit_byte
    call jit_new_fix
    push rax
    xor eax, eax
    call jit_emit_dword
    pop rax
    pop rbx
    ret

jit_emit_jmp_fix:                  # -> rax = fixup index
    mov al, 0xE9
    call jit_emit_byte
    call jit_new_fix
    push rax
    xor eax, eax
    call jit_emit_dword
    pop rax
    ret

# jit_emit_jmp_back: rdx = target label (earlier in the arena); rel32, no fixup
# jit_emit_byte clobbers rcx/rdi, so the emit position is kept in rdx.
jit_emit_jmp_back:
    mov rsi, rdx
    mov rdx, [jit_pos]
    mov al, 0xE9
    call jit_emit_byte
    mov rax, rsi
    sub rax, rdx
    sub rax, 5
    jmp jit_emit_dword

# jit_set_label: rax = fixup index, rdx = label (absolute address)
jit_set_label:
    mov rcx, [jit_fix_pos + rax*8]
    sub rdx, rcx
    sub rdx, 4
    mov [rcx], edx
    ret

# jit_patch_breaks: rcx = start index, rdx = label; patches E9 rel32 sites
# in jit_brk_pos[start .. jit_brk_n)
jit_patch_breaks:
    push rbx
    mov rbx, rdx
    mov rax, [jit_brk_n]
    cmp rcx, rax
    jge jit_patch_breaks_done
jit_patch_breaks_loop:
    mov rsi, [jit_brk_pos + rcx*8]
    mov rdx, rbx
    sub rdx, rsi
    sub rdx, 4
    mov [rsi], edx
    inc rcx
    cmp rcx, [jit_brk_n]
    jl jit_patch_breaks_loop
jit_patch_breaks_done:
    pop rbx
    ret

# Loop stack helpers (compile time)
jit_loop_push:                     # rcx = cont target, rdx = brk_start
    mov rax, [jit_loop_cnt]
    mov [jit_loop_cont + rax*8], rcx
    mov [jit_loop_brk_start + rax*8], rdx
    inc qword ptr [jit_loop_cnt]
    ret

jit_loop_pop:
    dec qword ptr [jit_loop_cnt]
    ret

# ------------------------------------------------------------ scan phase
# Registers every variable slot the function touches (params were already
# registered by jit_compile_fn). Must not create slots after the frame is
# computed, so emit phase never calls jit_get_slot for new symbols.
jit_scan_expr:                     # rdi = node index
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_NUM
    je jit_scan_expr_done
    cmp rax, ND_STR
    je jit_scan_expr_done
    cmp rax, ND_READ
    je jit_scan_expr_done
    cmp rax, ND_GETCHAR
    je jit_scan_expr_done
    cmp rax, ND_VAR
    je jit_scan_expr_var
    cmp rax, ND_NEG
    je jit_scan_expr_unary
    cmp rax, ND_NOT
    je jit_scan_expr_unary
    cmp rax, ND_PUTCHAR
    je jit_scan_expr_unary
    cmp rax, ND_ADD
    je jit_scan_expr_bin
    cmp rax, ND_SUB
    je jit_scan_expr_bin
    cmp rax, ND_MUL
    je jit_scan_expr_bin
    cmp rax, ND_DIV
    je jit_scan_expr_bin
    cmp rax, ND_MOD
    je jit_scan_expr_bin
    cmp rax, ND_EQ
    je jit_scan_expr_bin
    cmp rax, ND_NE
    je jit_scan_expr_bin
    cmp rax, ND_LT
    je jit_scan_expr_bin
    cmp rax, ND_GT
    je jit_scan_expr_bin
    cmp rax, ND_LE
    je jit_scan_expr_bin
    cmp rax, ND_GE
    je jit_scan_expr_bin
    cmp rax, ND_AND
    je jit_scan_expr_bin
    cmp rax, ND_OR
    je jit_scan_expr_bin
    cmp rax, ND_CALL
    je jit_scan_expr_call
    jmp jit_scan_expr_done
jit_scan_expr_var:
    mov rdi, [node_a + r12*8]
    call jit_get_slot
    jmp jit_scan_expr_done
jit_scan_expr_unary:
    mov rdi, [node_a + r12*8]
    call jit_scan_expr
    jmp jit_scan_expr_done
jit_scan_expr_bin:
    mov rdi, [node_a + r12*8]
    call jit_scan_expr
    mov rdi, [node_b + r12*8]
    call jit_scan_expr
    jmp jit_scan_expr_done
jit_scan_expr_call:
    mov rdx, [node_b + r12*8]      # first arg node (fn name is not a var)
jit_scan_expr_call_loop:
    test rdx, rdx
    jz jit_scan_expr_done
    push rdx
    mov rdi, rdx
    call jit_scan_expr
    pop rdx
    mov rdx, [node_next + rdx*8]
    jmp jit_scan_expr_call_loop
jit_scan_expr_done:
    pop r12
    ret

jit_scan_stmt:                     # rdi = statement node index
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_ASSIGN
    je jit_scan_stmt_assign
    cmp rax, ND_PRINT
    je jit_scan_stmt_print
    cmp rax, ND_IF
    je jit_scan_stmt_if
    cmp rax, ND_WHILE
    je jit_scan_stmt_while
    cmp rax, ND_RETURN
    je jit_scan_stmt_return
    cmp rax, ND_EXPR_STMT
    je jit_scan_stmt_expr
    jmp jit_scan_stmt_done          # BREAK/CONTINUE/FN/IMPORT: nothing
jit_scan_stmt_assign:
    mov rdi, [node_a + r12*8]      # lhs symbol gets a slot
    call jit_get_slot
    mov rdi, [node_b + r12*8]
    call jit_scan_expr
    jmp jit_scan_stmt_done
jit_scan_stmt_print:
    mov rdi, [node_a + r12*8]
    call jit_scan_expr
    jmp jit_scan_stmt_done
jit_scan_stmt_if:
    mov rdi, [node_a + r12*8]
    call jit_scan_expr
    mov rdi, [node_b + r12*8]
    call jit_scan_block
    mov rdi, [node_c + r12*8]
    call jit_scan_block
    jmp jit_scan_stmt_done
jit_scan_stmt_while:
    mov rdi, [node_a + r12*8]
    call jit_scan_expr
    mov rdi, [node_b + r12*8]
    call jit_scan_block
    jmp jit_scan_stmt_done
jit_scan_stmt_return:
    mov rdi, [node_a + r12*8]
    test rdi, rdi
    jz jit_scan_stmt_done
    call jit_scan_expr
    jmp jit_scan_stmt_done
jit_scan_stmt_expr:
    mov rdi, [node_a + r12*8]
    call jit_scan_expr
jit_scan_stmt_done:
    pop r12
    ret

jit_scan_block:                    # rdi = first statement node (0 = empty)
    push rbx
    mov rbx, rdi
jit_scan_block_loop:
    test rbx, rbx
    jz jit_scan_block_done
    mov rdi, rbx
    call jit_scan_stmt
    mov rbx, [node_next + rbx*8]
    jmp jit_scan_block_loop
jit_scan_block_done:
    pop rbx
    ret

# ------------------------------------------------------------ emit phase
# Every emitter leaves r12 = node index (jit_emit_expr/stmt), rbx = current
# statement (jit_emit_block) untouched; helpers preserve callee-saved regs.

jit_emit_expr:                     # rdi = node index; emits code leaving result in rax
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_NUM
    je jit_emit_expr_num
    cmp rax, ND_FLOAT
    je jit_emit_expr_float
    cmp rax, ND_VAR
    je jit_emit_expr_var
    cmp rax, ND_NEG
    je jit_emit_expr_neg
    cmp rax, ND_ADD
    je jit_emit_expr_add
    cmp rax, ND_SUB
    je jit_emit_expr_sub
    cmp rax, ND_MUL
    je jit_emit_expr_mul
    cmp rax, ND_DIV
    je jit_emit_expr_div
    cmp rax, ND_MOD
    je jit_emit_expr_mod
    cmp rax, ND_EQ
    je jit_emit_expr_eq
    cmp rax, ND_NE
    je jit_emit_expr_ne
    cmp rax, ND_LT
    je jit_emit_expr_lt
    cmp rax, ND_GT
    je jit_emit_expr_gt
    cmp rax, ND_LE
    je jit_emit_expr_le
    cmp rax, ND_GE
    je jit_emit_expr_ge
    cmp rax, ND_NOT
    je jit_emit_expr_not
    cmp rax, ND_AND
    je jit_emit_expr_and
    cmp rax, ND_OR
    je jit_emit_expr_or
    cmp rax, ND_CALL
    je jit_emit_expr_call
    cmp rax, ND_STR
    je jit_emit_expr_str
    cmp rax, ND_READ
    je jit_emit_expr_read
    cmp rax, ND_PUTCHAR
    je jit_emit_expr_putchar
    cmp rax, ND_GETCHAR
    je jit_emit_expr_getchar
    cmp rax, ND_LIST_CALL
    je jit_emit_expr_list_call
    cmp rax, ND_LEN
    je jit_emit_expr_len
    cmp rax, ND_PUSH
    je jit_emit_expr_push
    cmp rax, ND_POP
    je jit_emit_expr_pop
    cmp rax, ND_INDEX
    je jit_emit_expr_index
    cmp rax, ND_TYPE
    je jit_emit_expr_type
    cmp rax, ND_INT2STR
    je jit_emit_expr_int2str
    cmp rax, ND_FLOAT2STR
    je jit_emit_expr_float2str
    cmp rax, ND_STR2INT
    je jit_emit_expr_str2int
    cmp rax, ND_STR2FLOAT
    je jit_emit_expr_str2float
    cmp rax, ND_INT2FLOAT
    je jit_emit_expr_int2float
    cmp rax, ND_FLOAT2INT
    je jit_emit_expr_float2int
    cmp rax, ND_BOOL2INT
    je jit_emit_expr_bool2int
    cmp rax, ND_INT2BOOL
    je jit_emit_expr_int2bool
    cmp rax, ND_CONCAT
    je jit_emit_expr_concat
    cmp rax, ND_CHAR
    je jit_emit_expr_char
    cmp rax, ND_STR_GET
    je jit_emit_expr_str_get
    cmp rax, ND_STR_SET
    je jit_emit_expr_str_set
    cmp rax, ND_FLOOR
    je jit_emit_expr_floor
    cmp rax, ND_SQRT
    je jit_emit_expr_sqrt
    cmp rax, ND_EXP
    je jit_emit_expr_exp
    cmp rax, ND_LOG
    je jit_emit_expr_log
    jmp die_parse_error
jit_emit_expr_num:
    mov rdi, [node_a + r12*8]
    call jit_emit_mov_rax_imm
    jmp jit_emit_expr_done
jit_emit_expr_float:
    mov rdi, [node_a + r12*8]
    call jit_emit_mov_rax_imm
    jmp jit_emit_expr_done
jit_emit_expr_str:
    mov rdi, [node_a + r12*8]
    call jit_emit_mov_rdi_imm
    lea rdi, [make_str]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_var:
    mov rdi, [node_a + r12*8]
    call jit_get_slot
    mov rdi, rax
    call jit_emit_load_slot
    jmp jit_emit_expr_done
jit_emit_expr_neg:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [builtin_neg]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_not:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_xor_rax_8]
    mov rcx, 4
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_read:
    lea rdi, [read_int]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_shl_rax_3]
    mov rcx, 4
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_getchar:
    lea rdi, [getchar_tagged]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_putchar:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rsi, [enc_sar_rdi_3]
    mov rcx, 4
    call jit_emit_bytes
    lea rdi, [putchar_int]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_shl_rax_3]
    mov rcx, 4
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_add:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50                   # push rax
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rsi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5F                   # pop rdi
    call jit_emit_byte
    lea rdi, [bin_add]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_sub:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rsi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5F
    call jit_emit_byte
    lea rdi, [bin_sub]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_mul:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rsi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5F
    call jit_emit_byte
    lea rdi, [bin_mul]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_div:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rsi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5F
    call jit_emit_byte
    lea rdi, [bin_div]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_mod:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rsi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5F
    call jit_emit_byte
    lea rdi, [bin_mod]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done

# jit_emit_call1: rdi = helper address; emits eval node_a; rdi=rax; call helper.
jit_emit_call1:
    push rbx
    mov rbx, rdi
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov rdi, rbx
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    pop rbx
    ret

# jit_emit_call2: rdi = helper address; emits eval a; push; eval b; rsi=rax;
#                 pop rdi; call helper.
jit_emit_call2:
    push rbx
    mov rbx, rdi
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rsi_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5F
    call jit_emit_byte
    mov rdi, rbx
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    pop rbx
    ret

# jit_emit_cmp2: rdi = helper address (bin_eq..bin_ge); r12 = node.
jit_emit_cmp2:
    jmp jit_emit_call2

jit_emit_expr_eq:
    lea rdi, [bin_eq]
    call jit_emit_cmp2
    jmp jit_emit_expr_done
jit_emit_expr_ne:
    lea rdi, [bin_ne]
    call jit_emit_cmp2
    jmp jit_emit_expr_done
jit_emit_expr_lt:
    lea rdi, [bin_lt]
    call jit_emit_cmp2
    jmp jit_emit_expr_done
jit_emit_expr_gt:
    lea rdi, [bin_gt]
    call jit_emit_cmp2
    jmp jit_emit_expr_done
jit_emit_expr_le:
    lea rdi, [bin_le]
    call jit_emit_cmp2
    jmp jit_emit_expr_done
jit_emit_expr_ge:
    lea rdi, [bin_ge]
    call jit_emit_cmp2
    jmp jit_emit_expr_done

# Short-circuit && : a; test; jz false; b; test; setne; movzx; jmp done;
#                   false: xor eax,eax; done:
jit_emit_expr_and:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_cmp_rax_imm8]
    mov rcx, 3
    call jit_emit_bytes
    mov al, BOOL_FALSE
    call jit_emit_byte
    mov al, 0x84                   # JZ -> false
    call jit_emit_jcc_fix
    push rax
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    call jit_emit_jmp_fix          # done fixup
    push rax
    mov rax, [rsp + 8]             # false fixup
    mov rdx, [jit_pos]
    call jit_set_label
    mov rdi, BOOL_FALSE
    call jit_emit_mov_rax_imm
    pop rax                        # done fixup
    mov rdx, [jit_pos]
    call jit_set_label
    add rsp, 8
    jmp jit_emit_expr_done

# Short-circuit || : a; truthy? jnz true; b; truthy?; jmp done;
#                   true: mov rax,true; done:
jit_emit_expr_or:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_cmp_rax_imm8]
    mov rcx, 3
    call jit_emit_bytes
    mov al, BOOL_TRUE
    call jit_emit_byte
    mov al, 0x85                   # JNZ -> true
    call jit_emit_jcc_fix
    push rax
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    call jit_emit_jmp_fix          # done fixup
    push rax
    mov rax, [rsp + 8]             # true fixup
    mov rdx, [jit_pos]
    call jit_set_label
    mov rdi, BOOL_TRUE
    call jit_emit_mov_rax_imm
    pop rax                        # done fixup
    mov rdx, [jit_pos]
    call jit_set_label
    add rsp, 8
    jmp jit_emit_expr_done

jit_emit_expr_list_call:
    push rbx
    push r13
    push r14
    push r15
    xor r14, r14
    mov r15, [node_b + r12*8]
jit_emit_expr_list_call_count:
    test r15, r15
    jz jit_emit_expr_list_call_count_done
    inc r14
    mov r15, [node_next + r15*8]
    jmp jit_emit_expr_list_call_count
jit_emit_expr_list_call_count_done:
    mov r15, [node_b + r12*8]
jit_emit_expr_list_call_args:
    test r15, r15
    jz jit_emit_expr_list_call_args_done
    push r15
    mov rdi, r15
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    pop r15
    mov r15, [node_next + r15*8]
    jmp jit_emit_expr_list_call_args
jit_emit_expr_list_call_args_done:
    mov rdi, r14
    call jit_emit_mov_rdi_imm
    lea rdi, [list_make]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    mov rdi, r14
    shl rdi, 3
    call jit_emit_add_rsp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp jit_emit_expr_done
jit_emit_expr_len:
    lea rdi, [builtin_len]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_push:
    lea rdi, [list_push]
    call jit_emit_call2
    jmp jit_emit_expr_done
jit_emit_expr_pop:
    lea rdi, [list_pop]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_index:
    lea rdi, [builtin_index]
    call jit_emit_call2
    jmp jit_emit_expr_done
jit_emit_expr_type:
    lea rdi, [builtin_type]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_int2str:
    lea rdi, [int2str_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_float2str:
    lea rdi, [float2str_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_str2int:
    lea rdi, [str2int]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_str2float:
    lea rdi, [str2float]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_int2float:
    lea rdi, [int_to_float_tagged]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_float2int:
    lea rdi, [float2int_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_bool2int:
    lea rdi, [bool2int_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_int2bool:
    lea rdi, [int2bool_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_concat:
    push rbx
    push r13
    push r14
    push r15
    xor r14, r14
    mov r15, [node_b + r12*8]
jit_emit_expr_concat_count:
    test r15, r15
    jz jit_emit_expr_concat_count_done
    inc r14
    mov r15, [node_next + r15*8]
    jmp jit_emit_expr_concat_count
jit_emit_expr_concat_count_done:
    mov r15, [node_b + r12*8]
jit_emit_expr_concat_args:
    test r15, r15
    jz jit_emit_expr_concat_args_done
    push r15
    mov rdi, r15
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    pop r15
    mov r15, [node_next + r15*8]
    jmp jit_emit_expr_concat_args
jit_emit_expr_concat_args_done:
    mov rdi, r14
    call jit_emit_mov_rdi_imm
    lea rdi, [str_concat_all]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    mov rdi, r14
    shl rdi, 3
    call jit_emit_add_rsp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp jit_emit_expr_done
jit_emit_expr_char:
    lea rdi, [char_of_int]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_str_get:
    lea rdi, [str_index]
    call jit_emit_call2
    jmp jit_emit_expr_done
jit_emit_expr_str_set:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_c + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdx_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5E                   # pop rsi
    call jit_emit_byte
    mov al, 0x5F                   # pop rdi
    call jit_emit_byte
    lea rdi, [str_set]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
jit_emit_expr_floor:
    lea rdi, [floor_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_sqrt:
    lea rdi, [sqrt_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done

jit_emit_expr_exp:
    lea rdi, [exp_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done

jit_emit_expr_log:
    lea rdi, [log_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done

# Call: r12 = node. Emits arg pushes (pad to keep rsp 16-aligned at the call),
# rdi = argv, rsi = fn index, rax = patched target (0 -> interp bridge).
jit_emit_expr_call:
    call jit_emit_call
    jmp jit_emit_expr_done

jit_emit_call:                     # r12 = call node
    push rbx
    push r13
    push r14
    push r15
    mov r13, [node_a + r12*8]      # fn symbol id
    xor rbx, rbx
jit_emit_call_lookup:
    mov rax, [fn_n]
    cmp rbx, rax
    jge jit_emit_call_undef
    mov rax, [fn_sym + rbx*8]
    cmp rax, r13
    je jit_emit_call_found
    inc rbx
    jmp jit_emit_call_lookup
jit_emit_call_undef:
    # Compile-time unknown function: emit code that dies at runtime.
    lea rdi, [msg_undef_fn]
    call jit_emit_mov_rdi_imm
    mov rsi, msg_undef_fn_len
    call jit_emit_mov_rsi_imm
    lea rdi, [die]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_call_done
jit_emit_call_found:
    # rbx = fn index; count args
    xor r14, r14
    mov r15, [node_b + r12*8]
jit_emit_call_count:
    test r15, r15
    jz jit_emit_call_count_done
    inc r14
    mov r15, [node_next + r15*8]
    jmp jit_emit_call_count
jit_emit_call_count_done:
    test r14, 1
    jz jit_emit_call_no_pad
    lea rsi, [enc_sub_rsp_imm8]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 8
    call jit_emit_byte
jit_emit_call_no_pad:
    # emit args left to right, pushing each
    mov r15, [node_b + r12*8]
jit_emit_call_args:
    test r15, r15
    jz jit_emit_call_args_done
    push r15
    mov rdi, r15
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    pop r15
    mov r15, [node_next + r15*8]
    jmp jit_emit_call_args
jit_emit_call_args_done:
    # rdi = argv (first arg address)
    test r14, r14
    jnz jit_emit_call_argv_disp
    lea rsi, [enc_mov_rdi_rsp]
    mov rcx, 3
    call jit_emit_bytes
    jmp jit_emit_call_rsi
jit_emit_call_argv_disp:
    mov rdi, r14
    dec rdi
    shl rdi, 3
    call jit_emit_lea_rdi_rsp_disp
jit_emit_call_rsi:
    mov rsi, rbx
    call jit_emit_mov_rsi_imm
    # mov rax, imm64(0) placeholder; remember the imm64 position
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xB8
    call jit_emit_byte
    mov rax, [jit_pos]
    mov rcx, [jit_call_n]
    mov [jit_call_pos + rcx*8], rax
    mov [jit_call_fn + rcx*8], rbx
    inc qword ptr [jit_call_n]
    xor eax, eax
    call jit_emit_qword
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    # clean up: add rsp, (N + (N&1)) * 8
    mov rdi, r14
    mov rax, r14
    and rax, 1
    add rdi, rax
    shl rdi, 3
    call jit_emit_add_rsp
jit_emit_call_done:
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

jit_emit_expr_done:
    pop r12
    ret

jit_emit_stmt:                     # rdi = statement node index
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_ASSIGN
    je jit_emit_stmt_assign
    cmp rax, ND_VAR_DECL
    je jit_emit_stmt_var_decl
    cmp rax, ND_INDEX_ASSIGN
    je jit_emit_stmt_index_assign
    cmp rax, ND_PRINT
    je jit_emit_stmt_print
    cmp rax, ND_IF
    je jit_emit_stmt_if
    cmp rax, ND_WHILE
    je jit_emit_stmt_while
    cmp rax, ND_BREAK
    je jit_emit_stmt_break
    cmp rax, ND_CONTINUE
    je jit_emit_stmt_continue
    cmp rax, ND_RETURN
    je jit_emit_stmt_return
    cmp rax, ND_EXPR_STMT
    je jit_emit_stmt_expr
    jmp jit_emit_stmt_done          # FN/IMPORT: no-op
jit_emit_stmt_assign:
    mov rcx, [node_a + r12*8]
    cmp qword ptr [sym_mutable + rcx*8], 1
    je jit_emit_stmt_assign_imm
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    push rax
    mov rdi, [node_a + r12*8]
    call jit_get_slot
    mov rdi, rax
    pop rax
    call jit_emit_store_slot
    jmp jit_emit_stmt_done
jit_emit_stmt_assign_imm:
    lea rdi, [msg_imm]
    call jit_emit_mov_rdi_imm
    mov rsi, msg_imm_len
    call jit_emit_mov_rsi_imm
    lea rdi, [die]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_stmt_done
jit_emit_stmt_var_decl:
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    push rax
    mov rdi, [node_a + r12*8]
    call jit_get_slot
    mov rdi, rax
    pop rax
    call jit_emit_store_slot
    jmp jit_emit_stmt_done
jit_emit_stmt_index_assign:
    mov rdi, [node_c + r12*8]
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    mov rdi, [node_b + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdx_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x5E                   # pop rsi
    call jit_emit_byte
    mov rdi, [node_a + r12*8]
    call jit_get_slot
    mov rdi, rax
    call jit_emit_load_slot
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [list_index_assign]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_stmt_done
jit_emit_stmt_print:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [print_value]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_stmt_done
jit_emit_stmt_if:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_cmp_rax_imm8]
    mov rcx, 3
    call jit_emit_bytes
    mov al, BOOL_FALSE
    call jit_emit_byte
    mov al, 0x84
    call jit_emit_jcc_fix          # else fixup
    push rax
    mov rdi, [node_b + r12*8]
    call jit_emit_block
    call jit_emit_jmp_fix          # end fixup
    push rax
    mov rax, [rsp + 8]             # else fixup
    mov rdx, [jit_pos]
    call jit_set_label
    mov rdi, [node_c + r12*8]
    test rdi, rdi
    jz jit_emit_stmt_if_skip
    call jit_emit_block
jit_emit_stmt_if_skip:
    pop rax                        # end fixup
    mov rdx, [jit_pos]
    call jit_set_label
    add rsp, 8
    jmp jit_emit_stmt_done
jit_emit_stmt_while:
    mov rcx, [jit_pos]             # cont label
    push rcx
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
    lea rsi, [enc_mov_rdi_rax]
    mov rcx, 3
    call jit_emit_bytes
    lea rdi, [is_truthy]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    lea rsi, [enc_cmp_rax_imm8]
    mov rcx, 3
    call jit_emit_bytes
    mov al, BOOL_FALSE
    call jit_emit_byte
    mov al, 0x84
    call jit_emit_jcc_fix          # break fixup
    push rax
    mov rdx, [jit_brk_n]           # brk_start
    push rdx
    mov rcx, [rsp + 16]            # cont
    mov rdx, [rsp]                 # brk_start
    call jit_loop_push
    mov rdi, [node_b + r12*8]
    call jit_emit_block
    mov rdx, [rsp + 16]            # cont
    call jit_emit_jmp_back
    mov rdx, [jit_pos]             # break label
    mov rcx, [rsp]                 # brk_start
    call jit_patch_breaks
    mov rax, [rsp + 8]             # break fixup
    mov rdx, [jit_pos]
    call jit_set_label
    call jit_loop_pop
    add rsp, 24
    jmp jit_emit_stmt_done
jit_emit_stmt_break:
    mov rax, [jit_loop_cnt]
    test rax, rax
    jz jit_emit_stmt_done          # top-level break: no-op
    mov al, 0xE9
    call jit_emit_byte
    mov rdx, [jit_pos]
    mov rax, [jit_brk_n]
    mov [jit_brk_pos + rax*8], rdx
    inc qword ptr [jit_brk_n]
    xor eax, eax
    call jit_emit_dword
    jmp jit_emit_stmt_done
jit_emit_stmt_continue:
    mov rax, [jit_loop_cnt]
    test rax, rax
    jz jit_emit_stmt_done          # top-level continue: no-op
    dec rax
    mov rdx, [jit_loop_cont + rax*8]
    call jit_emit_jmp_back
    jmp jit_emit_stmt_done
jit_emit_stmt_return:
    mov rdi, [node_a + r12*8]
    test rdi, rdi
    jz jit_emit_stmt_return_zero
    call jit_emit_expr
    jmp jit_emit_stmt_return_emit
jit_emit_stmt_return_zero:
    lea rsi, [enc_xor_eax_eax]
    mov rcx, 2
    call jit_emit_bytes
jit_emit_stmt_return_emit:
    call jit_emit_jmp_fix
    mov rcx, [jit_ret_n]
    mov [jit_ret_fix + rcx*8], rax
    inc qword ptr [jit_ret_n]
    jmp jit_emit_stmt_done
jit_emit_stmt_expr:
    mov rdi, [node_a + r12*8]
    call jit_emit_expr
jit_emit_stmt_done:
    pop r12
    ret

jit_emit_block:                    # rdi = first statement node (0 = empty)
    push rbx
    mov rbx, rdi
jit_emit_block_loop:
    test rbx, rbx
    jz jit_emit_block_done
    mov rdi, rbx
    call jit_emit_stmt
    mov rbx, [node_next + rbx*8]
    jmp jit_emit_block_loop
jit_emit_block_done:
    pop rbx
    ret

# ------------------------------------------------------------ prologue/epilogue
# Prologue: push rbp; mov rbp,rsp; sub rsp,frame; mov r8,rdi; zero the frame;
# copy params from argv; increment the native depth guard.
jit_emit_prologue:
    push rbx
    push r12
    lea rsi, [enc_push_rbp]
    mov rcx, 1
    call jit_emit_bytes
    lea rsi, [enc_mov_rbp_rsp]
    mov rcx, 3
    call jit_emit_bytes
    mov rax, [jit_frame_size]
    test rax, rax
    jz jit_emit_prologue_no_frame
    push rax
    cmp rax, 127
    jg jit_emit_prologue_sub_d32
    lea rsi, [enc_sub_rsp_imm8]
    mov rcx, 3
    call jit_emit_bytes
    pop rax
    call jit_emit_byte
    jmp jit_emit_prologue_zero
jit_emit_prologue_sub_d32:
    lea rsi, [enc_sub_rsp_imm32]
    mov rcx, 3
    call jit_emit_bytes
    pop rax
    call jit_emit_dword
jit_emit_prologue_zero:
    lea rsi, [enc_mov_r8_rdi]
    mov rcx, 3
    call jit_emit_bytes
    lea rsi, [enc_xor_eax_eax]
    mov rcx, 2
    call jit_emit_bytes
    mov rdi, [jit_frame_size]
    call jit_emit_lea_rdi_rbp_neg
    mov rax, [jit_frame_size]
    shr rax, 3
    mov rdi, rax
    call jit_emit_mov_rcx_imm32
    lea rsi, [enc_rep_stosq]
    mov rcx, 3
    call jit_emit_bytes
jit_emit_prologue_no_frame:
    # copy params from argv
    xor r12, r12
jit_emit_prologue_params:
    mov rax, [fn_param_count + rbx*8]
    cmp r12, rax
    jge jit_emit_prologue_params_done
    push r12
    mov rdi, r12
    call jit_emit_load_param
    pop r12
    push r12
    imul rdx, rbx, MAXPARAMS
    add rdx, r12
    mov rdi, [fn_param_syms + rdx*8]
    call jit_get_slot
    mov rdi, rax
    call jit_emit_store_slot
    pop r12
    inc r12
    jmp jit_emit_prologue_params
jit_emit_prologue_params_done:
    # native depth guard: depth++ ; if depth >= MAXFRAMES die
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xA1                   # mov rax, [abs64]
    call jit_emit_byte
    lea rax, [jit_depth]
    call jit_emit_qword
    lea rsi, [enc_inc_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov rdi, MAXFRAMES
    call jit_emit_cmp_rax_imm32
    mov al, 0x8D                   # JGE -> overflow path
    call jit_emit_jcc_fix
    push rax
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xA3                   # mov [abs64], rax
    call jit_emit_byte
    lea rax, [jit_depth]
    call jit_emit_qword
    call jit_emit_jmp_fix          # E9 rel32: skip die_seq on the normal path
    push rax
    mov rax, [rsp + 8]             # jge fixup
    mov rdx, [jit_pos]
    call jit_set_label             # jge -> die_seq
    lea rdi, [msg_stackoverflow]
    call jit_emit_mov_rdi_imm
    mov rsi, msg_stackoverflow_len
    call jit_emit_mov_rsi_imm
    lea rdi, [die]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    pop rax                        # jmp fixup
    mov rdx, [jit_pos]
    call jit_set_label             # jmp -> body start (after die_seq)
    add rsp, 8                     # discard the jge fixup
    pop r12
    pop rbx
    ret

# Epilogue (fn_end label): depth-- ; leave ; ret
jit_emit_epilogue:
    mov al, 0x50                   # push rax (preserve return value)
    call jit_emit_byte
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xA1
    call jit_emit_byte
    lea rax, [jit_depth]
    call jit_emit_qword
    lea rsi, [enc_dec_rax]
    mov rcx, 3
    call jit_emit_bytes
    mov al, 0x48
    call jit_emit_byte
    mov al, 0xA3
    call jit_emit_byte
    lea rax, [jit_depth]
    call jit_emit_qword
    mov al, 0x58                   # pop rax (restore return value)
    call jit_emit_byte
    lea rsi, [enc_leave]
    mov rcx, 1
    call jit_emit_bytes
    lea rsi, [enc_ret]
    mov rcx, 1
    call jit_emit_bytes
    ret

# ------------------------------------------------------------ compile driver
# jit_compile_fn: rdi = fn index. Compiles one function into the arena and
# installs fn_jit[idx], or rolls back and leaves it 0 on any failure.
jit_compile_fn:
    push rbx
    push r12
    mov rbx, rdi
    mov rax, [jit_pos]
    mov [jit_code_start], rax
    mov r12, [jit_call_n]
    push r12                       # saved call count for rollback
    lea rcx, [rax + 65536]         # headroom check
    cmp rcx, [jit_end]
    jg jit_compile_fn_fail
    mov [jit_fn_index], rbx
    mov qword ptr [jit_slot_n], 0
    mov rax, [jit_fix_n]
    mov [jit_fix_base], rax
    mov qword ptr [jit_ret_n], 0
    mov qword ptr [jit_brk_n], 0
    mov qword ptr [jit_loop_cnt], 0
    # register params first
    xor rcx, rcx
jit_compile_fn_params:
    mov rax, [fn_param_count + rbx*8]
    cmp rcx, rax
    jge jit_compile_fn_params_done
    push rcx
    imul rdx, rbx, MAXPARAMS
    add rdx, rcx
    mov rdi, [fn_param_syms + rdx*8]
    call jit_get_slot
    pop rcx
    inc rcx
    jmp jit_compile_fn_params
jit_compile_fn_params_done:
    # scan the body for local variable slots
    mov rdi, [fn_body + rbx*8]
    call jit_scan_block
    # fix the frame size now (no new slots beyond this point)
    mov rax, [jit_slot_n]
    imul rax, rax, 8
    add rax, 15
    and rax, -16
    mov [jit_frame_size], rax
    call jit_emit_prologue
    mov rdi, [fn_body + rbx*8]
    call jit_emit_block
    # fall-through return 0
    lea rsi, [enc_xor_eax_eax]
    mov rcx, 2
    call jit_emit_bytes
    # fn_end label + epilogue
    mov rax, [jit_pos]
    mov [jit_fn_end], rax
    call jit_emit_epilogue
    # patch return jumps to fn_end
    xor rcx, rcx
jit_compile_fn_ret_patch:
    mov rax, [jit_ret_n]
    cmp rcx, rax
    jge jit_compile_fn_ret_patch_done
    mov rax, [jit_ret_fix + rcx*8]
    mov rdx, [jit_fn_end]
    push rcx                    # jit_set_label clobbers rcx
    call jit_set_label
    pop rcx
    inc rcx
    jmp jit_compile_fn_ret_patch
jit_compile_fn_ret_patch_done:
    mov rax, [jit_failed]
    test rax, rax
    jnz jit_compile_fn_fail
    # install
    mov rax, [jit_code_start]
    mov [fn_jit + rbx*8], rax
    pop r12                        # discard saved call count
    pop r12
    pop rbx
    ret
jit_compile_fn_fail:
    mov rax, [jit_failed]
    test rax, rax
    jz jit_compile_fn_fail_clean
    mov rax, [jit_code_start]
    mov [jit_pos], rax
    mov rax, [jit_fix_base]
    mov [jit_fix_n], rax
    mov qword ptr [jit_ret_n], 0
    mov qword ptr [jit_brk_n], 0
    mov qword ptr [jit_loop_cnt], 0
    mov qword ptr [jit_failed], 0
jit_compile_fn_fail_clean:
    pop r12
    mov [jit_call_n], r12
    mov qword ptr [fn_jit + rbx*8], 0
    pop r12
    pop rbx
    ret

# jit_patch_calls: resolve every recorded call site to its native address
# or to the interp bridge. Runs after all functions are compiled.
jit_patch_calls:
    push rbx
    xor rbx, rbx
jit_patch_calls_loop:
    mov rax, [jit_call_n]
    cmp rbx, rax
    jge jit_patch_calls_done
    mov rax, [jit_call_fn + rbx*8]
    mov rax, [fn_jit + rax*8]
    test rax, rax
    jnz jit_patch_calls_have
    lea rax, [jit_to_interp_bridge]
jit_patch_calls_have:
    mov rcx, [jit_call_pos + rbx*8]
    mov [rcx], rax
    inc rbx
    jmp jit_patch_calls_loop
jit_patch_calls_done:
    pop rbx
    ret

# jit_compile_all: mmap the arena, compile every function, patch calls,
# then mprotect the arena to read+exec. On any failure nothing is installed.
jit_compile_all:
    push rbx
    push r12
    xor rdi, rdi
    mov rsi, JIT_ARENA_SIZE
    mov rdx, PROT_READ | PROT_WRITE | PROT_EXEC
    mov r10, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9, r9
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja jit_compile_all_done        # mmap failed: everything stays interpreted
    mov [jit_arena], rax
    mov [jit_pos], rax
    lea rcx, [rax + JIT_ARENA_SIZE]
    mov [jit_end], rcx
    mov qword ptr [jit_failed], 0
    mov qword ptr [jit_call_n], 0
    mov qword ptr [jit_fix_n], 0
    mov qword ptr [jit_fix_base], 0
    xor rbx, rbx
jit_compile_all_loop:
    mov rax, [fn_n]
    cmp rbx, rax
    jge jit_compile_all_patch
    mov rdi, rbx
    call jit_compile_fn
    inc rbx
    jmp jit_compile_all_loop
jit_compile_all_patch:
    call jit_patch_calls
    mov rdi, [jit_arena]
    mov rsi, JIT_ARENA_SIZE
    mov rdx, PROT_READ | PROT_EXEC
    mov rax, SYS_MPROTECT
    syscall
jit_compile_all_done:
    pop r12
    pop rbx
    ret

# interp_invoke: rdi = fn index, rsi = argv (evaluated argument values).
# Preserves rbx/r12-r15/rbp. Runs the interpreted body like eval_call does
# but without re-evaluating arguments.
interp_invoke:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbx, rdi
    mov rax, [call_depth]
    cmp rax, MAXFRAMES - 1
    jge die_stackoverflow
    inc rax
    mov [call_depth], rax
    imul rdi, rax, MAXSYM*8
    lea rdi, [call_stack + rdi]
    xor rax, rax
    mov rcx, MAXSYM
    rep stosq
    xor rcx, rcx
interp_invoke_arg_loop:
    mov rax, [fn_param_count + rbx*8]
    cmp rcx, rax
    jge interp_invoke_args_done
    mov rax, [rsi]
    imul r8, rbx, MAXPARAMS
    add r8, rcx
    mov r8, [fn_param_syms + r8*8]
    mov r9, [call_depth]
    imul r9, r9, MAXSYM
    add r9, r8
    mov [call_stack + r9*8], rax
    inc rcx
    sub rsi, 8
    jmp interp_invoke_arg_loop
interp_invoke_args_done:
    mov qword ptr [return_val], 0
    mov rdi, [fn_body + rbx*8]
    call exec_list
    dec qword ptr [call_depth]
    mov rax, [return_val]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# jit_to_interp_bridge: called from generated code with rdi = argv,
# rsi = fn index. Swaps and dispatches to the interpreter.
jit_to_interp_bridge:
    xchg rdi, rsi
    jmp interp_invoke

# ---------------------------------------------------------------- _start --
_start:
    mov qword ptr [node_n], 1      # node 0 is reserved as "null"
    mov qword ptr [call_depth], 0
    mov qword ptr [fn_n], 0
    mov qword ptr [str_n], 0
    mov qword ptr [str_pool_pos], 0
    call register_builtins
    mov rax, [rsp]                 # argc
    cmp rax, 2
    jl start_usage
    mov rdi, [rsp + 16]            # argv[1]
    call load_source
    lea rax, [src_buf]
    mov [lex_src_ptr], rax
    call tokenize
    call parse_program
    mov [program_root], rax
    # "nojit" as argv[2] disables the JIT (everything runs interpreted)
    mov rax, [rsp]                 # argc
    cmp rax, 3
    jl start_jit
    mov rdi, [rsp + 24]            # argv[2]
    cmp byte ptr [rdi], 'n'
    jne start_jit
    cmp byte ptr [rdi + 1], 'o'
    jne start_jit
    cmp byte ptr [rdi + 2], 'j'
    jne start_jit
    cmp byte ptr [rdi + 3], 'i'
    jne start_jit
    cmp byte ptr [rdi + 4], 't'
    jne start_jit
    jmp start_execute
start_jit:
    call jit_compile_all
start_execute:
    mov rdi, [program_root]
    call exec_list
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
# register_builtins: resolve the builtin function names to symbol IDs.
# Must run before parsing so parse_call can dispatch builtins statically.
register_builtins:
    push rbx
    lea rbx, [bname_list]
    lea rsi, [bname_list]
    mov rdx, 4
    call resolve_symbol
    mov [builtin_list_sym], rax
    lea rsi, [bname_len]
    mov rdx, 3
    call resolve_symbol
    mov [builtin_len_sym], rax
    lea rsi, [bname_push]
    mov rdx, 4
    call resolve_symbol
    mov [builtin_push_sym], rax
    lea rsi, [bname_pop]
    mov rdx, 3
    call resolve_symbol
    mov [builtin_pop_sym], rax
    lea rsi, [bname_type]
    mov rdx, 4
    call resolve_symbol
    mov [builtin_type_sym], rax
    lea rsi, [bname_int2str]
    mov rdx, 7
    call resolve_symbol
    mov [builtin_int2str_sym], rax
    lea rsi, [bname_float2str]
    mov rdx, 9
    call resolve_symbol
    mov [builtin_float2str_sym], rax
    lea rsi, [bname_str2int]
    mov rdx, 7
    call resolve_symbol
    mov [builtin_str2int_sym], rax
    lea rsi, [bname_str2float]
    mov rdx, 9
    call resolve_symbol
    mov [builtin_str2float_sym], rax
    lea rsi, [bname_int2float]
    mov rdx, 9
    call resolve_symbol
    mov [builtin_int2float_sym], rax
    lea rsi, [bname_float2int]
    mov rdx, 9
    call resolve_symbol
    mov [builtin_float2int_sym], rax
    lea rsi, [bname_bool2int]
    mov rdx, 8
    call resolve_symbol
    mov [builtin_bool2int_sym], rax
    lea rsi, [bname_int2bool]
    mov rdx, 8
    call resolve_symbol
    mov [builtin_int2bool_sym], rax
    lea rsi, [bname_concat]
    mov rdx, 6
    call resolve_symbol
    mov [builtin_concat_sym], rax
    lea rsi, [bname_char]
    mov rdx, 4
    call resolve_symbol
    mov [builtin_char_sym], rax
    lea rsi, [bname_str_get]
    mov rdx, 7
    call resolve_symbol
    mov [builtin_str_get_sym], rax
    lea rsi, [bname_str_set]
    mov rdx, 7
    call resolve_symbol
    mov [builtin_str_set_sym], rax
    lea rsi, [bname_floor]
    mov rdx, 5
    call resolve_symbol
    mov [builtin_floor_sym], rax
    lea rsi, [bname_sqrt]
    mov rdx, 4
    call resolve_symbol
    mov [builtin_sqrt_sym], rax
    lea rsi, [bname_exp]
    mov rdx, 3
    call resolve_symbol
    mov [builtin_exp_sym], rax
    lea rsi, [bname_log]
    mov rdx, 3
    call resolve_symbol
    mov [builtin_log_sym], rax
    pop rbx
    ret

start_usage:
    lea rdi, [msg_usage]
    mov rsi, msg_usage_len
    call die
