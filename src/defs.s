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
.equ SYS_MUNMAP, 11
.equ SYS_IOCTL,  16
.equ SYS_PREAD64, 17
.equ SYS_READLINK, 89
.equ SYS_EXIT,   60
.equ SYS_ARCH_PRCTL, 158

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
.equ ND_DLOPEN,    58      # dlopen(path)         → handle int
.equ ND_DLSYM,     59      # dlsym(handle, name)  → address int
.equ ND_CALL_NATIVE, 60    # call_native(addr, ...)   → int result  (variadic)
.equ ND_CALL_NATIVE_F, 61  # call_native_f(...)       → float result (variadic)
.equ ND_DLERROR,   62      # dlerror()             → last error string

# ------------------------------------------------------------------ loader --
# Capabilities and data layout for the minimal ELF loader (src/dl.s).
.equ DL_DSO_MAX,    16
.equ DL_ARGS_MAX,   16
.equ DL_TLS_AREA,   0x40000   # 256 KiB static-TLS region per loaded set
.equ DL_MAP_BASE,   0x0F000000  # fixed base for loaded libraries (far above qafc)

# DSO descriptor layout (fixed-size slots in dl_table, DSO_ENTRY_SIZE each)
.equ DSO_BASE,      0
.equ DSO_MSIZE,     8
.equ DSO_FIRSTMAP,  16
.equ DSO_DYNAMIC,   24
.equ DSO_STRTAB,    32
.equ DSO_SYMTAB,    40
.equ DSO_GNUHASH,   48
.equ DSO_SYSVHASH,  56
.equ DSO_RELADD,    64
.equ DSO_RELSZ,     72
.equ DSO_PLTREL,    80
.equ DSO_PLTRELSZ,  88
.equ DSO_PLTRELTYPE,96
.equ DSO_INIT,      104
.equ DSO_INITARRAY, 112
.equ DSO_INITSZ,    120
.equ DSO_FINI,      128
.equ DSO_FINIARRAY, 136
.equ DSO_FINISZ,    144
.equ DSO_TLSOFF,    152
.equ DSO_TLSSIZE,   160
.equ DSO_TLSALIGN,  168
.equ DSO_ORDER,     176
.equ DSO_NAMEPTR,   184
.equ DSO_NAMELEN,   192
.equ DSO_RELR,      200
.equ DSO_RELRSZ,    208
.equ DSO_ENTRY_SIZE,216

# x86-64 relocation types
.equ R_RELATIVE,  0
.equ R_64,        1
.equ R_PC32,      2
.equ R_GLOB_DAT,  6
.equ R_JUMP_SLOT, 7
.equ R_DTPMOD64,  35
.equ R_TLSDESC,   36
.equ R_TPOFF64,   37
.equ R_GOTTPOFF,  39
.equ R_TPOFF32,   40
.equ R_DTPOFF64,  41
.equ R_IRELATIVE, 42

# .dynamic tags used by the loader
.equ DT_NULL,        0
.equ DT_NEEDED,      1
.equ DT_PLTRELSZ,    2
.equ DT_HASH,        4
.equ DT_STRTAB,      5
.equ DT_SYMTAB,      6
.equ DT_RELA,        7
.equ DT_RELASZ,      8
.equ DT_RELAENT,     9
.equ DT_STRSZ,       10
.equ DT_SYMENT,      11
.equ DT_INIT,        12
.equ DT_FINI,        13
.equ DT_JMPREL,      23
.equ DT_PLTREL,      24
.equ DT_INIT_ARRAY,  25
.equ DT_FINI_ARRAY,  26
.equ DT_INIT_ARRAYSZ,27
.equ DT_FINI_ARRAYSZ,28
.equ DT_RUNPATH,     29
.equ DT_FLAGS,       30
.equ DT_GNU_HASH,    0x6ffffef5
.equ DT_RELACOUNT,   0x6ffffff9
.equ DT_RELRSZ,      35
.equ DT_RELR,        36
.equ DT_RELRENT,     37

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

