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

# ======================================================= native bindings ====
# dlopen_builtin: rdi = string value (path) -> rax = tagged int handle (0 = fail)
.global dlopen_builtin
dlopen_builtin:
    push rbx
    push r8
    mov rax, rdi
    and rax, 7
    cmp rax, TAG_STR
    jne dlob_zerovieut                    # (never taken for tagged strings; see below)
    mov rax, rdi
    and rax, -8                          # bufbase
    add rax, 8                           # NUL-terminated path bytes
    mov rdi, rax
    call dl_open_file
    test rax, rax
    jz dlob_zero
    shl rax, 3
    pop r8
    pop rbx
    ret
dlob_zero:
    xor eax, eax
    pop r8
    pop rbx
    ret
dlob_zerovieut:
    xor eax, eax
    pop r8
    pop rbx
    ret

# dlsym_builtin: rdi = tagged int handle, rsi = string value (name) -> rax
.global dlsym_builtin
dlsym_builtin:
    push rbx
    push r8
    mov rax, rsi
    and rax, 7
    cmp rax, TAG_STR
    jne dlsym_type
    mov rax, rdi
    test rax, rax
    jz dlsym_zero
    shr rax, 3                           # handle raw (dso index+1)
    and rsi, -8
    add rsi, 8                           # name bytes
    mov rdi, rax
    call dl_lookup_symbol
    test rax, rax
    jz dlsym_zero
    shl rax, 3
    pop r8
    pop rbx
    ret
dlsym_zero:
    xor eax, eax
    pop r8
    pop rbx
    ret
dlsym_type:
    lea rdi, [msg_type]
    mov rsi, msg_type_len
    call die

# dlerror_builtin: () -> rax = string value
.global dlerror_builtin
dlerror_builtin:
    push rbx
    push r8
    call dl_last_error
    mov rsi, rax
    mov rbx, rsi
    push rbx
    mov rdi, rbx
    call dl_strlen
    pop rsi
    mov rdi, rax
    call mk_str_bytes
    pop r8
    pop rbx
    ret

# mk_str_bytes: rdi = len, rsi = bytes -> rax = string value (bytes + NUL copy)
mk_str_bytes:
    push rbx
    push r8
    mov rbx, rdi
    lea rdi, [rbx + 9]
    call heap_alloc
    mov [rax], rbx
    lea rdi, [rax + 8]
    mov rcx, rbx
    push rax
    rep movsb
    pop rax
    mov byte ptr [rax + 8 + rbx], 0
    lea rax, [rax + TAG_STR]
    pop r8
    pop rbx
    ret

# ========================================================== native_call ====
# See the marshalling design in src/eval.s (eval_call_native). Args arrive on
# the stack in the order they were pushed (arg0 first, so arg0 sits deepest):
#   [rsp]     = return address
#   [rsp+8]   = last argument
#   [rsp+8k]  = count-k-th argument  (arg0 at [rsp + 8 + (count-1)*8])
# rdi = total argument count. native_call copies the args out lowest-first so
# that native_args_buf[0] is arg0 (the function address).
# The target function follows the SysV calling convention; floats (tag 1) are
# routed to XMM registers, everything else is routed to the integer/pointer
# register sequence. Beyond 6 GP args the overflow is pushed onto the stack in
# ABI order. The caller (eval / JIT) pops the arguments itself afterwards.
native_mode_int  = 0
native_mode_float = 1

# decoded raw C argument for an XMM / GP slot; sequences below.
native_decode_arg:
    mov rbx, rax
    and ebx, 7
    cmp ebx, 3                    # string -> NUL-terminated byte pointer
    jne native_dec_int
    and rax, -8
    add rax, 8
    ret
native_dec_int:
    sar rax, 3
    ret

# native_call: rdi = count -> rax = tagged int result
.global native_call
native_call:
    push rbp
    push r8
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [dl_nc_sav], rsp
    mov r12, rdi
    test r12, r12
    jz native_done_int
    cmp r12, DL_ARGS_MAX
    jg native_too_many
    # --- copy args into native_args_buf. eval calls the arg chain in order
    # (node_b = function first, then following args), pushing each result, so
    # on entry the block is [rsp+56+count*8] = function, with the remaining
    # args DESCENDING toward [rsp+56+8] = last arg. Walk the block downward
    # while filling buf[0..] so that buf[0]=function, buf[1..]=args. ---
    lea rsi, [rsp + 56 + r12*8]
    lea rdi, [native_args_buf]
    mov rcx, r12
native_marshal_loop:
    mov rax, [rsi]
    mov [rdi], rax
    sub rsi, 8
    add rdi, 8
    dec rcx
    jnz native_marshal_loop
    # --- classify args (skip arg0 = the function address) ---
    mov qword ptr [native_gp_count], 0
    mov qword ptr [native_xmm_count], 0
    mov r13, [native_args_buf]
    shr r13, 3                           # target address
    mov r14, 0                           # arg index counter (1-based start)
    mov r10, r12
native_cls_loop:
    inc r14
    cmp r14, r10
    jae native_cls_done
    mov rax, [native_args_buf + r14*8]
    mov rdx, rax
    and edx, 7
    cmp edx, TAG_FLOAT
    je native_cls_xmm
    # general-purpose argument
    mov rcx, [native_gp_count]
    cmp rcx, 9                           # room for up to 10 GP args < DL_ARGS_MAX
    jae native_too_many
    call native_decode_arg
    mov rcx, [native_gp_count]
    mov [native_gp_buf + rcx*8], rax
    inc qword ptr [native_gp_count]
    jmp native_cls_loop
native_cls_xmm:
    mov rcx, [native_xmm_count]
    cmp rcx, 8
    jae native_too_many
    and rax, -8
    movq xmm0, rax
    movq [native_xmm_buf + rcx*8], xmm0
    inc qword ptr [native_xmm_count]
    jmp native_cls_loop
native_cls_done:
    # target 0 (failed dlsym) -> return 0
    test r13, r13
    jz native_done_int
    # --- push overflow GP args on the stack, 16-byte aligned ---
    # r13 = target (preserve), r14 = tmp
    mov rax, [native_gp_count]
    sub rax, 6
    mov r14, rax                         # overflow count (>= 0)
    jle native_no_overflow
    lea rax, [r14*8 + 15]
    and rax, -16
    sub rsp, rax                         # reserve; mod16 unchanged
    mov rax, rsp
    and eax, 15
    mov rcx, r14
    and ecx, 1
    shl ecx, 3
    cmp eax, ecx
    je native_no_pad
    push rax                             # alignment pad
native_no_pad:
    lea rsi, [native_gp_buf + 48]
    mov rcx, r14
native_push_stack:
    test rcx, rcx
    jz native_load_regs
    dec rcx
    push qword ptr [rsi + rcx*8]
    jmp native_push_stack
native_no_overflow:
native_load_regs:
    lea rax, [native_gp_buf]
    mov rdi, [rax]
    mov rsi, [rax + 8]
    mov rdx, [rax + 16]
    mov rcx, [rax + 24]
    mov r8, [rax + 32]
    mov r9, [rax + 40]
    movq xmm0, [native_xmm_buf + 0]
    movq xmm1, [native_xmm_buf + 8]
    movq xmm2, [native_xmm_buf + 16]
    movq xmm3, [native_xmm_buf + 24]
    movq xmm4, [native_xmm_buf + 32]
    movq xmm5, [native_xmm_buf + 40]
    movq xmm6, [native_xmm_buf + 48]
    movq xmm7, [native_xmm_buf + 56]
    call r13
    shl rax, 3
    jmp native_done
native_too_many:
    lea rdi, [msg_dl_of]
    mov rsi, msg_dl_of_len
    call die
native_done_int:
    mov rax, 0
native_done:
    mov rsp, [dl_nc_sav]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop r8
    pop rbp
    ret

# native_call_f: rdi = count -> rax = tagged float result (xmm0 return)
.global native_call_f
native_call_f:
    push rbp
    push r8
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [dl_nc_sav], rsp
    mov r12, rdi
    test r12, r12
    jz native_f_done
cmp r12, DL_ARGS_MAX
    jg native_too_many
    lea rsi, [rsp + 56 + r12*8]
    lea rdi, [native_args_buf]
    mov rcx, r12
native_marshal_f_loop:
    mov rax, [rsi]
    mov [rdi], rax
    sub rsi, 8
    add rdi, 8
    dec rcx
    jnz native_marshal_f_loop
    mov qword ptr [native_gp_count], 0
    mov qword ptr [native_xmm_count], 0
    mov r13, [native_args_buf]
    shr r13, 3
    mov r14, 0
    mov r10, r12
native_cls_f_loop:
    inc r14
    cmp r14, r10
    jae native_cls_f_done
    mov rax, [native_args_buf + r14*8]
    mov rdx, rax
    and edx, 7
    cmp edx, TAG_FLOAT
    je native_cls_f_xmm
    mov rcx, [native_gp_count]
    cmp rcx, 9
    jae native_too_many
    call native_decode_arg
    mov rcx, [native_gp_count]
    mov [native_gp_buf + rcx*8], rax
    inc qword ptr [native_gp_count]
    jmp native_cls_f_loop
native_cls_f_xmm:
    mov rcx, [native_xmm_count]
    cmp rcx, 8
    jae native_too_many
    and rax, -8
    movq xmm0, rax
    movq [native_xmm_buf + rcx*8], xmm0
    inc qword ptr [native_xmm_count]
    jmp native_cls_f_loop
native_cls_f_done:
    test r13, r13
    jz native_f_done
    mov rax, [native_gp_count]
    sub rax, 6
    mov r14, rax
    jle native_f_no_overflow
    lea rax, [r14*8 + 15]
    and rax, -16
    sub rsp, rax
    mov rax, rsp
    and eax, 15
    mov rcx, r14
    and ecx, 1
    shl ecx, 3
    cmp eax, ecx
    je native_f_no_pad
    push rax
native_f_no_pad:
    lea rsi, [native_gp_buf + 48]
    mov rcx, r14
native_f_push_stack:
    test rcx, rcx
    jz native_f_regs
    dec rcx
    push qword ptr [rsi + rcx*8]
    jmp native_f_push_stack
native_f_no_overflow:
native_f_regs:
    lea rax, [native_gp_buf]
    mov rdi, [rax]
    mov rsi, [rax + 8]
    mov rdx, [rax + 16]
    mov rcx, [rax + 24]
    mov r8, [rax + 32]
    mov r9, [rax + 40]
    movq xmm0, [native_xmm_buf + 0]
    movq xmm1, [native_xmm_buf + 8]
    movq xmm2, [native_xmm_buf + 16]
    movq xmm3, [native_xmm_buf + 24]
    movq xmm4, [native_xmm_buf + 32]
    movq xmm5, [native_xmm_buf + 40]
    movq xmm6, [native_xmm_buf + 48]
    movq xmm7, [native_xmm_buf + 56]
    call r13
    movq rax, xmm0
    and rax, -8
    or rax, 1
    jmp native_done
native_f_done:
    mov rax, 0
    jmp native_done

