# ================================================================= imports ==
# Module ("import") file resolution.
#
# Imports are resolved against five roots, tried in order:
#   * the current working directory
#   * the directory containing the top-level program file (main_dir_buf)
#   * the directory containing the qafc executable itself (qaf_bin_dir_buf)
#   * the <qafc dir>/lib standard-library dir (qaf_bin_lib_buf)
#   * the <parent of qafc dir>/lib/qaf conventional install dir (qaf_data_lib_buf)
# Each root is tried with the bare name and with a ".qf" suffix, so a module
# can be found no matter where qafc is invoked from. See load_import (in
# syscalls.s) for the search loop; this file provides the path helpers.

# ---------------------------------------------------------------- try_open_path
# rdi = NUL-terminated path -> rax = fd (>= 0) or -1.
try_open_path:
    xor rsi, rsi              # O_RDONLY
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    cmp rax, 0
    jl try_open_path_fail
    ret
try_open_path_fail:
    mov rax, -1
    ret

# ---------------------------------------------------------------- strcpy_nul
# rdi = dst, rsi = src (NUL-terminated). Copies bytes including the NUL.
# On return rdi points at the written NUL byte.
strcpy_nul:
    movzx eax, byte ptr [rsi]
    test al, al
    jz strcpy_nul_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp strcpy_nul
strcpy_nul_done:
    mov byte ptr [rdi], 0
    ret

# ---------------------------------------------------------------- try_import_path
# rdi = root directory (NUL-terminated, or 0 for the current directory),
# rsi = module name (NUL-terminated). Builds "<root>/<name>" (or "<name>" for
# the CWD root) and "<root>/<name>.qf" in import_path_buf and tries opening
# each. Returns rax = fd (>= 0) on success, -1 when neither candidate exists.
try_import_path:
    push rbx
    push r12
    mov rbx, rdi              # rbx = root
    mov r12, rsi              # r12 = module name
    lea rdi, [import_path_buf]
    test rbx, rbx
    jz try_import_path_name
try_import_path_copy_root:
    movzx eax, byte ptr [rbx]
    test al, al
    jz try_import_path_root_done
    mov [rdi], al
    inc rbx
    inc rdi
    jmp try_import_path_copy_root
try_import_path_root_done:
    mov byte ptr [rdi], '/'
    inc rdi
try_import_path_name:
    mov rsi, r12
    call strcpy_nul           # rdi = NUL byte position
    lea rdi, [import_path_buf]
    call try_open_path
    cmp rax, 0
    jge try_import_path_done
    lea rdi, [import_path_buf]
    call append_qf_path
    lea rdi, [import_path_buf]
    call try_open_path
    cmp rax, 0
    jge try_import_path_done
    mov rax, -1
try_import_path_done:
    pop r12
    pop rbx
    ret

# ---------------------------------------------------------------- append_qf_path
# rdi = buffer holding a NUL-terminated string; appends a ".qf" suffix.
append_qf_path:
    call strnul               # rdi = position of the NUL byte
    mov byte ptr [rdi], '.'
    mov byte ptr [rdi + 1], 'q'
    mov byte ptr [rdi + 2], 'f'
    mov byte ptr [rdi + 3], 0
    ret

# ---------------------------------------------------------------- strnul
# rdi = NUL-terminated string -> on return rdi points at the NUL byte.
strnul:
    cmp byte ptr [rdi], 0
    je strnul_done
    inc rdi
    jmp strnul
strnul_done:
    ret

# ---------------------------------------------------------------- extract_dir
# rdi = NUL-terminated path, rsi = output directory buffer, rdx = dir-length
# slot (8 bytes). Copies the directory part (everything up to the last '/',
# separator excluded) into the buffer and stores its length.
#
#   "examples/math.qf" -> "examples"  (len 9)
#   "./demo.qf"        -> "."         (len 1)
#   "/a/b/c.qf"        -> "/a/b"      (len 4)
#   "/foo.qf"          -> "/"         (len 1)
#   "demo.qf"          -> ""          (len 0)
extract_dir:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi              # rbx = path
    mov r14, rsi              # r14 = output buffer
    mov r12, rdx              # r12 = length slot
    mov qword ptr [r12], 0
    xor rcx, rcx              # rcx = scan index
    mov r13, -1               # r13 = index of the last '/', -1 if none
extract_dir_scan:
    movzx eax, byte ptr [rbx + rcx]
    test al, al
    jz extract_dir_scan_done
    cmp al, '/'
    jne extract_dir_scan_next
    mov r13, rcx
extract_dir_scan_next:
    inc rcx
    cmp rcx, 500
    jle extract_dir_scan
extract_dir_scan_done:
    cmp r13, 0
    jl extract_dir_none       # no '/': bare filename
    jnz extract_dir_copy      # r13 > 0 -> dir is [0..r13)
    mov r13, 1                # r13 == 0 -> the directory is '/'
extract_dir_copy:
    mov [r12], r13
    xor rdx, rdx
extract_dir_copy_loop:
    cmp rdx, r13
    jge extract_dir_done
    mov al, [rbx + rdx]
    mov [r14 + rdx], al
    inc rdx
    jmp extract_dir_copy_loop
extract_dir_none:
    mov qword ptr [r12], 0
extract_dir_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------------------------------------------------------- extract_main_dir
# rdi = NUL-terminated path of the top-level program file. Records its
# directory in main_dir_buf / main_dir_len for import resolution.
extract_main_dir:
    push rsi
    push rdx
    lea rsi, [main_dir_buf]
    lea rdx, [main_dir_len]
    call extract_dir
    pop rdx
    pop rsi
    ret

# ---------------------------------------------------------------- extract_parent_dir
# rdi = NUL-terminated path, rsi = output buffer, rdx = length slot (8 bytes).
# Like extract_dir but drops the final path component too, so the parent of a
# directory is produced (handy for conventional "$prefix/lib/qaf" installs):
#   "/usr/local/bin" -> "/usr/local"  (len 11)
#   "/bin"           -> "/"           (len 1)
#   "relative/x"     -> "relative"    (len 8)
#   "x"              -> ""            (len 0)
extract_parent_dir:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi              # rbx = path
    mov r14, rsi              # r14 = output buffer
    mov r12, rdx              # r12 = length slot
    mov qword ptr [r12], 0
    xor rcx, rcx              # rcx = scan index
    mov r13, -1               # r13 = index of the last '/', -1 if none
extract_parent_dir_scan:
    movzx eax, byte ptr [rbx + rcx]
    test al, al
    jz extract_parent_dir_scan_done
    cmp al, '/'
    jne extract_parent_dir_next
    mov r13, rcx
extract_parent_dir_next:
    inc rcx
    cmp rcx, 500
    jle extract_parent_dir_scan
extract_parent_dir_scan_done:
    cmp r13, 0
    jl extract_parent_dir_none   # no '/' at all: no parent directory
    jnz extract_parent_dir_copy  # last '/' at index > 0
    mov byte ptr [r14], '/'      # path was "/..." -> parent is '/'
    mov qword ptr [r12], 1
    jmp extract_parent_dir_done
extract_parent_dir_copy:
    mov [r12], r13
    xor rdx, rdx
extract_parent_dir_copy_loop:
    cmp rdx, r13
    jge extract_parent_dir_done
    mov al, [rbx + rdx]
    mov [r14 + rdx], al
    inc rdx
    jmp extract_parent_dir_copy_loop
extract_parent_dir_none:
    mov qword ptr [r12], 0
extract_parent_dir_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------------------------------------------------------- compute_bin_dir
# Resolves the qafc executable's own path (/proc/self/exe), records its
# directory in qaf_bin_dir_buf / qaf_bin_dir_len, and computes two standard
# library locations:
#   * "<qafc dir>/lib"           in qaf_bin_lib_buf  (dev layout: ./lib)
#   * "<parent of qafc dir>/lib/qaf" in qaf_data_lib_buf (installed layout)
# so stdlib-style modules can be imported no matter what the current directory
# is, whether qafc is run from the repository or from $prefix/bin/qafc.
compute_bin_dir:
    push rsi
    push rdx
    lea rdi, [proc_self_exe]
    lea rsi, [qaf_bin_path_buf]
    mov rdx, 1024
    mov rax, SYS_READLINK
    syscall
    cmp rax, 0
    jl compute_bin_dir_skip
    mov byte ptr [qaf_bin_path_buf + rax], 0
    lea rdi, [qaf_bin_path_buf]
    lea rsi, [qaf_bin_dir_buf]
    lea rdx, [qaf_bin_dir_len]
    call extract_dir
    # Build "<qaf_bin_dir>/lib" into qaf_bin_lib_buf.
    lea rdi, [qaf_bin_lib_buf]
    lea rsi, [qaf_bin_dir_buf]
    call strcpy_nul           # rdi = NUL position in qaf_bin_lib_buf
    mov byte ptr [rdi], '/'
    mov byte ptr [rdi + 1], 'l'
    mov byte ptr [rdi + 2], 'i'
    mov byte ptr [rdi + 3], 'b'
    mov byte ptr [rdi + 4], 0
    lea rdi, [qaf_bin_lib_buf]
    call strnul
    lea rax, [qaf_bin_lib_buf]
    sub rdi, rax
    mov [qaf_bin_lib_len], rdi
    # Build "<parent of qaf_bin_dir>/lib/qaf" into qaf_data_lib_buf.
    lea rdi, [qaf_bin_dir_buf]
    lea rsi, [qaf_data_lib_buf]
    lea rdx, [qaf_data_lib_len]
    call extract_parent_dir
    cmp qword ptr [qaf_data_lib_len], 0
    jz compute_bin_dir_done
    lea rdi, [qaf_data_lib_buf]
    call strnul              # rdi = NUL position
    mov byte ptr [rdi], '/'
    mov byte ptr [rdi + 1], 'l'
    mov byte ptr [rdi + 2], 'i'
    mov byte ptr [rdi + 3], 'b'
    mov byte ptr [rdi + 4], '/'
    mov byte ptr [rdi + 5], 'q'
    mov byte ptr [rdi + 6], 'a'
    mov byte ptr [rdi + 7], 'f'
    mov byte ptr [rdi + 8], 0
    lea rdi, [qaf_data_lib_buf]
    call strnul
    lea rax, [qaf_data_lib_buf]
    sub rdi, rax
    mov [qaf_data_lib_len], rdi
compute_bin_dir_done:
    pop rdx
    pop rsi
    ret
compute_bin_dir_skip:
    mov qword ptr [qaf_bin_dir_len], 0
    mov qword ptr [qaf_bin_lib_len], 0
    mov qword ptr [qaf_data_lib_len], 0
    pop rdx
    pop rsi
    ret
