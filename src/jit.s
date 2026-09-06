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
    cmp rax, ND_DLOPEN
    je jit_emit_expr_dlopen
    cmp rax, ND_DLSYM
    je jit_emit_expr_dlsym
    cmp rax, ND_CALL_NATIVE
    je jit_emit_expr_call_native
    cmp rax, ND_CALL_NATIVE_F
    je jit_emit_expr_call_native_f
    cmp rax, ND_DLERROR
    je jit_emit_expr_dlerror
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
jit_emit_expr_dlopen:
    lea rdi, [dlopen_builtin]
    call jit_emit_call1
    jmp jit_emit_expr_done
jit_emit_expr_dlsym:
    lea rdi, [dlsym_builtin]
    call jit_emit_call2
    jmp jit_emit_expr_done
jit_emit_expr_dlerror:
    lea rdi, [dlerror_builtin]
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    jmp jit_emit_expr_done
# call_native / call_native_f: variadic; node_a = raw arg count, node_b = args
# (arg0 = function address). Emits the same push sequence as list_call, then
# rdi=count; rax=helper; call rax; add rsp, count*8. The JIT frame stays
# 16-aligned because count*8 is a multiple of 8.
jit_emit_expr_call_native:
    lea rdi, [native_call]
    jmp jit_emit_expr_call_native_common
jit_emit_expr_call_native_f:
    lea rdi, [native_call_f]
jit_emit_expr_call_native_common:
    push rbx
    push r13
    push r14
    push r15
    mov r14, rdi
    mov r13, [node_a + r12*8]
    mov r15, [node_b + r12*8]
jit_emit_expr_call_native_args:
    test r15, r15
    jz jit_emit_expr_call_native_args_done
    push r15
    mov rdi, r15
    call jit_emit_expr
    mov al, 0x50
    call jit_emit_byte
    pop r15
    mov r15, [node_next + r15*8]
    jmp jit_emit_expr_call_native_args
jit_emit_expr_call_native_args_done:
    mov rdi, r13
    call jit_emit_mov_rdi_imm
    mov rdi, r14
    call jit_emit_mov_rax_imm
    lea rsi, [enc_call_rax]
    mov rcx, 2
    call jit_emit_bytes
    mov rdi, r13
    shl rdi, 3
    call jit_emit_add_rsp
    pop r15
    pop r14
    pop r13
    pop rbx
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

