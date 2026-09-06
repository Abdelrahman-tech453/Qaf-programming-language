.section .data
msg_repl_banner:    .ascii "Qaf interactive shell\nType statements or function definitions, e.g.:\n  print 1 + 2;\n  fn sq(x) { return x * x; }\n  print sq(9);\nPress Ctrl+D to exit.\n"
msg_repl_banner_len = . - msg_repl_banner
msg_repl_prompt:    .ascii "qaf> "
msg_repl_prompt_len = . - msg_repl_prompt
msg_repl_bye:       .ascii "\n"
msg_repl_bye_len = . - msg_repl_bye
proc_self_exe:      .asciz "/proc/self/exe"
proc_self_exe_len = . - proc_self_exe
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
msg_dl:             .ascii "qaf: dl: "
msg_dl_len = . - msg_dl
msg_dl_of:          .ascii "qaf: dl: too many libs\n"
msg_dl_of_len = . - msg_dl_of
msg_dl_native:      .ascii "qaf: dl: unsupported relocation type\n"
msg_dl_native_len = . - msg_dl_native
msg_dl_mem:         .ascii "qaf: dl: out of loader memory\n"
msg_dl_mem_len = . - msg_dl_mem
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
msg_abort:          .ascii "qaf: abort called from loaded library\n"
msg_abort_len = . - msg_abort
dl_err_open:        .asciz "cannot open library"
dl_err_elf:         .asciz "bad ELF file"
dl_err_phnum:       .asciz "too many program headers"
dl_err_dyn:         .asciz "no dynamic section"
dl_err_sym:         .asciz "symbol not found"
dl_err_mem:         .asciz "out of loader memory"
dl_err_reloc:       .asciz "unsupported relocation type"
dl_slash:           .asciz "/"
dl_lib_dirs:
    .quad dl_dir_libx, 21
    .quad dl_dir_usrlib, 25
    .quad dl_dir_lib64, 6
    .quad dl_dir_lib, 4
    .quad dl_dir_usr, 8
    .quad 0
dl_dir_libx:    .asciz "/lib/x86_64-linux-gnu"
dl_dir_usrlib:  .asciz "/usr/lib/x86_64-linux-gnu"
dl_dir_lib64:   .asciz "/lib64"
dl_dir_lib:     .asciz "/lib"
dl_dir_usr:     .asciz "/usr/lib"
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
bname_dlopen:       .ascii "dlopen"
bname_dlsym:        .ascii "dlsym"
bname_call_native:  .ascii "call_native"
bname_call_native_f:.ascii "call_native_f"
bname_dlerror:      .ascii "dlerror"

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
# ---- symbols provided to loaded libraries (src/dl.s stubs) ----
# DSO_USER additions below; dl_prov_syms is (name ptr, name len, stub addr) triples.
dl_prov_syms:
    .quad prov_dlopen, 6, qaf_dlopen_stub
    .quad prov_dlsym, 5, qaf_dlsym_stub
    .quad prov_dlclose, 7, qaf_dlclose_stub
    .quad prov_dlerror, 7, qaf_dlerror_stub
    .quad prov_tls_get_addr, 13, qaf_tls_get_addr
    .quad prov_tlsdesc_return, 18, qaf_tlsdesc_return
    .quad prov_tlsdesc_dyn, 25, qaf_tlsdesc_return
    .quad prov_malloc, 6, qaf_malloc
    .quad prov_free, 4, qaf_free
    .quad prov_realloc, 7, qaf_realloc
    .quad prov_calloc, 6, qaf_calloc
    .quad prov_memcpy, 6, qaf_memcpy
    .quad prov_memmove, 7, qaf_memmove
    .quad prov_memset, 6, qaf_memset
    .quad prov_memcmp, 6, qaf_memcmp
    .quad prov_strlen, 6, qaf_strlen
    .quad prov_strcmp, 6, qaf_strcmp
    .quad prov_strchr, 6, qaf_strchr
    .quad prov_strncpy, 7, qaf_strncpy
    .quad prov_strrchr, 7, qaf_strrchr
    .quad prov_abort, 5, qaf_abort
    .quad prov_exit, 4, qaf_exit
    .quad prov_pthread_once, 11, qaf_pthread_once
    .quad prov_mutex_lock, 18, qaf_mutex_lock
    .quad prov_mutex_unlock, 20, qaf_mutex_unlock
    .quad prov_mutex_init, 18, qaf_mutex_init
    .quad prov_mutex_destroy, 21, qaf_mutex_init
    .quad prov_errno_loc, 15, qaf_errno_loc
    .quad prov_sched_yield, 11, qaf_sched_yield
    .quad prov_getpid, 6, qaf_getpid
    .quad prov_open, 4, qaf_open
    .quad prov_close, 5, qaf_close
    .quad prov_read, 4, qaf_read
    .quad prov_write, 5, qaf_write
    .quad prov_ioctl, 5, qaf_ioctl
    .quad prov_mmap, 4, qaf_mmap
    .quad prov_munmap, 6, qaf_munmap
    .quad prov_mprotect, 8, qaf_mprotect
    .quad prov_syscall, 7, qaf_syscall
    .quad 0
prov_dlopen:        .asciz "dlopen"
prov_dlsym:         .asciz "dlsym"
prov_dlclose:       .asciz "dlclose"
prov_dlerror:       .asciz "dlerror"
prov_tls_get_addr:  .asciz "__tls_get_addr"
prov_tlsdesc_return:.asciz "_dl_tlsdesc_return"
prov_tlsdesc_dyn:   .asciz "_dl_tlsdesc_dynamic_return"
prov_malloc:        .asciz "malloc"
prov_free:          .asciz "free"
prov_realloc:       .asciz "realloc"
prov_calloc:        .asciz "calloc"
prov_memcpy:        .asciz "memcpy"
prov_memmove:       .asciz "memmove"
prov_memset:        .asciz "memset"
prov_memcmp:        .asciz "memcmp"
prov_strlen:        .asciz "strlen"
prov_strcmp:        .asciz "strcmp"
prov_strchr:        .asciz "strchr"
prov_strncpy:       .asciz "strncpy"
prov_strrchr:       .asciz "strrchr"
prov_abort:         .asciz "abort"
prov_exit:          .asciz "exit"
prov_pthread_once:  .asciz "pthread_once"
prov_mutex_lock:    .asciz "pthread_mutex_lock"
prov_mutex_unlock:  .asciz "pthread_mutex_unlock"
prov_mutex_init:    .asciz "pthread_mutex_init"
prov_mutex_destroy: .asciz "pthread_mutex_destroy"
prov_errno_loc:     .asciz "__errno_location"
prov_sched_yield:   .asciz "sched_yield"
prov_getpid:        .asciz "getpid"
prov_open:          .asciz "open"
prov_close:         .asciz "close"
prov_read:          .asciz "read"
prov_write:         .asciz "write"
prov_ioctl:         .asciz "ioctl"
prov_mmap:          .asciz "mmap"
prov_munmap:        .asciz "munmap"
prov_mprotect:      .asciz "mprotect"
prov_syscall:       .asciz "syscall"

