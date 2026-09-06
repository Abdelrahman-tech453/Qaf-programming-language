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

# Import path resolution: imports are searched in the current directory first,
# then in the directory containing the top-level program file (main_dir), then
# in the directory containing the qafc executable (qaf_bin_dir).
main_dir_buf:   .skip 512         # directory of the top-level program file
main_dir_len:   .skip 8           # 0 = no directory component (bare filename)
qaf_bin_path_buf: .skip 1024      # resolved path of the qafc executable
qaf_bin_path_len: .skip 8
qaf_bin_dir_buf:  .skip 512       # directory containing the qafc executable
qaf_bin_dir_len:  .skip 8
qaf_bin_lib_buf:  .skip 520       # <qafc dir>/lib — shipped standard library dir
qaf_bin_lib_len:  .skip 8
qaf_data_lib_buf: .skip 520       # <parent of qafc dir>/lib/qaf — conventional
qaf_data_lib_len: .skip 8         # install layout ($prefix/lib/qaf)
import_path_buf: .skip 1024       # scratch buffer for candidate import paths

# Interactive REPL state
repl_active:    .skip 8           # 1 while in the interactive REPL loop
repl_rspsave:   .skip 8           # rsp to restore when aborting parse/exec errors
repl_line_buf:  .skip 4096        # one line of user input

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
builtin_dlopen_sym:  .skip 8
builtin_dlsym_sym:   .skip 8
builtin_call_native_sym:   .skip 8
builtin_call_native_f_sym: .skip 8
builtin_dlerror_sym: .skip 8
f_tmp:            .skip 8           # 8-byte scratch for FPU transcendentals

# ------------------------------------------------------- native/loader state --
# Dynamic loader (src/dl.s) working state. dl_table is an array of fixed-size
# DSO_ENTRY_SIZE descriptors (see defs.s).
dl_table:       .skip DL_DSO_MAX * DSO_ENTRY_SIZE
dl_count:       .skip 8            # number of loaded shared objects
dl_arena_base:  .skip 8            # base of the fixed loader arena
dl_next:        .skip 8            # next free address in the loader arena
dl_lp_size:     .skip 8            # PT_LOAD span of the dso currently mapping
dl_init_done:   .skip 8            # 1 once the loader (TLS/arena) is prepared
dl_tp:          .skip 8            # thread pointer value (%fs base) installed
dl_tls_top:     .skip 8            # current static-TLS allocation top
dl_tls_area:    .skip 8            # mmap base of the static TLS region
dl_error_buf:   .skip 256          # last dlerror() message (NUL-terminated)
dl_path_buf:    .skip 512          # scratch NUL-terminated path
dl_ehdr_buf:    .skip 96           # ELF header read buffer
dl_phdr_buf:    .skip 96*56        # program-header read buffer
dl_name_bank:   .skip DL_DSO_MAX*256   # durable copies of library paths
native_mode:    .skip 8            # native_call return mode (0=int, 1=float)
# native-argument marshalling scratch (see native_call in runtime.s)
native_args_buf:   .skip DL_ARGS_MAX*8
native_xmm_buf:    .skip 8*8
native_gp_buf:     .skip 6*8      # GP register slots rdi..r9 for native_call
native_gp_count:   .skip 8        # number of GP args gathered
native_xmm_count:  .skip 8        # number of float args gathered
dl_nc_sav:         .skip 8        # native_call entry stack pointer
native_dtv:        .skip 8* (DL_DSO_MAX + 4)   # TLS dynamic-thread-vector <-> static blocks
dl_errno_slot:     .skip 8            # errno interpose slot for loaded libs
dl_ml_pos:         .skip 8            # malloc bump pointer (provided libc subset)
dl_ml_end:         .skip 8
dl_reloc_marker:   .skip 8            # dl_reloc_resolve output: 0 addr,1 tls,2 ifunc,3 stub
dl_reloc_sv:       .skip 8            # st_value of the relocation symbol
dl_reloc_tlo:      .skip 8            # TLS block-base offset from TP of the symbol
dl_reloc_mod:      .skip 8            # module id (load order + 1) of the symbol
dl_phnum:          .skip 8            # retained e_phnum of the dso being parsed

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

