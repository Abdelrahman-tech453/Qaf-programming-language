# ================================================================== loader ===
# src/dl.s — a minimal dynamic linker for x86-64 ELF shared objects.
#
# qafc is a static, pure-syscall executable, so it cannot use the real
# `dlopen`. This loader maps ET_DYN files into the process's own address
# space, resolves symbols (DT_GNU_HASH / DT_HASH), applies relocations
# (including static TLS and GNU ifunc), loads DT_NEEDED dependencies
# recursively and runs constructors — enough to bind libOpenCL (docs/gpu.md).
#
# API used by the runtime (wrappers live in runtime.s):
#   dl_init_once()                            idempotent arena/TLS setup
#   dl_open_file(rdi = NUL path)              -> rax = (dso index+1)   (0 = fail)
#   dl_lookup_symbol(rdi = idx+1, rsi=NUL name) -> rax = address      (0 = fail)
#   dl_last_error()                           -> rax = ptr to NUL error string
#
# Symbol-resolution rules: a dso's own table first, then every already-loaded
# dso in load order (previous indices), then the provided-stub table below.
# Load order is guaranteed post-order because dependencies are loaded before
# the dso's own relocations are run.
# =================================================================== code ===
.section .text

# ------------------------------------------------------------- dl_init_once --
# Sets up the fixed loader arena (PROT_NONE, grown by dl_next) and the static
# TLS region with a real %fs thread pointer so loaded code using %fs: offsets
# (including __tls_get_addr) works.
.global dl_init_once
dl_init_once:
    cmp qword ptr [dl_init_done], 0
    jne dl_init_once_ret
    xor edi, edi
    mov esi, 0x20000000                 # 512 MiB arena for libraries
    mov edx, 3                          # PROT_READ|PROT_WRITE (backing page maps)
    mov r10d, 0x22                      # MAP_PRIVATE|MAP_ANONYMOUS
    xor r8d, r8d
    xor r9d, r9d
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja dl_init_fail
    mov [dl_arena_base], rax
    mov [dl_next], rax
    xor edi, edi
    mov esi, DL_TLS_AREA
    mov edx, 3
    mov r10d, 0x22
    xor r8d, r8d
    xor r9d, r9d
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja dl_init_fail
    mov [dl_tls_area], rax
    lea rax, [rax + 0x400]              # this region doubles as the TCB area
    mov [dl_tp], rax
    mov [dl_tls_top], rax
    mov qword ptr [rax], rax            # tcb self pointer
    lea rcx, [native_dtv]
    mov qword ptr [rax + 8], rcx        # tcb->dtv
    mov qword ptr [native_dtv], 2       # dtv[0] = number of slots allotted
    mov rax, SYS_ARCH_PRCTL
    mov rdi, 0x1002                     # ARCH_SET_FS
    mov rsi, [dl_tp]
    syscall
    mov qword ptr [dl_init_done], 1
dl_init_once_ret:
    ret
dl_init_fail:
    lea rdi, [dl_err_mem]
    call dl_put_error
    mov rax, 1
    ret

# ------------------------------------------------------------- dl_put_error --
# rsi must become: string already NUL in .data … use rdi = NUL string instead.
# Contract: dl_put_error(rdi = NUL string) stores a copy for dlerror().
dl_put_error:
    push rdi
    push rcx
    push rsi
    xor rcx, rcx
    lea rsi, [dl_error_buf]
dl_pe_loop:
    cmp rcx, 250
    jge dl_pe_done
    mov al, [rdi + rcx]
    mov [rsi + rcx], al
    test al, al
    jz dl_pe_done
    inc rcx
    jmp dl_pe_loop
dl_pe_done:
    mov byte ptr [rsi + rcx], 0
    pop rsi
    pop rcx
    pop rdi
    ret

# ------------------------------------------------------------ string helpers --
# dl_streq: rdi = s1, rsi = s2 (both NUL) -> rax = 1/0
dl_streq:
    push rdi
    push rsi
    push rcx
dl_streq_loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne dl_streq_neq
    test al, al
    jz dl_streq_eq
    inc rdi
    inc rsi
    jmp dl_streq_loop
dl_streq_neq:
    xor eax, eax
    jmp dl_streq_out
dl_streq_eq:
    mov eax, 1
dl_streq_out:
    pop rcx
    pop rsi
    pop rdi
    ret

# dl_prov_match: rdi = name z, rsi = id (not NUL-terminated), rdx = id len -> 1/0
dl_prov_match:
    push rdi
    push rsi
    push rcx
    xor ecx, ecx
dl_pm_loop:
    cmp rcx, rdx
    jae dl_pm_endchk
    mov al, [rdi + rcx]
    mov r9b, [rsi + rcx]
    cmp al, r9b
    jne dl_pm_no
    inc ecx
    jmp dl_pm_loop
dl_pm_endchk:
    cmp byte ptr [rdi + rcx], 0
    jne dl_pm_no
    mov eax, 1
    jmp dl_pm_out
dl_pm_no:
    xor eax, eax
dl_pm_out:
    pop rcx
    pop rsi
    pop rdi
    ret

# dl_strcpy: rdi = dst, rsi = src -> rax = dst
dl_strcpy:
    push rdi
    push rcx
    mov rax, rdi
dl_strcpy_loop:
    mov cl, [rsi]
    mov [rdi], cl
    test cl, cl
    jz dl_strcpy_done
    inc rdi
    inc rsi
    jmp dl_strcpy_loop
dl_strcpy_done:
    pop rcx
    pop rdi
    ret

# dl_strcat: rdi = dst (NUL at current end), rsi = src -> rax = dst
dl_strcat:
    push rdi
    push rcx
    mov rax, rdi
dl_strcat_find:
    cmp byte ptr [rdi], 0
    je dl_strcat_copy
    inc rdi
    jmp dl_strcat_find
dl_strcat_copy:
    mov cl, [rsi]
    mov [rdi], cl
    test cl, cl
    jz dl_strcat_done
    inc rdi
    inc rsi
    jmp dl_strcat_copy
dl_strcat_done:
    pop rcx
    pop rdi
    ret

# dl_strlen: rdi = s -> rax = len
dl_strlen:
    push rdi
    mov rax, -1
dl_strlen_loop:
    inc rax
    cmp byte ptr [rdi + rax], 0
    jne dl_strlen_loop
    pop rdi
    ret

# dl_strchr_chk: rdi = s, esi = first char of name (for path checks); uses
# dl_strchr-style scan for '/' presence.
# dl_has_slash: rdi = s -> rax = 1 if contains '/'
dl_has_slash:
    push rdi
    xor eax, eax
    mov al, [rdi]
dl_hs_loop:
    cmp al, '/'
    je dl_hs_yes
    test al, al
    jz dl_hs_no
    inc rdi
    mov al, [rdi]
    jmp dl_hs_loop
dl_hs_yes:
    mov eax, 1
    jmp dl_hs_out
dl_hs_no:
    xor eax, eax
dl_hs_out:
    pop rdi
    ret

# ---------------------------------------------------------- hash functions --
# dl_hash (SysV ELF hash): rdi = s -> eax
dl_hash:
    push rdi
    push rcx
    push rdx
    xor eax, eax
dl_hash_loop:
    movzx ecx, byte ptr [rdi]
    test cl, cl
    jz dl_hash_done
    mov edx, eax
    shl edx, 4
    add eax, edx
    mov edx, eax
    shr edx, 24
    and edx, 0xF0
    xor eax, edx
    inc rdi
    jmp dl_hash_loop
dl_hash_done:
    pop rdx
    pop rcx
    pop rdi
    ret

# dl_gnu_hash: rdi = s -> eax
dl_gnu_hash:
    push rdi
    push rcx
    mov eax, 5381
dl_gnu_hash_loop:
    movzx ecx, byte ptr [rdi]
    test cl, cl
    jz dl_gnu_hash_done
    mov edx, eax
    shl edx, 5
    add eax, edx
    add eax, ecx
    inc rdi
    jmp dl_gnu_hash_loop
dl_gnu_hash_done:
    pop rcx
    pop rdi
    ret

# ----------------------------------------------------------- dl_lookup_in ---
# rdi = name (NUL), rsi = dso index -> rax = symbol table index, or -1.
dl_lookup_in:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    imul r13, r13, DSO_ENTRY_SIZE
    lea r14, [dl_table + r13]
    mov rax, [r14 + DSO_GNUHASH]
    test rax, rax
    jnz dl_li_gnu
    # ---- SysV hash ----
    mov rbx, [r14 + DSO_SYSVHASH]
    test rbx, rbx
    jz dl_li_notfound
    mov rdi, r12
    call dl_hash
    mov r15d, eax
    mov r8d, [rbx]                      # nbuckets
    test r8d, r8d
    jz dl_li_notfound
    lea r9, [rbx + 8]
    mov eax, r15d
    xor edx, edx
    div r8                              # rdx = bucket
    mov esi, [r9 + rdx*4]
    lea r9, [rbx + 8 + r8*4]            # chains
    mov r10, [r14 + DSO_SYMTAB]
    mov r11, [r14 + DSO_STRTAB]
dl_li_sysv_loop:
    test esi, esi
    jz dl_li_notfound
    mov rax, rsi
    imul rax, rax, 24
    mov edx, [r10 + rax]                # st_name
    mov rdi, r11
    add rdi, rdx
    mov rsi, r12
    call dl_streq
    test rax, rax
    jnz dl_li_found
    mov esi, [r9 + rsi*4]               # chains[i] -> next
    jmp dl_li_sysv_loop
    # ---- GNU hash ----
dl_li_gnu:
    mov rbx, [r14 + DSO_GNUHASH]
    mov rdi, r12
    call dl_gnu_hash
    mov r15d, eax
    mov r8d, [rbx]                      # nbuckets
    mov r9d, [rbx + 8]                  # bloom_size
    mov ecx, [rbx + 12]                 # bloom_shift
    test r9d, r9d
    jz dl_li_notfound
    lea r10, [rbx + 16]                 # bloom words
    mov rax, r15
    shr rax, 6
    xor edx, edx
    div r9                              # (h1>>6) % size
    mov rcx, [r10 + rdx*8]
    mov rdx, r15
    and edx, 63
    bt rcx, rdx
    jnc dl_li_notfound
    mov ecx, [rbx + 12]
    mov rax, r15
    shr rax, cl                         # h2 = h1 >> bloom_shift
    push rax
    shr rax, 6
    xor edx, edx
    div r9                              # (h2>>6) % size
    mov rcx, [r10 + rdx*8]
    mov rdx, [rsp]
    and edx, 63
    bt rcx, rdx
    pop rcx
    jnc dl_li_notfound
    mov rax, r15
    xor edx, edx
    div r8                              # rdx = bucket
    lea r11, [r10 + r9*8]               # buckets
    mov ecx, [r11 + rdx*4]              # first chain index
    mov r9d, [rbx + 4]                  # symoffset
    cmp ecx, r9d
    jb dl_li_notfound
    mov ebx, ecx
    mov eax, r8d
    lea r11, [r11 + rax*4]              # chains base
dl_li_gnu_chain:
    mov rax, rbx
    sub rax, r9
    mov eax, [r11 + rax*4]              # word
    mov edx, eax
    shr edx, 1
    mov eax, r15d
    shr eax, 1
    cmp edx, eax
    jne dl_li_gnu_next
    mov rax, rbx                        # index
    imul rax, rax, 24
    mov rcx, [r14 + DSO_SYMTAB]
    mov edx, [rcx + rax]                # st_name
    mov rcx, [r14 + DSO_STRTAB]
    mov rdi, rcx
    add rdi, rdx
    mov rsi, r12
    call dl_streq
    test eax, eax
    jnz dl_li_found
dl_li_gnu_next:
    mov rax, rbx
    sub rax, r9
    mov eax, [r11 + rax*4]
    test al, 1
    jnz dl_li_notfound
    inc ebx
    jmp dl_li_gnu_chain
dl_li_found:
    mov rax, rbx
    jmp dl_li_done
dl_li_notfound:
    mov rax, -1
dl_li_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ------------------------------------------------------------ dl_sym_addr ----
# rdi = dso index, rsi = symbol index -> rax
#   dl_reloc_marker = 0 : rax = absolute address of symbol
#   dl_reloc_marker = 1 : rax = TLS block-base offset from %fs (TP)
#   dl_reloc_marker = 2 : rax = ifunc resolver address
#   also: [dl_reloc_sv] = st_value, [dl_reloc_mod] = module id (order+1)
dl_sym_addr:
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    imul r12, r12, DSO_ENTRY_SIZE
    lea r14, [dl_table + r12]
    mov rax, [r14 + DSO_ORDER]
    inc rax
    mov [dl_reloc_mod], rax
    mov r15, [r14 + DSO_SYMTAB]
    mov rax, r13
    imul rax, rax, 24
    add r15, rax
    movzx ecx, word ptr [r15 + 6]       # st_shndx
    test ecx, ecx
    jz dl_sa_undef
    mov rdx, [r15 + 8]                  # st_value
    mov [dl_reloc_sv], rdx
    cmp ecx, 0xfff1                     # SHN_ABS
    je dl_sa_abs
    movzx eax, byte ptr [r15 + 4]       # st_info
    and eax, 15
    cmp eax, 6                          # STT_TLS
    je dl_sa_tls
    cmp eax, 10                         # STT_IFUNC
    je dl_sa_ifunc
    mov rax, [r14 + DSO_BASE]
    add rax, rdx
    mov qword ptr [dl_reloc_marker], 0
    mov qword ptr [dl_reloc_tlo], 0
    jmp dl_sa_done
dl_sa_abs:
    mov rax, rdx
    mov qword ptr [dl_reloc_marker], 0
    mov qword ptr [dl_reloc_tlo], 0
    jmp dl_sa_done
dl_sa_tls:
    mov rax, [r14 + DSO_TLSOFF]         # offset of block base from TP
    mov qword ptr [dl_reloc_tlo], rax
    mov qword ptr [dl_reloc_marker], 1
    jmp dl_sa_done
dl_sa_ifunc:
    mov rax, [r14 + DSO_BASE]
    add rax, rdx
    mov qword ptr [dl_reloc_marker], 2
    mov qword ptr [dl_reloc_tlo], 0
    jmp dl_sa_done
dl_sa_undef:
    xor eax, eax
    mov qword ptr [dl_reloc_marker], 0
    mov qword ptr [dl_reloc_sv], 0
    mov qword ptr [dl_reloc_tlo], 0
    mov qword ptr [dl_reloc_mod], 0
dl_sa_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

# ---------------------------------------------------------- dl_find_global ---
# rdi = name (NUL) -> rax = combined handle:
#    0                                     = not found
#    (dso_index<<32) | sym_index            = loaded-symbol handle
#    (0xFFFFFFFF<<32) | stub_index          = provided-stub handle
dl_find_global:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    xor r13, r13
    mov r14, [dl_count]
dl_fg_loop:
    cmp r13, r14
    jae dl_fg_provided
    mov rdi, r12
    mov rsi, r13
    call dl_lookup_in
    inc r13
    test rax, rax
    js dl_fg_loop
    dec r13
    push rax                            # sym index (r13 stays the dso index)
    mov rdx, r13
    imul rdx, rdx, DSO_ENTRY_SIZE
    lea rcx, [dl_table + rdx]
    mov rdx, [rcx + DSO_SYMTAB]
    mov rax, [rsp]
    imul rax, rax, 24
    add rdx, rax
    movzx ecx, word ptr [rdx + 6]       # st_shndx
    pop rax
    test ecx, ecx
    jz dl_fg_skip
    mov rdx, r13
    shl rdx, 32
    or rax, rdx
    jmp dl_fg_done
dl_fg_skip:
    inc r13
    jmp dl_fg_loop
dl_fg_provided:
    lea rbx, [dl_prov_syms]
dl_fg_p_loop:
    mov rcx, [rbx]
    test rcx, rcx
    jz dl_fg_notfound
    mov rsi, rcx
    mov rdx, [rbx + 8]
    mov rdi, r12
    push rbx
    call dl_prov_match
    pop rbx
    test eax, eax
    jnz dl_fg_prov_found
    add rbx, 24
    jmp dl_fg_p_loop
dl_fg_prov_found:
    mov rax, rbx
    lea rdx, [dl_prov_syms]
    sub rax, rdx
    mov rcx, 24
    xor edx, edx
    div rcx
    mov rdx, -1
    shl rdx, 32
    or rax, rdx
    jmp dl_fg_done
dl_fg_notfound:
    xor eax, eax
dl_fg_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ---------------------------------------------------------- dl_sym_to_addr ---
# rdi = combined handle from dl_find_global -> rax = absolute address or 0.
# Provides the address of plain symbols and of static-TLS symbols (which in
# our single-threaded model can be handed out directly).
dl_sym_to_addr:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rdi
    shr r13, 32
    mov r14d, edi                       # low 32 = sym/stub index
    cmp r13d, -1
    je dl_sta_prov
    imul r13, r13, DSO_ENTRY_SIZE
    lea r15, [dl_table + r13]
    mov rax, [r15 + DSO_SYMTAB]
    mov rcx, r14
    imul rcx, rcx, 24
    add rax, rcx
    movzx ecx, word ptr [rax + 6]
    test ecx, ecx
    jz dl_sta_zero
    mov rdx, [rax + 8]                  # st_value
    movzx eax, byte ptr [rax + 4]       # st_info
    and eax, 15
    cmp eax, 6                          # STT_TLS
    je dl_sta_tls
    mov rax, [r15 + DSO_BASE]
    add rax, rdx
    jmp dl_sta_done
dl_sta_tls:
    mov rax, [r15 + DSO_TLSOFF]
    mov rcx, [dl_tp]
    sub rcx, rax                        # block base absolute
    add rcx, rdx
    mov rax, rcx
    jmp dl_sta_done
dl_sta_prov:
    mov rax, r14
    imul rax, rax, 24
    lea rcx, [dl_prov_syms]
    add rcx, rax
    mov rax, [rcx + 16]
    jmp dl_sta_done
dl_sta_zero:
    xor eax, eax
dl_sta_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ============================================================ load engine ====
# ---------------------------------------------------------- dl_open_file ---
# Public entry point: rdi = NUL path or soname. Resolves library dirs when
# the name has no slash, then loads. Returns (dso index + 1) on success, 0 on
# failure with the reason recorded in dl_error_buf.
.global dl_open_file
dl_open_file:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    call dl_init_once
    mov byte ptr [dl_error_buf], 0
    mov rdi, r12
    call dl_has_slash
    test rax, rax
    jnz dl_of_direct
    mov rdi, r12
    call dl_resolve_needed              # search standard library dirs
    test rax, rax
    jz dl_of_nofile
    mov r12, rax
    jmp dl_of_load
dl_of_direct:
    mov rdi, r12
dl_of_load:
    call dl_load_path
    test rax, rax
    js dl_of_fail                      # -1 = error (index 0 is a valid result)
    inc rax                            # handle = index+1
    jmp dl_of_done
dl_of_nofile:
    lea rdi, [dl_err_open]
    call dl_put_error
    xor eax, eax
    jmp dl_of_done
dl_of_fail:
    xor eax, eax
dl_of_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

# -------------------------------------------------------- dl_load_path ------
# rdi = NUL path -> rax = dso index, or 0..-1 -> -1 on failure (error set).
# Internal: dedups, parses, maps, resolves dependencies, relocates, inits.
dl_load_path:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        # keep path across the whole load
    # --- dedup against already loaded libraries ---
    xor r13, r13
    mov rbx, [dl_count]
dl_lp_dedup:
    cmp r13, rbx
    jae dl_lp_dedup_done
    push r13
    imul r13, r13, DSO_ENTRY_SIZE
    lea rcx, [dl_table + r13]
    pop r13
    mov rsi, [rcx + DSO_NAMEPTR]
    test rsi, rsi
    jz dl_lp_dedup_next
    mov rdi, rdi                        # path (kept)
    call dl_streq
    test rax, rax
    jnz dl_lp_already
dl_lp_dedup_next:
    inc r13
    jmp dl_lp_dedup
dl_lp_dedup_done:
    mov rax, [dl_count]
    cmp rax, DL_DSO_MAX
    jae dl_lp_of
    # --- open the file ---
    mov rdi, rdi
    xor esi, esi
    mov rax, SYS_OPEN
    syscall
    cmp rax, -4096
    ja dl_lp_nofile
    mov r13, rax                        # fd
    # --- read and validate ELF header ---
    mov rdi, r13
    lea rsi, [dl_ehdr_buf]
    mov rdx, 96
    mov r10, 0
    mov rax, SYS_PREAD64
    syscall
    lea rbx, [dl_ehdr_buf]
    cmp dword ptr [rbx], 0x464c457f
    jne dl_lp_badelf
    cmp byte ptr [rbx + 4], 2           # ELFCLASS64
    jne dl_lp_badelf
    cmp word ptr [rbx + 16], 3          # ET_DYN
    jne dl_lp_badelf
    movzx r14d, word ptr [rbx + 56]     # e_phnum
    cmp r14d, 0xffff                    # PN_XNUM — unsupported
    je dl_lp_toomanyph
    cmp r14d, 96
    ja dl_lp_toomanyph
    # --- read program headers ---
    mov [dl_phnum], r14d
    mov rdi, r13
    lea rsi, [dl_phdr_buf]
    mov rcx, r14
    imul rcx, rcx, 56                   # count = phnum * sizeof(Elf64_Phdr)
    mov rdx, rcx
    mov r10, [rbx + 32]                 # e_phoff (64-bit)
    mov rax, SYS_PREAD64
    syscall
    # --- compute PT_LOAD span ---
    lea rbx, [dl_phdr_buf]
    mov r15, r14                        # phdr counter
    mov rax, -1                         # minv
    xor r9, r9                          # maxv
dl_lp_span:
    test r15, r15
    jz dl_lp_span_done
    cmp dword ptr [rbx], 1              # PT_LOAD
    jne dl_lp_span_next
    mov rcx, [rbx + 16]                 # p_vaddr
    cmp rcx, rax
    cmovb rax, rcx
    mov rdx, [rbx + 40]
    add rdx, rcx
    cmp rdx, r9
    cmova r9, rdx
dl_lp_span_next:
    add rbx, 56
    dec r15
    jmp dl_lp_span
dl_lp_span_done:
    cmp rax, -1
    je dl_lp_badelf
    mov r15, r9                         # span bytes (assuming vaddrs from ~0)
    mov rax, r15
    add rax, 4095
    and rax, -4096
    mov r15, rax
    mov [dl_lp_size], r15            # span survives the mapping loop
    # --- reserve arena region (PROT_NONE fixed) ---
    mov rdi, [dl_next]
    mov rsi, rax
    xor edx, edx
    mov r10d, 0x32                      # PRIVATE|ANON|FIXED
    xor r8d, r8d
    xor r9d, r9d
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja dl_lp_oom
    mov rbp, rax                        # base
    # --- map each PT_LOAD ---
    xor r8d, r8d
    lea rbx, [dl_phdr_buf]
dl_lp_map:
    cmp r8, r14
    jae dl_lp_map_done
    cmp dword ptr [rbx], 1
    jne dl_lp_map_next
    mov rcx, [rbx + 16]                 # p_vaddr
    mov rdx, [rbx + 40]                 # p_memsz
    mov rsi, [rbx + 32]                 # p_filesz
    mov rdi, [rbx + 8]                  # p_offset
    mov eax, [rbx + 4]                  # p_flags
    xor r9d, r9d
    test eax, 4
    jz dl_lp_prot_x
    or r9d, 1                           # R
dl_lp_prot_x:
    test eax, 2
    jz dl_lp_prot_w
    or r9d, 2                           # W
dl_lp_prot_w:
    test eax, 1
    jz dl_lp_prot_done
    or r9d, 4                           # X
dl_lp_prot_done:
    # rcx = p_vaddr, rdx = p_memsz, rsi = p_filesz, rdi = p_offset,
    # r9 = prot, rbp = base (arena), r13 = fd
    # map_off = p_vaddr - (p_offset & 0xfff) keeps the load bias consistent
    # even when segments are not page-aligned (delta = vaddr - offset).
    test rsi, rsi
    jz dl_lp_map_bss
    mov r15, rdi
    and r15, -4096                     # file_off = p_offset & ~PAGE
    mov rax, rdi
    and eax, 0xfff
    mov r11, rcx
    sub r11, rax                       # map_off
    lea rax, [rcx + rsi]               # data_end
    add rax, 4095
    and rax, -4096
    sub rax, r11                       # page_cover = round_up(data_end) - map_off
    mov r15, r11                       # map_off
    push rcx                           # vaddr      [rsp+56]
    push rdx                           # memsz      [rsp+48]
    push rdi                           # offset     [rsp+40]
    push rax                           # page_cover [rsp+32]
    push r15                           # map_off    [rsp+24]
    push r9                            # prot       [rsp+16]
    push r8                            # counter    [rsp+8]
    push rbx                           # phdr       [rsp+0]
    mov rdi, rbp
    add rdi, [rsp + 24]                # addr = base + map_off
    mov rsi, [rsp + 32]                # len = page_cover
    mov rdx, [rsp + 16]                # prot
    mov r10d, 0x12                     # MAP_PRIVATE|MAP_FIXED
    mov r8, r13                        # fd
    mov r9, [rsp + 40]
    and r9, -4096                      # offset & ~PAGE
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja dl_lp_map_fail
    # bss tail: if round_up(vaddr+memsz) > map_off + page_cover,
    # map anonymous RW pages over the remainder.
    mov rax, [rsp + 56]                # vaddr
    add rax, [rsp + 48]                # vaddr + memsz
    add rax, 4095
    and rax, -4096                     # round_up(vaddr+memsz)
    mov r11, [rsp + 24]
    add r11, [rsp + 32]                # map_off + page_cover
    cmp rax, r11
    jbe dl_lp_map_tail_done
    sub rax, r11                       # tail len
    mov rdi, rbp
    add rdi, r11                       # tail addr
    mov rsi, rax
    mov rdx, 3                         # RW
    mov r10d, 0x22                     # MAP_PRIVATE|MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja dl_lp_map_fail
dl_lp_map_tail_done:
    pop rbx                            # phdr       [rsp+0]
    pop r8                             # counter    [rsp+8]
    pop r9                             # prot       [rsp+16]
    pop r15                            # map_off    [rsp+24]
    pop rax                            # page_cover [rsp+32]
    pop rdi                            # offset     [rsp+40]
    pop rdx                            # memsz      [rsp+48]
    pop rcx                            # vaddr      [rsp+56]
    jmp dl_lp_map_next
dl_lp_map_bss:
    # filesz == 0: purely anonymous segment at [base + map_off]
    push rdi
    mov rdi, rdi
    and edi, 0xfff
    mov rax, rcx
    sub rax, rdi                       # map_off
    pop rdi
    mov r11, rbp
    add r11, rax                       # addr
    mov rsi, rcx
    add rsi, rdx
    add rsi, 4095
    and rsi, -4096
    sub rsi, rax                       # len
    mov rdi, r11
    mov rdx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov rax, SYS_MMAP
    syscall
    cmp rax, -4096
    ja dl_lp_bss_fail
    jmp dl_lp_map_next
dl_lp_bss_fail:
    lea rdi, [dl_err_mem]
    call dl_put_error
    mov rax, -1
    jmp dl_lp_done
dl_lp_map_next:
    add rbx, 56
    inc r8
    jmp dl_lp_map
# --- register the DSO ---
dl_lp_map_done:
    mov r14, [dl_count]
    mov rax, r14
    imul rax, rax, DSO_ENTRY_SIZE
    lea rbx, [dl_table + rax]
    mov [rbx + DSO_BASE], rbp
    mov r15, [dl_lp_size]
    mov [rbx + DSO_MSIZE], r15
    mov [rbx + DSO_ORDER], r14
    # store a durable copy of the path in the name bank (dl_path_buf is scratch)
    mov rax, r14
    shl rax, 8
    lea rdi, [dl_name_bank + rax]
    mov rsi, r12
    push rbx
    call dl_strcpy
    pop rbx
    mov [rbx + DSO_NAMEPTR], rax
    mov qword ptr [rbx + DSO_NAMELEN], 0
    inc qword ptr [dl_count]
    mov rax, r15
    add [dl_next], rax
    # close the fd (file content is mapped)
    mov rdi, r13
    mov rax, SYS_CLOSE
    syscall
    # parse dynamic section + TLS (phdr buffer still valid here)
    mov rdi, r14
    call dl_parse_dynamic
    mov rdi, r14
    call dl_assign_tls
    # load DT_NEEDED dependencies (recursion clobbers dl_phdr_buf — fine now)
    mov rdi, r14
    call dl_load_needed
    # relocate, then run constructors
    mov rdi, r14
    call dl_apply_relocs
    # constructors skipped for now (libc/ld-linux init needs full host bootstrap)
    mov rax, r14
    jmp dl_lp_done
# --- failure exits ---
dl_lp_already:
    mov rax, r13
    jmp dl_lp_done
dl_lp_of:
    lea rdi, [dl_err_mem]
    call dl_put_error
    mov rax, -1
    jmp dl_lp_done
dl_lp_nofile:
    lea rdi, [dl_err_open]
    call dl_put_error
    mov rax, -1
    jmp dl_lp_done
dl_lp_badelf:
    lea rdi, [dl_err_elf]
    call dl_put_error
    mov rdi, r13
    mov rax, SYS_CLOSE
    syscall
    mov rax, -1
    jmp dl_lp_done
dl_lp_toomanyph:
    lea rdi, [dl_err_phnum]
    call dl_put_error
    mov rdi, r13
    mov rax, SYS_CLOSE
    syscall
    mov rax, -1
    jmp dl_lp_done
dl_lp_oom:
    lea rdi, [dl_err_mem]
    call dl_put_error
    mov rdi, r13
    mov rax, SYS_CLOSE
    syscall
    mov rax, -1
    jmp dl_lp_done
dl_lp_map_fail:
    lea rdi, [dl_err_mem]
    call dl_put_error
    add rsp, 64
    mov rax, -1
    jmp dl_lp_done
dl_lp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

# ------------------------------------------------- dl_parse_dynamic ---------
# rdi = dso index. Fills the DSO_* fields from PT_DYNAMIC (and PT_TLS),
# processing DT_NEEDED by locating + loading them (parse is called before the
# recursive loads so phdr scratch is still valid).
dl_parse_dynamic:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    imul r12, r12, DSO_ENTRY_SIZE
    lea r15, [dl_table + r12]
    lea rbx, [dl_phdr_buf]
    mov ecx, [dl_phnum]
    xor eax, eax
dl_pd_phdr:
    test ecx, ecx
    jz dl_pd_none
    cmp dword ptr [rbx], 2              # PT_DYNAMIC
    je dl_pd_have_dyn
    cmp dword ptr [rbx], 7              # PT_TLS
    jne dl_pd_phdr_next
    mov rax, [rbx + 40]                 # p_memsz
    mov [r15 + DSO_TLSSIZE], rax
    mov rax, [rbx + 48]                 # p_align
    mov [r15 + DSO_TLSALIGN], rax
    jmp dl_pd_phdr_next
dl_pd_have_dyn:
    mov rax, [rbx + 16]                 # p_vaddr
    add rax, [r15 + DSO_BASE]
    mov [r15 + DSO_DYNAMIC], rax
dl_pd_phdr_next:
    add rbx, 56
    dec ecx
    jmp dl_pd_phdr
dl_pd_none:
    mov rax, [r15 + DSO_DYNAMIC]
    test rax, rax
    jz dl_pd_nodyn
    mov rbp, rax                         # dynamic pointer
    mov r13, [r15 + DSO_BASE]
dl_pd_loop:
    mov rax, [rbp]                       # d_tag
    test rax, rax
    jz dl_pd_tail
    mov rcx, [rbp + 8]                   # d_val
    cmp rax, DT_GNU_HASH
    je dl_pd_set_gnu
    cmp rax, DT_HASH
    je dl_pd_set_sysv
    cmp rax, DT_STRTAB
    je dl_pd_set_strtab
    cmp rax, DT_SYMTAB
    je dl_pd_set_symtab
    cmp rax, DT_RELA
    je dl_pd_set_rela
    cmp rax, DT_RELASZ
    je dl_pd_set_relsz
    cmp rax, DT_JMPREL
    je dl_pd_set_jmprel
    cmp rax, DT_PLTRELSZ
    je dl_pd_set_pltsz
    cmp rax, DT_PLTREL
    je dl_pd_set_plttype
    cmp rax, DT_RELR
    je dl_pd_set_relr
    cmp rax, DT_RELRSZ
    je dl_pd_set_relrsz
    cmp rax, DT_INIT
    je dl_pd_set_init
    cmp rax, DT_INIT_ARRAY
    je dl_pd_set_initarr
    cmp rax, DT_INIT_ARRAYSZ
    je dl_pd_set_initsz
    cmp rax, DT_STRTAB
    je dl_pd_set_strtab
    mov r8, r13                          # base
    cmp rax, DT_NEEDED
    je dl_pd_needed
    jmp dl_pd_next
dl_pd_set_gnu:
    add rcx, r13
    mov [r15 + DSO_GNUHASH], rcx
    jmp dl_pd_next
dl_pd_set_sysv:
    add rcx, r13
    mov [r15 + DSO_SYSVHASH], rcx
    jmp dl_pd_next
dl_pd_set_strtab:
    add rcx, r13
    mov [r15 + DSO_STRTAB], rcx
    jmp dl_pd_next
dl_pd_set_symtab:
    add rcx, r13
    mov [r15 + DSO_SYMTAB], rcx
    jmp dl_pd_next
dl_pd_set_rela:
    add rcx, r13
    mov [r15 + DSO_RELADD], rcx
    jmp dl_pd_next
dl_pd_set_relsz:
    mov [r15 + DSO_RELSZ], rcx
    jmp dl_pd_next
dl_pd_set_jmprel:
    add rcx, r13
    mov [r15 + DSO_PLTREL], rcx
    jmp dl_pd_next
dl_pd_set_pltsz:
    mov [r15 + DSO_PLTRELSZ], rcx
    jmp dl_pd_next
dl_pd_set_plttype:
    mov [r15 + DSO_PLTRELTYPE], rcx
    jmp dl_pd_next
dl_pd_set_relr:
    add rcx, r13
    mov [r15 + DSO_RELR], rcx
    jmp dl_pd_next
dl_pd_set_relrsz:
    mov [r15 + DSO_RELRSZ], rcx
    jmp dl_pd_next
dl_pd_set_init:
    add rcx, r13
    mov [r15 + DSO_INIT], rcx
    jmp dl_pd_next
dl_pd_set_initarr:
    add rcx, r13
    mov [r15 + DSO_INITARRAY], rcx
    jmp dl_pd_next
dl_pd_set_initsz:
    mov [r15 + DSO_INITSZ], rcx
    jmp dl_pd_next
dl_pd_needed:
    # NEEDED handling is left to dl_load_needed (called after parse, when
    # DSO_STRTAB is set). Resolving here would see DSO_STRTAB == 0 yet.
    jmp dl_pd_next
dl_pd_next:
    add rbp, 16
    jmp dl_pd_loop
dl_pd_tail:
    # (DT_INIT may equal base in weird files; leave as-is)
    mov rax, [r15 + DSO_GNUHASH]
    test rax, rax
    jz dl_pd_sysv_check
    jmp dl_pd_have
dl_pd_sysv_check:
    mov rax, [r15 + DSO_SYSVHASH]
    test rax, rax
    jnz dl_pd_have
    mov rax, [r15 + DSO_RELADD]
    test rax, rax
    jz dl_pd_nohash_fallback            # no symbols at all — static-ish .so
dl_pd_have:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret
dl_pd_nodyn:
    lea rdi, [dl_err_dyn]
    call dl_put_error
    jmp dl_pd_end
dl_pd_nohash_fallback:
    mov qword ptr [r15 + DSO_SYSVHASH], 0
dl_pd_end:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

# ---------------------------------------------------------- dl_assign_tls ----
# rdi = dso index. Allocates the module a static-TLS block growing down from
# the thread pointer; records tlsoff (TP -> block base) and the DTV slot.
dl_assign_tls:
    push rbx
    push rcx
    push rdx
    push r12
    imul r12, rdi, DSO_ENTRY_SIZE
    lea r12, [dl_table + r12]
    mov rdx, [r12 + DSO_TLSSIZE]
    test rdx, rdx
    jz dl_at_done
    mov rax, [r12 + DSO_TLSALIGN]
    test rax, rax
    jz dl_at_set_off
    dec rax
    not rax
    mov rcx, [dl_tls_top]
    sub rcx, rdx
    and rcx, rax                         # aligned block base
    mov [dl_tls_top], rcx
    mov rax, [dl_tp]
    sub rax, rcx                         # tlsoff
    mov [r12 + DSO_TLSOFF], rax
    mov rdx, [r12 + DSO_ORDER]
    inc rdx
    mov [native_dtv + rdx*8], rcx        # dtv[modid] = block base
    jmp dl_at_done
dl_at_set_off:
    mov rcx, [dl_tls_top]
    sub rcx, rdx
    mov [dl_tls_top], rcx
    mov rax, [dl_tp]
    sub rax, rcx
    mov [r12 + DSO_TLSOFF], rax
    mov rdx, [r12 + DSO_ORDER]
    inc rdx
    mov [native_dtv + rdx*8], rcx
dl_at_done:
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

# -------------------------------------------------------- dl_load_needed -----
# rdi = dso index. Walks DT_NEEDED and loads any not yet loaded.
dl_load_needed:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    imul r12, r12, DSO_ENTRY_SIZE
    lea r14, [dl_table + r12]
    mov rbp, [r14 + DSO_DYNAMIC]
    mov r15, [r14 + DSO_BASE]
    mov r13, [r14 + DSO_STRTAB]
dl_ln_loop:
    mov rax, [rbp]
    test rax, rax
    jz dl_ln_done
    cmp rax, DT_NEEDED
    jne dl_ln_next
    mov rcx, [rbp + 8]
    mov rdi, r13
    add rdi, rcx                         # name
    call dl_resolve_needed
    test rax, rax
    jz dl_ln_next
    mov rdi, rax
    call dl_load_path
dl_ln_next:
    add rbp, 16
    jmp dl_ln_loop
dl_ln_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# ------------------------------------------------------ dl_resolve_needed ----
# rdi = soname (NUL, no slash) -> rax = NUL full path in dl_path_buf, or 0.
dl_resolve_needed:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rbp, r12                         # rbp = name (for concatenation)
    lea r13, [dl_path_buf]
    lea r14, [dl_lib_dirs]
dl_rn_dir:
    mov rsi, [r14]
    test rsi, rsi
    jz dl_rn_notfound
    mov r15, [r14 + 8]                   # dir len (unused; dirs are NUL-terminated)
    mov rdi, r13
    push r14
    push r15
    call dl_strcpy
    mov rdi, r13
    lea rsi, [dl_slash]
    call dl_strcat
    mov rdi, r13
    mov rsi, r12
    call dl_strcat
    pop r15
    pop r14
    # probe-open
    mov rdi, r13
    xor esi, esi
    mov rax, SYS_OPEN
    syscall
    cmp rax, -4096
    ja dl_rn_next
    mov rdi, rax
    mov rax, SYS_CLOSE
    syscall
    mov rax, r13
    jmp dl_rn_done
dl_rn_next:
    add r14, 16
    jmp dl_rn_dir
dl_rn_notfound:
    xor eax, eax
dl_rn_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# -------------------------------------------------------- dl_apply_relocs ----
# rdi = dso index. Applies .rela.dyn then .rela.plt, then a final IRELATIVE
# pass (resolvers may reference other symbols).
dl_apply_relocs:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi                          # dso index (preserved: 7 pushed)
    imul r12, rbx, DSO_ENTRY_SIZE
    lea r12, [dl_table + r12]
    mov rbp, [r12 + DSO_BASE]
    # pass 1: rela.dyn (skip IRELATIVE)
    mov r8, [r12 + DSO_RELADD]
    mov r9, [r12 + DSO_RELSZ]
dl_ar_rela:
    test r9, r9
    jz dl_ar_jmprel
    sub r9, 24
    mov eax, [r8 + 8]                   # low 32 of r_info = type
    cmp eax, R_IRELATIVE
    je dl_ar_rela_next                   # IRELATIVE defers to the resolver pass
    push rbx
    push r8
    push r9
    mov rdi, rbx
    mov rsi, r8
    mov rdx, rbp
    call dl_do_rela
    pop r9
    pop r8
    pop rbx
dl_ar_rela_next:
    add r8, 24
    jmp dl_ar_rela
dl_ar_jmprel:
    mov rax, [r12 + DSO_PLTRELTYPE]
    cmp rax, 7
    jne dl_ar_irel
    mov r8, [r12 + DSO_PLTREL]
    mov r9, [r12 + DSO_PLTRELSZ]
dl_ar_jmp:
    test r9, r9
    jz dl_ar_irel
    sub r9, 24
    push rbx
    push r8
    push r9
    mov rdi, rbx
    mov rsi, r8
    mov rdx, rbp
    call dl_do_rela
    pop r9
    pop r8
    pop rbx
    add r8, 24
    jmp dl_ar_jmp
    # pass 3: IRELATIVE first over rela.dyn
dl_ar_irel:
    mov rdi, rbx
    mov r8, [r12 + DSO_RELADD]
    mov r9, [r12 + DSO_RELSZ]
dl_ar_irel_loop:
    test r9, r9
    jz dl_ar_relr
    mov rax, [r8 + 8]
    mov ecx, eax
    cmp ecx, R_IRELATIVE
    jne dl_ar_irel_next
    push rbx
    push r8
    push r9
    mov rdi, rbx
    mov rsi, r8
    mov rdx, rbp
    call dl_do_rela
    pop r9
    pop r8
    pop rbx
dl_ar_irel_next:
    sub r9, 24
    add r8, 24
    jmp dl_ar_irel_loop
    # pass 4: RELR compact relative relocations. No symbols, no addends.
    #   even word -> location offset w: store (B+w) at [B+w]
    #   odd  word -> bitmap: bit i (1..63) applies a relocation at curOff+i*8
dl_ar_relr:
    mov rbp, [r12 + DSO_BASE]   # resolvers may have clobbered base
    mov r8, [r12 + DSO_RELR]
    mov r9, [r12 + DSO_RELRSZ]
    test r9, r9
    jz dl_ar_done
dl_ar_relr_loop:
    test r9, r9
    jz dl_ar_done
    mov rax, [r8]
    test rax, 1
    jnz dl_ar_relr_bitmap
    mov r10, rbp
    add r10, rax                    # addr = B + off
    mov rdx, [r10]                  # value = existing content + B
    add rdx, rbp
    mov [r10], rdx
    add r8, 8
    sub r9, 8
    jmp dl_ar_relr_loop
dl_ar_relr_bitmap:
    xor rcx, rcx
dl_ar_relr_bit:
    inc rcx
    cmp rcx, 64
    jae dl_ar_relr_next
    bt rax, rcx
    jnc dl_ar_relr_bit
    lea rdx, [r10 + rcx*8]
    mov rax, [rdx]
    add rax, rbp
    mov [rdx], rax
    jmp dl_ar_relr_bit
dl_ar_relr_next:
    add r8, 8
    sub r9, 8
    jmp dl_ar_relr_loop
dl_ar_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

# ------------------------------------------------------------ dl_do_rela -----
# rdi = dso index, rsi = rela*, rdx = base. Applies one relocation.
dl_do_rela:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        # dso index
    mov r13, rsi                        # rela*
    mov r14, rdx                        # base
    mov rbx, [r13]                      # r_offset
    mov r15, [r13 + 16]                 # r_addend
    mov rax, [r13 + 8]
    shr rax, 32                         # sym index
    lea r8, [r14 + rbx]                 # P = base + r_offset
    xor r9, r9                          # S
    test rax, rax
    jz dl_dr_dispatch                   # sym index 0 (RELATIVE / IRELATIVE)
    mov rdi, r12
    mov rsi, rax
    call dl_sym_addr
    mov r9, rax
    mov rdx, [dl_reloc_marker]
    cmp rdx, 2
    je dl_dr_ifunc
    cmp rdx, 1
    je dl_dr_dispatch                   # TLS symbol: dispatch uses slots
    test r9, r9
    jnz dl_dr_dispatch                  # defined locally
    # --- undefined in this dso: resolve via global scope / provided stubs ---
    push r12
    imul r12, r12, DSO_ENTRY_SIZE
    lea rax, [dl_table + r12]
    pop r12
    mov rcx, [rax + DSO_SYMTAB]
    mov rax, [r13 + 8]
    shr rax, 32
    imul rax, rax, 24
    mov esi, [rcx + rax]                # st_name
    push r12
    imul r12, r12, DSO_ENTRY_SIZE
    mov rcx, [dl_table + r12 + DSO_STRTAB]
    pop r12
    add rsi, rcx
    mov rdi, rsi
    push r8
    push r15
    call dl_find_global
    pop r15
    pop r8
    test rax, rax
    jz dl_dr_fail
    push r8
    push r15
    mov rdi, rax
    call dl_sym_to_addr
    pop r15
    pop r8
    mov r9, rax
    mov qword ptr [dl_reloc_marker], 0
    mov qword ptr [dl_reloc_tlo], 0
    jmp dl_dr_dispatch
dl_dr_ifunc:
    push r8
    push r15
    call r9                             # resolver()
    pop r15
    pop r8
    mov r9, rax
    mov qword ptr [dl_reloc_marker], 0
dl_dr_dispatch:
    mov ecx, [r13 + 8]                  # type (low 32 of r_info)
    cmp ecx, R_RELATIVE
    je dl_dr_relative
    cmp ecx, R_64
    je dl_dr_64
    cmp ecx, R_PC32
    je dl_dr_pc32
    cmp ecx, R_GLOB_DAT
    je dl_dr_gd
    cmp ecx, R_JUMP_SLOT
    je dl_dr_gd
    cmp ecx, R_DTPMOD64
    je dl_dr_dtpmod
    cmp ecx, R_DTPOFF64
    je dl_dr_dtpoff
    cmp ecx, R_TPOFF64
    je dl_dr_tpoff64
    cmp ecx, R_TPOFF32
    je dl_dr_tpoff32
    cmp ecx, R_GOTTPOFF
    je dl_dr_gottpoff
    cmp ecx, R_TLSDESC
    je dl_dr_tlsdesc
    cmp ecx, R_IRELATIVE
    je dl_dr_irelative
    # unsupported relocation type — record and continue
    lea rdi, [dl_err_reloc]
    call dl_put_error
    jmp dl_dr_done
dl_dr_relative:
    mov rax, r14
    add rax, r15
    mov [r8], rax
    jmp dl_dr_done
dl_dr_64:
    mov rax, r9
    add rax, r15
    mov [r8], rax
    jmp dl_dr_done
dl_dr_pc32:
    mov rax, r9
    add rax, r15
    sub rax, r8
    mov [r8], eax
    jmp dl_dr_done
dl_dr_gd:
    mov [r8], r9
    jmp dl_dr_done
dl_dr_irelative:
    push r8
    push r15
    mov rax, r14
    add rax, r15                        # resolver = base + addend
    call rax
    pop r15
    pop r8
    mov [r8], rax
    jmp dl_dr_done
dl_dr_dtpmod:
    mov rax, [dl_reloc_mod]
    mov [r8], rax
    jmp dl_dr_done
dl_dr_dtpoff:
    mov rax, [dl_reloc_sv]
    add rax, r15
    mov [r8], rax
    jmp dl_dr_done
dl_dr_tpoff64:
    mov rax, [dl_reloc_marker]
    cmp rax, 1
    jne dl_dr_tpoff_plain
    mov rax, [dl_reloc_sv]
    mov rcx, [dl_reloc_tlo]
    sub rax, rcx                        # st_value - tlsoff
    add rax, r15
    mov [r8], rax
    jmp dl_dr_done
dl_dr_tpoff_path:
    mov rax, r9
    mov rcx, [dl_tp]
    sub rax, rcx                        # absolute addr - TP
    add rax, r15
    mov [r8], rax
    jmp dl_dr_done
dl_dr_tpoff_plain:
    jmp dl_dr_tpoff_path
dl_dr_tpoff32:
    mov rax, [dl_reloc_sv]
    mov rcx, [dl_reloc_tlo]
    sub rax, rcx
    add rax, r15
    mov [r8], eax
    jmp dl_dr_done
dl_dr_gottpoff:
    mov rax, [dl_reloc_sv]
    add rax, r15
    mov rcx, [dl_reloc_tlo]
    sub rax, rcx
    mov [r8], rax
    jmp dl_dr_done
dl_dr_tlsdesc:
    lea rax, [qaf_tlsdesc_return]
    mov qword ptr [r8], rax
    mov rax, [dl_reloc_sv]
    add rax, r15
    mov rcx, [dl_reloc_tlo]
    sub rax, rcx
    mov [r8 + 8], rax
    jmp dl_dr_done
dl_dr_fail:
    lea rdi, [dl_err_sym]
    call dl_put_error
dl_dr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# ------------------------------------------------------------ dl_run_init ----
# rdi = dso index. Calls DT_INIT then each DT_INIT_ARRAY entry in order.
dl_run_init:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    imul r12, r12, DSO_ENTRY_SIZE
    lea r13, [dl_table + r12]
    mov rax, [r13 + DSO_INIT]
    test rax, rax
    jz dl_ri_arr
    call rax
dl_ri_arr:
    mov rbp, [r13 + DSO_INITARRAY]
    mov rcx, [r13 + DSO_INITSZ]
    xor r14, r14
dl_ri_loop:
    cmp r14, rcx
    jae dl_ri_done
    mov rax, [rbp + r14]
    test rax, rax
    jz dl_ri_next
    call rax
dl_ri_next:
    add r14, 8
    jmp dl_ri_loop
dl_ri_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

# ---------------------------------------------------------- dl_lookup_symbol --
# Public: rdi = handle (dso index+1), rsi = NUL name -> rax = address (0 fail).
.global dl_lookup_symbol
dl_lookup_symbol:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    test rdi, rdi
    jz dl_ls_notfound
    dec rdi
    cmp rdi, [dl_count]
    jae dl_ls_notfound
    mov rdi, r12
    call dl_find_global
    test rax, rax
    jz dl_ls_notfound
    mov rdi, rax
    call dl_sym_to_addr
    test rax, rax
    jz dl_ls_notfound
    jmp dl_ls_done
dl_ls_notfound:
    lea rdi, [dl_err_sym]
    call dl_put_error
    xor eax, eax
dl_ls_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

# ----------------------------------------------------------- dl_last_error ---
# Public: -> rax = NUL error string.
.global dl_last_error
dl_last_error:
    lea rax, [dl_error_buf]
    ret

# ===================================================== provided libc subset ==
# These are what loaded libraries bind against instead of real glibc. All
# follow the SysV ABI (preserve rbx/rbp/r12-r15; we additionally preserve r8).

qaf_dlopen_stub:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    call dl_init_once
    mov byte ptr [dl_error_buf], 0
    mov rdi, r12
    call dl_has_slash
    test rax, rax
    jnz qaf_dlo_direct
    mov rdi, r12
    call dl_resolve_needed
    test rax, rax
    jz qaf_dlo_zero
    mov r12, rax
qaf_dlo_direct:
    mov rdi, r12
    call dl_load_path
    test rax, rax
    jle qaf_dlo_zero
    inc rax                              # handle = index+1
    jmp qaf_dlo_done
qaf_dlo_zero:
    xor eax, eax
qaf_dlo_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

qaf_dlsym_stub:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    test rdi, rdi                          # handle (index+1) or 0
    jz qaf_dls_zero
    mov rsi, r12
    call dl_lookup_symbol
    jmp qaf_dls_done
qaf_dls_zero:
    xor eax, eax
qaf_dls_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

qaf_dlclose_stub:
    xor eax, eax
    ret

qaf_dlerror_stub:
    lea rax, [dl_error_buf]
    ret

qaf_tls_get_addr:
    push rdx
    mov rdx, rdi
    mov rax, [rdx]                        # mod
    mov rcx, [rdx + 8]                    # off
    test rax, rax
    jz qaf_tga_zero
    cmp rax, DL_DSO_MAX
    ja qaf_tga_zero
    lea rax, [native_dtv + rax*8]
    mov rax, [rax]
    add rax, rcx
    pop rdx
    ret
qaf_tga_zero:
    mov rax, rcx
    pop rdx
    ret

qaf_tlsdesc_return:
    mov rax, [rdi + 8]
    ret

qaf_malloc:
    push rcx
    mov rcx, rdi
    add rcx, 15
    and rcx, -16
    mov rdx, [dl_ml_pos]
    add rdx, rcx
    cmp rdx, [dl_ml_end]
    jbe qaf_ma_fit
    push rcx
    xor edi, edi
    mov esi, 0x400000
    mov edx, 3
    mov r10d, 0x22
    xor r8d, r8d
    xor r9d, r9d
    mov rax, SYS_MMAP
    syscall
    pop rcx
    cmp rax, -4096
    ja qaf_ma_fail
    mov [dl_ml_pos], rax
    lea rdx, [rax + 0x400000]
    mov [dl_ml_end], rdx
    mov rdx, [dl_ml_pos]
    add rdx, rcx
qaf_ma_fit:
    mov rax, [dl_ml_pos]
    mov [dl_ml_pos], rdx
    pop rcx
    ret
qaf_ma_fail:
    xor eax, eax
    pop rcx
    ret

qaf_free:
    ret

qaf_calloc:
    push rcx
    mov rax, rdi
    mul rsi                              # rdx:rax = n*size
    test rdx, rdx
    jnz qaf_ca_bad
    mov rcx, rax                         # total
    push rcx
    mov rdi, rax
    call qaf_malloc
    test rax, rax
    jz qaf_ca_bad2
    mov r10, rax
    pop rcx                              # total
    mov rdi, r10
    xor eax, eax
    rep stosb
    mov rax, r10
    pop rcx
    ret
qaf_ca_bad2:
    pop rcx
qaf_ca_bad:
    xor eax, eax
    pop rcx
    ret

qaf_realloc:
    push rbx
    push rbp
    push r8
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        # old
    mov r13, rsi                        # newsize
    mov rdi, r13
    call qaf_malloc
    test rax, rax
    jz qaf_re_done
    mov r14, rax                        # new
    test r12, r12
    jz qaf_re_new
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call qaf_memcpy
qaf_re_new:
    mov rax, r14
qaf_re_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r8
    pop rbp
    pop rbx
    ret

qaf_memcpy:                              # rdi=dst, rsi=src, rdx=n  (no overlap)
    push rdi
    mov rcx, rdx
    rep movsb
    pop rdi
    ret

qaf_memmove:                             # overlap-safe copy
    push rdi
    mov rcx, rdx
    cmp rsi, rdi
    jae qaf_mm_fwd
    lea rax, [rsi + rcx]
    cmp rdi, rax
    jae qaf_mm_fwd
    lea rdi, [rdi + rcx - 1]
    lea rsi, [rsi + rcx - 1]
    std
    rep movsb
    cld
    pop rdi
    ret
qaf_mm_fwd:
    rep movsb
    pop rdi
    ret

qaf_memset:                              # rdi=s, esi=c, rdx=n
    push rdi
    mov rax, rsi
    mov rcx, rdx
    rep stosb
    pop rdi
    ret

qaf_memcmp:                              # rdi=s1, rsi=s2, rdx=n -> rax
    push rdi
    push rsi
    push rdx
    xor eax, eax
qaf_mc_loop:
    cmp rax, rdx
    jae qaf_mc_eq
    movzx ecx, byte ptr [rdi + rax]
    movzx r8d, byte ptr [rsi + rax]
    cmp ecx, r8d
    je qaf_mc_next
    sub ecx, r8d
    mov eax, ecx
    jmp qaf_mc_done
qaf_mc_next:
    inc rax
    jmp qaf_mc_loop
qaf_mc_eq:
    xor eax, eax
qaf_mc_done:
    pop rdx
    pop rsi
    pop rdi
    ret

qaf_strlen:                              # rdi=s -> rax
    push rdi
    mov rax, -1
qaf_sl_loop:
    inc rax
    cmp byte ptr [rdi + rax], 0
    jne qaf_sl_loop
    pop rdi
    ret

qaf_strcmp:
    push rdi
    push rsi
qaf_sc_loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne qaf_sc_diff
    test al, al
    jz qaf_sc_eq
    inc rdi
    inc rsi
    jmp qaf_sc_loop
qaf_sc_eq:
    xor eax, eax
    jmp qaf_sc_done
qaf_sc_diff:
    movzx eax, al
    movzx ecx, cl
    sub eax, ecx
qaf_sc_done:
    pop rsi
    pop rdi
    ret

qaf_strchr:                              # rdi=s, esi=c -> rax ptr or 0
    movzx eax, sil
    mov cl, al
qaf_sch_loop:
    mov al, [rdi]
    cmp al, cl
    je qaf_sch_hit
    test al, al
    jz qaf_sch_miss
    inc rdi
    jmp qaf_sch_loop
qaf_sch_hit:
    mov rax, rdi
    ret
qaf_sch_miss:
    xor eax, eax
    ret

qaf_strrchr:                             # rdi=s, esi=c -> rax
    movzx ecx, sil
    xor eax, eax
qaf_srr_loop:
    mov dl, [rdi]
    cmp dl, cl
    jne qaf_srr_next
    mov rax, rdi
qaf_srr_next:
    test dl, dl
    jz qaf_srr_done
    inc rdi
    jmp qaf_srr_loop
qaf_srr_done:
    ret

qaf_strncpy:                             # rdi=dst, rsi=src, rdx=n
    push rdi
    mov rcx, rdx
qaf_snc_loop:
    test rcx, rcx
    jz qaf_snc_done
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz qaf_snc_pad
    inc rsi
qaf_snc_pad:
    inc rdi
    dec rcx
    jmp qaf_snc_loop
qaf_snc_done:
    pop rdi
    ret

qaf_abort:
    mov rax, SYS_WRITE
    mov rdi, 2
    lea rsi, [msg_abort]
    mov rdx, msg_abort_len
    syscall
    mov rax, SYS_EXIT
    mov rdi, 134
    syscall

qaf_exit:                                # rdi = status
    mov rax, SYS_EXIT
    syscall

qaf_pthread_once:                        # rdi=once ptr, rsi=fn
    cmp byte ptr [rdi], 0
    jne qaf_po_ret
    mov byte ptr [rdi], 1
    jmp rsi
qaf_po_ret:
    ret

qaf_mutex_lock:
qaf_mutex_unlock:
qaf_mutex_init:
    ret

qaf_errno_loc:
    lea rax, [dl_errno_slot]
    ret

qaf_sched_yield:
    ret

qaf_getpid:
    mov rax, 39
    syscall
    ret

qaf_open:                                # rdi=path, esi=flags -> fd
    mov rax, SYS_OPEN
    syscall
    ret

qaf_close:                               # rdi=fd
    mov rax, SYS_CLOSE
    syscall
    ret

qaf_read:                                # rdi=fd, rsi=buf, rdx=n
    mov rax, SYS_READ
    syscall
    ret

qaf_write:                               # rdi=fd, rsi=buf, rdx=n
    mov rax, SYS_WRITE
    syscall
    ret

qaf_ioctl:                               # rdi=fd, esi=req, rdx=arg
    mov rax, SYS_IOCTL
    syscall
    ret

qaf_mmap:                                # rdi=addr, rsi=len, rdx=prot, r10->flags, r8=fd, r9=off
    mov r10, rcx                         # 4th arg arrives in rcx per SysV
    mov r8, r8
    mov r9, r9
    mov rax, SYS_MMAP
    syscall
    ret

qaf_munmap:                              # rdi=addr, rsi=len
    mov rax, SYS_MUNMAP
    syscall
    ret

qaf_mprotect:                            # rdi=addr, rsi=len, rdx=prot
    mov rax, SYS_MPROTECT
    syscall
    ret

qaf_syscall:                             # n in rdi, a1..a6 -> syscall args
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov r10, r8
    mov r8, r9
    mov r9, [rsp + 8]                    # 6th arg passed on the stack
    syscall
    ret
