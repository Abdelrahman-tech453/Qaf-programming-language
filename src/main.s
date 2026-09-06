# ---------------------------------------------------------------- _start --
_start:
    mov qword ptr [node_n], 1      # node 0 is reserved as "null"
    mov qword ptr [call_depth], 0
    mov qword ptr [fn_n], 0
    mov qword ptr [str_n], 0
    mov qword ptr [str_pool_pos], 0
    call register_builtins
    call compute_bin_dir      # locate stdlib-style modules next to qafc
    mov rax, [rsp]                 # argc
    cmp rax, 2
    jl start_repl                  # no program file: interactive REPL
    mov rdi, [rsp + 16]            # argv[1]
    cmp byte ptr [rdi], 'r'
    jne start_program
    cmp byte ptr [rdi + 1], 'e'
    jne start_program
    cmp byte ptr [rdi + 2], 'p'
    jne start_program
    cmp byte ptr [rdi + 3], 'l'
    jne start_program
    jmp start_repl                 # program name "repl": interactive REPL
start_program:
    call extract_main_dir          # remember argv[1]'s dir for import resolution
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
    lea rsi, [bname_dlopen]
    mov rdx, 6
    call resolve_symbol
    mov [builtin_dlopen_sym], rax
    lea rsi, [bname_dlsym]
    mov rdx, 5
    call resolve_symbol
    mov [builtin_dlsym_sym], rax
    lea rsi, [bname_call_native]
    mov rdx, 11
    call resolve_symbol
    mov [builtin_call_native_sym], rax
    lea rsi, [bname_call_native_f]
    mov rdx, 13
    call resolve_symbol
    mov [builtin_call_native_f_sym], rax
    lea rsi, [bname_dlerror]
    mov rdx, 7
    call resolve_symbol
    mov [builtin_dlerror_sym], rax
    pop rbx
    ret
