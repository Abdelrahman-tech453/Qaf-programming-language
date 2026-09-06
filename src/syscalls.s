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
    cmp qword ptr [repl_active], 0
    jne die_repl
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
    cmp qword ptr [repl_active], 0
    jne die_repl
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# die_repl: when a parse or runtime error fires inside the interactive REPL,
# unwind the stack back to the saved rsp and continue with the next line.
die_repl:
    mov rsp, [repl_rspsave]
    jmp repl_recover

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
# rdi = NUL-terminated module name. Resolves the file by trying, in order:
#   * the current working directory,
#   * the directory of the top-level program file,
#   * the directory containing the qafc executable,
#   * the <qafc dir>/lib standard-library directory,
#   * the <parent of qafc dir>/lib/qaf conventional install directory,
# each with the module name as-is and with a ".qf" suffix (see try_import_path
# in imports.s). On success reads the file into import_buf, sets src_len and
# lex_src_ptr, and returns rax = 0. Returns rax = -1 on failure (the caller
# reports the error).
load_import:
    push rbx
    push r12
    mov rbx, rdi              # rbx = module name

    # Root 1: current working directory
    xor rdi, rdi
    mov rsi, rbx
    call try_import_path
    cmp rax, 0
    jge load_import_rd

    # Root 2: directory of the top-level program file
    cmp qword ptr [main_dir_len], 0
    jz load_import_try_bin
    lea rdi, [main_dir_buf]
    mov rsi, rbx
    call try_import_path
    cmp rax, 0
    jge load_import_rd

load_import_try_bin:
    # Root 3: directory containing the qafc executable
    cmp qword ptr [qaf_bin_dir_len], 0
    jz load_import_try_lib
    lea rdi, [qaf_bin_dir_buf]
    mov rsi, rbx
    call try_import_path
    cmp rax, 0
    jge load_import_rd

load_import_try_lib:
    # Root 4: <qafc dir>/lib standard-library directory
    cmp qword ptr [qaf_bin_lib_len], 0
    jz load_import_try_sys
    lea rdi, [qaf_bin_lib_buf]
    mov rsi, rbx
    call try_import_path
    cmp rax, 0
    jge load_import_rd

load_import_try_sys:
    # Root 5: <parent of qafc dir>/lib/qaf — the conventional installed layout
    cmp qword ptr [qaf_data_lib_len], 0
    jz load_import_fail
    lea rdi, [qaf_data_lib_buf]
    mov rsi, rbx
    call try_import_path
    cmp rax, 0
    jge load_import_rd

load_import_fail:
    mov rax, -1
    pop r12
    pop rbx
    ret

load_import_rd:
    mov r12, rax              # r12 = open fd
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
