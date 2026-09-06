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
