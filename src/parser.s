# ----------------------------------------------------------- token cursor --
peek_type:
    mov rax, [cur_tok]
    mov rax, [tok_type + rax*8]
    ret

advance_tok:
    mov rcx, [cur_tok]
    mov rax, [tok_type + rcx*8]
    mov rdx, [tok_val + rcx*8]
    inc rcx
    mov [cur_tok], rcx
    ret

# rdi = expected token type; consumes it or dies with a parse error
expect_tok:
    push rdi
    call peek_type
    pop rdi
    cmp rax, rdi
    jne die_parse_error
    call advance_tok
    ret

# ------------------------------------------------------- expression parser --
# Precedence climbing:
# logical_or (||) -> logical_and (&&) -> equality (==, !=) -> relational (<, >, <=, >=)
# -> additive (+, -) -> mult (*, /, %) -> unary (-, !) -> primary

parse_primary:
    call peek_type
    cmp rax, TOK_NUM
    jne parse_primary_try_bool
    call advance_tok
    shl rdx, 3                # ints are stored shifted left by 3 (tag 0)
    mov rdi, ND_NUM
    mov rsi, rdx
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_bool:
    cmp rax, TOK_BOOL
    jne parse_primary_try_float
    call advance_tok
    mov rdi, ND_NUM
    mov rsi, rdx              # bool literals are already tagged values
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_float:
    cmp rax, TOK_FLOAT
    jne parse_primary_try_str
    call advance_tok
    mov rdi, ND_FLOAT
    mov rsi, rdx
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_str:
    cmp rax, TOK_STR
    jne parse_primary_try_read
    call advance_tok
    mov rdi, ND_STR
    mov rsi, rdx              # str_id
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_read:
    cmp rax, TOK_READ
    jne parse_primary_try_putchar
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    mov rdi, TOK_RPAREN
    call expect_tok
    mov rdi, ND_READ
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_putchar:
    cmp rax, TOK_PUTCHAR
    jne parse_primary_try_getchar
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_RPAREN
    call expect_tok
    pop rax
    mov rdi, ND_PUTCHAR
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_getchar:
    cmp rax, TOK_GETCHAR
    jne parse_primary_try_ident
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    mov rdi, TOK_RPAREN
    call expect_tok
    mov rdi, ND_GETCHAR
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_ident:
    cmp rax, TOK_IDENT
    jne parse_primary_try_lparen
    call advance_tok
    mov r8, rdx               # symbol ID (caller-saved r8)
    call peek_type
    cmp rax, TOK_LPAREN
    je parse_call
    mov rdi, ND_VAR
    mov rsi, r8
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_primary_try_lparen:
    cmp rax, TOK_LPAREN
    jne die_parse_error
    call advance_tok
    call parse_expr
    push rax
    mov rdi, TOK_RPAREN
    call expect_tok
    pop rax
    ret

# parse_call: r8 = function name symbol index
parse_call:
    call advance_tok          # consume '('
    push r8                   # save fn sym id
    push r12                  # save caller's r12
    push r13                  # save caller's r13
    call peek_type
    cmp rax, TOK_RPAREN
    je parse_call_no_args
    call parse_expr
    mov r12, rax              # r12 = first arg node
    mov r13, rax              # r13 = tail of arg list
parse_call_args_loop:
    call peek_type
    cmp rax, TOK_COMMA
    jne parse_call_args_done
    call advance_tok
    call parse_expr
    mov [node_next + r13*8], rax
    mov r13, rax
    jmp parse_call_args_loop
parse_call_args_done:
    mov rdi, TOK_RPAREN
    call expect_tok
    mov rdx, r12              # rdx = first arg node
    jmp parse_call_mk
parse_call_no_args:
    mov rdi, TOK_RPAREN
    call expect_tok
    xor rdx, rdx              # rdx = 0
parse_call_mk:
    pop r13                   # restore caller's r13
    pop r12                   # restore caller's r12
    pop rsi                   # restore fn sym id into rsi
    mov rdi, ND_CALL
    cmp rsi, [builtin_list_sym]
    je parse_builtin_list
    cmp rsi, [builtin_len_sym]
    je parse_builtin_len
    cmp rsi, [builtin_push_sym]
    je parse_builtin_push
    cmp rsi, [builtin_pop_sym]
    je parse_builtin_pop
    cmp rsi, [builtin_type_sym]
    je parse_builtin_type
    cmp rsi, [builtin_int2str_sym]
    je parse_builtin_int2str
    cmp rsi, [builtin_float2str_sym]
    je parse_builtin_float2str
    cmp rsi, [builtin_str2int_sym]
    je parse_builtin_str2int
    cmp rsi, [builtin_str2float_sym]
    je parse_builtin_str2float
    cmp rsi, [builtin_int2float_sym]
    je parse_builtin_int2float
    cmp rsi, [builtin_float2int_sym]
    je parse_builtin_float2int
    cmp rsi, [builtin_bool2int_sym]
    je parse_builtin_bool2int
    cmp rsi, [builtin_int2bool_sym]
    je parse_builtin_int2bool
    cmp rsi, [builtin_concat_sym]
    je parse_builtin_concat
    cmp rsi, [builtin_char_sym]
    je parse_builtin_char
    cmp rsi, [builtin_str_get_sym]
    je parse_builtin_str_get
    cmp rsi, [builtin_str_set_sym]
    je parse_builtin_str_set
    cmp rsi, [builtin_floor_sym]
    je parse_builtin_floor
    cmp rsi, [builtin_sqrt_sym]
    je parse_builtin_sqrt
    cmp rsi, [builtin_exp_sym]
    je parse_builtin_exp
    cmp rsi, [builtin_log_sym]
    je parse_builtin_log
    cmp rsi, [builtin_dlopen_sym]
    je parse_builtin_dlopen
    cmp rsi, [builtin_dlsym_sym]
    je parse_builtin_dlsym
    cmp rsi, [builtin_call_native_sym]
    je parse_builtin_call_native
    cmp rsi, [builtin_call_native_f_sym]
    je parse_builtin_call_native_f
    cmp rsi, [builtin_dlerror_sym]
    je parse_builtin_dlerror
    xor rcx, rcx
    call new_node
    ret

parse_builtin_list:
    xor rcx, rcx              # count args
    mov rax, rdx
parse_builtin_list_count:
    test rax, rax
    jz parse_builtin_list_done
    inc rcx
    mov rax, [node_next + rax*8]
    jmp parse_builtin_list_count
parse_builtin_list_done:
    mov rdi, ND_LIST_CALL
    mov rsi, rcx              # arg count
    xor rcx, rcx
    call new_node
    ret
parse_builtin_len:    mov rdi, ND_LEN;      jmp parse_builtin_1
parse_builtin_pop:    mov rdi, ND_POP;      jmp parse_builtin_1
parse_builtin_type:   mov rdi, ND_TYPE;     jmp parse_builtin_1
parse_builtin_int2str:    mov rdi, ND_INT2STR;   jmp parse_builtin_1
parse_builtin_float2str:  mov rdi, ND_FLOAT2STR; jmp parse_builtin_1
parse_builtin_str2int:    mov rdi, ND_STR2INT;   jmp parse_builtin_1
parse_builtin_str2float:  mov rdi, ND_STR2FLOAT; jmp parse_builtin_1
parse_builtin_int2float:  mov rdi, ND_INT2FLOAT; jmp parse_builtin_1
parse_builtin_float2int:  mov rdi, ND_FLOAT2INT; jmp parse_builtin_1
parse_builtin_bool2int:   mov rdi, ND_BOOL2INT;  jmp parse_builtin_1
parse_builtin_int2bool:   mov rdi, ND_INT2BOOL;  jmp parse_builtin_1
parse_builtin_char:   mov rdi, ND_CHAR;     jmp parse_builtin_1
parse_builtin_floor:  mov rdi, ND_FLOOR;    jmp parse_builtin_1
parse_builtin_sqrt:   mov rdi, ND_SQRT;     jmp parse_builtin_1
parse_builtin_exp:     mov rdi, ND_EXP;      jmp parse_builtin_1
parse_builtin_log:     mov rdi, ND_LOG;      jmp parse_builtin_1
parse_builtin_dlopen:  mov rdi, ND_DLOPEN;   jmp parse_builtin_1
parse_builtin_dlerror: mov rdi, ND_DLERROR
    mov rsi, rdx
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_builtin_dlsym:
    mov rdi, ND_DLSYM
    jmp parse_builtin_2
parse_builtin_call_native:
    mov rdi, ND_CALL_NATIVE
    jmp parse_builtin_variadic
parse_builtin_call_native_f:
    mov rdi, ND_CALL_NATIVE_F
    jmp parse_builtin_variadic
    # a variadic builtin mirrors ND_LIST_CALL: node_a=arg count, node_b=first arg
parse_builtin_variadic:
    xor rcx, rcx                        # count nodes in the arg chain (incl. the
    mov rax, rdx                        # function-address node)
parse_builtin_variadic_count:
    test rax, rax
    jz parse_builtin_variadic_done
    inc rcx
    mov rax, [node_next + rax*8]
    jmp parse_builtin_variadic_count
parse_builtin_variadic_done:
    mov rsi, rcx
    xor rcx, rcx
    call new_node
    ret
parse_builtin_1:
    mov rsi, rdx              # arg node (rdx = first arg)
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_builtin_push:
    mov rdi, ND_PUSH
    jmp parse_builtin_2
parse_builtin_concat:
    xor rcx, rcx
    mov rax, rdx
parse_builtin_concat_count:
    test rax, rax
    jz parse_builtin_concat_done
    inc rcx
    mov rax, [node_next + rax*8]
    jmp parse_builtin_concat_count
parse_builtin_concat_done:
    mov rdi, ND_CONCAT
    mov rsi, rcx
    xor rcx, rcx
    call new_node
    ret
parse_builtin_str_get:
    mov rdi, ND_STR_GET
    jmp parse_builtin_2
parse_builtin_2:
    mov rsi, rdx
    mov rdx, [node_next + rdx*8]
    xor rcx, rcx
    call new_node
    ret
parse_builtin_str_set:
    mov rdi, ND_STR_SET
    mov rsi, rdx              # str node
    mov rax, [node_next + rdx*8]
    mov rdx, rax              # index node
    mov rcx, [node_next + rax*8]  # value node
    call new_node
    ret

parse_unary:
    call peek_type
    cmp rax, TOK_MINUS
    je parse_unary_neg
    cmp rax, TOK_BANG
    je parse_unary_not
    jmp parse_postfix
parse_unary_neg:
    call advance_tok
    call parse_unary
    mov rdi, ND_NEG
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_unary_not:
    call advance_tok
    call parse_unary
    mov rdi, ND_NOT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_postfix:
    push rbx
    call parse_primary
    mov rbx, rax
parse_postfix_loop:
    call peek_type
    cmp rax, TOK_LBRACKET
    jne parse_postfix_done
    call advance_tok
    call parse_expr
    push rax
    mov rdi, TOK_RBRACKET
    call expect_tok
    pop rax
    mov rdi, ND_INDEX
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_postfix_loop
parse_postfix_done:
    mov rax, rbx
    pop rbx
    ret

parse_mult:
    push rbx
    push r15
    call parse_unary
    mov rbx, rax
parse_mult_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_STAR
    je parse_mult_op
    cmp r15, TOK_SLASH
    je parse_mult_op
    cmp r15, TOK_PERCENT
    je parse_mult_op
    jmp parse_mult_done
parse_mult_op:
    call advance_tok
    call parse_unary
    mov rdi, ND_MUL
    cmp r15, TOK_STAR
    je parse_mult_settype
    mov rdi, ND_DIV
    cmp r15, TOK_SLASH
    je parse_mult_settype
    mov rdi, ND_MOD
parse_mult_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_mult_loop
parse_mult_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_additive:
    push rbx
    push r15
    call parse_mult
    mov rbx, rax
parse_additive_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_PLUS
    je parse_additive_op
    cmp r15, TOK_MINUS
    je parse_additive_op
    jmp parse_additive_done
parse_additive_op:
    call advance_tok
    call parse_mult
    mov rdi, ND_ADD
    cmp r15, TOK_PLUS
    je parse_additive_settype
    mov rdi, ND_SUB
parse_additive_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_additive_loop
parse_additive_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_relational:
    push rbx
    push r15
    call parse_additive
    mov rbx, rax
parse_relational_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_LT
    je parse_relational_op
    cmp r15, TOK_GT
    je parse_relational_op
    cmp r15, TOK_LE
    je parse_relational_op
    cmp r15, TOK_GE
    je parse_relational_op
    jmp parse_relational_done
parse_relational_op:
    call advance_tok
    call parse_additive
    mov rdi, ND_LT
    cmp r15, TOK_LT
    je parse_relational_settype
    mov rdi, ND_GT
    cmp r15, TOK_GT
    je parse_relational_settype
    mov rdi, ND_LE
    cmp r15, TOK_LE
    je parse_relational_settype
    mov rdi, ND_GE
parse_relational_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_relational_loop
parse_relational_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_equality:
    push rbx
    push r15
    call parse_relational
    mov rbx, rax
parse_equality_loop:
    call peek_type
    mov r15, rax
    cmp r15, TOK_EQEQ
    je parse_equality_op
    cmp r15, TOK_NE
    je parse_equality_op
    jmp parse_equality_done
parse_equality_op:
    call advance_tok
    call parse_relational
    mov rdi, ND_EQ
    cmp r15, TOK_EQEQ
    je parse_equality_settype
    mov rdi, ND_NE
parse_equality_settype:
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_equality_loop
parse_equality_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_logical_and:
    push rbx
    push r15
    call parse_equality
    mov rbx, rax
parse_logical_and_loop:
    call peek_type
    cmp rax, TOK_LOGAND
    jne parse_logical_and_done
    call advance_tok
    call parse_equality
    mov rdi, ND_AND
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_logical_and_loop
parse_logical_and_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_logical_or:
    push rbx
    push r15
    call parse_logical_and
    mov rbx, rax
parse_logical_or_loop:
    call peek_type
    cmp rax, TOK_LOGOR
    jne parse_logical_or_done
    call advance_tok
    call parse_logical_and
    mov rdi, ND_OR
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    mov rbx, rax
    jmp parse_logical_or_loop
parse_logical_or_done:
    mov rax, rbx
    pop r15
    pop rbx
    ret

parse_expr:
    jmp parse_logical_or

# --------------------------------------------------------- statement parser
# rdi = terminator token type -> rax = index of first stmt (0 if none).
# Links statements via node_next; does not consume the terminator.
parse_stmts_until:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor rbx, rbx
    xor r13, r13
parse_stmts_until_loop:
    call peek_type
    cmp rax, r12
    je parse_stmts_until_done
    cmp rax, TOK_EOF
    je parse_stmts_until_done
    call parse_stmt
    test rbx, rbx
    jnz parse_stmts_until_link
    mov rbx, rax
    mov r13, rax
    jmp parse_stmts_until_loop
parse_stmts_until_link:
    mov [node_next + r13*8], rax
    mov r13, rax
    jmp parse_stmts_until_loop
parse_stmts_until_done:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

parse_block:
    mov rdi, TOK_LBRACE
    call expect_tok
    mov rdi, TOK_RBRACE
    call parse_stmts_until
    push rax
    mov rdi, TOK_RBRACE
    call expect_tok
    pop rax
    ret

parse_program:
    mov rdi, TOK_EOF
    call parse_stmts_until
    ret

parse_stmt:
    call peek_type
    cmp rax, TOK_IF
    je parse_stmt_if
    cmp rax, TOK_WHILE
    je parse_stmt_while
    cmp rax, TOK_PRINT
    je parse_stmt_print
    cmp rax, TOK_BREAK
    je parse_stmt_break
    cmp rax, TOK_CONTINUE
    je parse_stmt_continue
    cmp rax, TOK_FN
    je parse_stmt_fn
    cmp rax, TOK_RETURN
    je parse_stmt_return
    cmp rax, TOK_FROM
    je parse_stmt_import
    cmp rax, TOK_IMPORT
    je parse_stmt_import_whole
    cmp rax, TOK_VAR
    je parse_stmt_var
    cmp rax, TOK_LET
    je parse_stmt_var
    cmp rax, TOK_IDENT
    je parse_stmt_ident
    # Fallback to expression statement
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_EXPR_STMT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_stmt_if:
    jmp parse_if
parse_stmt_while:
    jmp parse_while
parse_stmt_print:
    jmp parse_print
parse_stmt_break:
    jmp parse_break
parse_stmt_continue:
    jmp parse_continue
parse_stmt_fn:
    jmp parse_fn
parse_stmt_return:
    jmp parse_return
parse_stmt_import:
    jmp parse_import
parse_stmt_import_whole:
    jmp parse_import_whole
parse_stmt_var:
    jmp parse_var_decl
parse_stmt_ident:
    mov rax, [cur_tok]
    mov rcx, [tok_type + rax*8 + 8] # peek next token
    cmp rcx, TOK_ASSIGN
    je parse_assign
    cmp rcx, TOK_LBRACKET
    je parse_index_assign
    # Expression statement
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_EXPR_STMT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# var/let x = expr;  ->  ND_VAR_DECL {a: sym id, b: expr, c: mutable flag}
parse_var_decl:
    push rbx
    call peek_type
    cmp rax, TOK_LET
    je parse_var_decl_let
    xor rbx, rbx
    jmp parse_var_decl_kw_done
parse_var_decl_let:
    mov rbx, 1
parse_var_decl_kw_done:
    call advance_tok
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rcx, rdx              # sym id
    mov [sym_mutable + rcx*8], rbx
    mov rdi, TOK_ASSIGN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_VAR_DECL
    mov rsi, rcx
    mov rdx, rax
    mov rcx, rbx
    call new_node
    pop rbx
    ret

# x[i] = v;  ->  ND_INDEX_ASSIGN {a: sym id, b: value expr, c: index expr}
parse_index_assign:
    push rbx
    push r15
    call advance_tok          # consume ident
    mov rbx, rdx              # target sym id
    call advance_tok          # consume '['
    call parse_expr
    mov r15, rax              # index expr
    mov rdi, TOK_RBRACKET
    call expect_tok
    mov rdi, TOK_ASSIGN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_INDEX_ASSIGN
    mov rsi, rbx
    mov rdx, rax
    mov rcx, r15
    call new_node
    pop r15
    pop rbx
    ret

# fn ident ( [param, ...] ) block
parse_fn:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call advance_tok          # consume 'fn'
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rbx, rdx              # function name sym id
    mov rdi, TOK_LPAREN
    call expect_tok
    xor r14, r14              # param count
    mov rax, [import_mode]
    test rax, rax
    jz parse_fn_slot_real
    mov r15, [pend_fn_n]      # pending slot (imported file being parsed)
    cmp r15, MAXFN
    jge die_parse_error
    imul r13, r15, MAXPARAMS  # r13 = base index in pend_fn_param_syms
    jmp parse_fn_slot_done
parse_fn_slot_real:
    mov r15, [fn_n]
    cmp r15, MAXFN
    jge die_parse_error
    imul r13, r15, MAXPARAMS  # r13 = base index in fn_param_syms
parse_fn_slot_done:
    call peek_type
    cmp rax, TOK_RPAREN
    je parse_fn_params_done
parse_fn_params_loop:
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok          # rdx = param sym id
    cmp r14, MAXPARAMS
    jge die_parse_error
    lea r8, [r13 + r14]
    mov r9, [import_mode]
    test r9, r9
    jnz parse_fn_param_store_pend
    mov [fn_param_syms + r8*8], rdx
    jmp parse_fn_param_store_done
parse_fn_param_store_pend:
    mov [pend_fn_param_syms + r8*8], rdx
parse_fn_param_store_done:
    inc r14
    call peek_type
    cmp rax, TOK_COMMA
    jne parse_fn_params_done
    call advance_tok
    jmp parse_fn_params_loop
parse_fn_params_done:
    mov rdi, TOK_RPAREN
    call expect_tok
    call parse_block
    mov r12, rax              # body AST node
    mov r9, [import_mode]
    test r9, r9
    jnz parse_fn_reg_pend
    # Register function in the real table
    mov [fn_sym + r15*8], rbx
    mov [fn_param_count + r15*8], r14
    mov [fn_body + r15*8], r12
    inc r15
    mov [fn_n], r15
    jmp parse_fn_reg_done
parse_fn_reg_pend:
    # Defer registration: keep it pending until the import is resolved
    mov [pend_fn_sym + r15*8], rbx
    mov [pend_fn_param_count + r15*8], r14
    mov [pend_fn_body + r15*8], r12
    inc r15
    mov [pend_fn_n], r15
parse_fn_reg_done:
    # Return ND_FN node
    mov rdi, ND_FN
    mov rsi, r15
    dec rsi
    mov rdx, r12
    xor rcx, rcx
    call new_node
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# import IDENT;  -- whole-file import (like `from IDENT import *`). Same
# load/parse/register machinery as `from`-imports, reached via parse_import_after_names.
parse_import_whole:
    push rbx
    push r12
    push r13
    push r14
    call advance_tok          # consume 'import'
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rbx, rdx              # rbx = filename sym id
    mov rdi, TOK_SEMI
    call expect_tok
    mov qword ptr [import_all], 1
    xor r14, r14
    mov [import_count], r14
    jmp parse_import_after_names

# from IDENT "import" (IDENT ("," IDENT)* | "*") ";"
# Processed at parse time: loads the file (resolved relative to the current
# directory and the main file's directory, with and without a ".qf" suffix),
# tokenizes it appended after the last known EOF, parses it in defer mode,
# then registers only the requested function names. Top-level statements of
# the imported file are parsed but never executed.
parse_import:
    push rbx
    push r12
    push r13
    push r14
    call advance_tok          # consume 'from'
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    mov rbx, rdx              # rbx = filename sym id
    mov rdi, TOK_IMPORT
    call expect_tok
    call peek_type
    cmp rax, TOK_STAR
    je parse_import_star
    xor r14, r14              # r14 = number of names to import
parse_import_names_loop:
    call peek_type
    cmp rax, TOK_IDENT
    jne die_parse_error
    call advance_tok
    cmp r14, MAXSYM
    jge die_parse_error
    mov [import_syms + r14*8], rdx
    inc r14
    call peek_type
    cmp rax, TOK_COMMA
    jne parse_import_names_done
    call advance_tok
    jmp parse_import_names_loop
parse_import_names_done:
    mov qword ptr [import_all], 0
    jmp parse_import_after_names
parse_import_star:
    call advance_tok          # consume '*'
    mov qword ptr [import_all], 1
    xor r14, r14
parse_import_after_names:
    mov [import_count], r14
    call peek_type
    cmp rax, TOK_SEMI
    jne parse_import_after_semi
    call advance_tok
parse_import_after_semi:
    # Guard against import cycles
    mov rax, [import_depth]
    cmp rax, 64
    jge die_parse_error
    inc rax
    mov [import_depth], rax
    # Save this import's filter into the per-depth slot (nested imports
    # parse with their own filter and must not clobber this one).
    mov r9, [import_all]
    mov [import_filter_all + rax*8], r9
    mov [import_filter_count + rax*8], r14
    imul r9, rax, MAXSYM
    xor rcx, rcx
parse_import_filter_copy:
    cmp rcx, r14
    jge parse_import_filter_done
    mov rdx, [import_syms + rcx*8]
    mov [import_filter_syms + r9*8], rdx
    inc rcx
    add r9, 8
    jmp parse_import_filter_copy
parse_import_filter_done:
    # Build the filename in import_name_buf (cap 252 chars, room for ".qf")
    mov rax, [sym_name_len + rbx*8]
    mov rcx, rax
    cmp rcx, 252
    jle parse_import_fname_len_ok
    mov rcx, 252
parse_import_fname_len_ok:
    mov rsi, [sym_name_ptr + rbx*8]
    lea rdi, [import_name_buf]
    xor rdx, rdx
parse_import_fname_copy:
    cmp rdx, rcx
    jge parse_import_fname_done
    mov al, [rsi + rdx]
    mov [rdi + rdx], al
    inc rdx
    jmp parse_import_fname_copy
parse_import_fname_done:
    mov byte ptr [import_name_buf + rcx], 0
    # load_import resolves the file itself: CWD and the main file's directory,
    # each tried with and without a ".qf" suffix.
    lea rdi, [import_name_buf]
    call load_import
    test rax, rax
    jz parse_import_loaded
    lea rdi, [msg_open]
    mov rsi, msg_open_len
    call die
parse_import_loaded:
    mov r12, [cur_tok]        # save parser cursor
    mov rax, [tok_count]      # append new tokens after the last EOF
    mov [tok_write_pos], rax
    call tokenize
    mov r13, [import_mode]    # save outer mode
    mov qword ptr [import_mode], 1
    call parse_program
    mov [import_mode], r13    # restore outer mode
    call register_imports
    mov [cur_tok], r12        # restore parser cursor
    dec qword ptr [import_depth]
    pop r14
    pop r13
    pop r12
    pop rbx
    # No-op node at runtime (all import work happens at parse time)
    mov rdi, ND_IMPORT
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# Register the pending function definitions whose symbol is in the current
# import's filter slot (or all of them for "import *"). Clears the pending
# list.
register_imports:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, [import_depth]       # this import's filter slot
    xor rbx, rbx              # pending index
register_imports_loop:
    mov rax, [pend_fn_n]
    cmp rbx, rax
    jge register_imports_done
    mov r12, [pend_fn_sym + rbx*8]
    mov rax, [import_filter_all + r15*8]
    test rax, rax
    jnz register_imports_take
    mov r14, [import_filter_count + r15*8]
    imul r13, r15, MAXSYM
    xor rcx, rcx
register_imports_search:
    cmp rcx, r14
    jge register_imports_next
    mov rax, [import_filter_syms + r13*8]
    cmp rax, r12
    je register_imports_take
    inc rcx
    add r13, 8
    jmp register_imports_search
register_imports_take:
    mov rcx, [fn_n]
    cmp rcx, MAXFN
    jge die_parse_error
    mov rax, [pend_fn_sym + rbx*8]
    mov [fn_sym + rcx*8], rax
    mov rax, [pend_fn_param_count + rbx*8]
    mov [fn_param_count + rcx*8], rax
    mov rax, [pend_fn_body + rbx*8]
    mov [fn_body + rcx*8], rax
    imul rdx, rbx, MAXPARAMS
    imul r8, rcx, MAXPARAMS
    xor r13, r13
register_imports_copy_params:
    cmp r13, MAXPARAMS
    jge register_imports_copy_done
    mov rax, [pend_fn_param_syms + rdx*8]
    mov [fn_param_syms + r8*8], rax
    inc r13
    inc rdx
    inc r8
    jmp register_imports_copy_params
register_imports_copy_done:
    inc rcx
    mov [fn_n], rcx
register_imports_next:
    inc rbx
    jmp register_imports_loop
register_imports_done:
    mov qword ptr [pend_fn_n], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# return [expr] ;
parse_return:
    call advance_tok          # consume 'return'
    call peek_type
    cmp rax, TOK_SEMI
    je parse_return_empty
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_RETURN
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret
parse_return_empty:
    call advance_tok          # consume ';'
    mov rdi, ND_RETURN
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# if ( expr ) block [else block]
parse_if:
    push rbx
    push r14
    push r15
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    call parse_expr
    mov rbx, rax
    mov rdi, TOK_RPAREN
    call expect_tok
    call parse_block
    mov r14, rax
    xor r15, r15
    call peek_type
    cmp rax, TOK_ELSE
    jne parse_if_mk
    call advance_tok
    call parse_block
    mov r15, rax
parse_if_mk:
    mov rdi, ND_IF
    mov rsi, rbx
    mov rdx, r14
    mov rcx, r15
    call new_node
    pop r15
    pop r14
    pop rbx
    ret

# while ( expr ) block
parse_while:
    push rbx
    call advance_tok
    mov rdi, TOK_LPAREN
    call expect_tok
    call parse_expr
    mov rbx, rax
    mov rdi, TOK_RPAREN
    call expect_tok
    call parse_block
    mov rdi, ND_WHILE
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    pop rbx
    ret

# print expr ;
parse_print:
    call advance_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_PRINT
    mov rsi, rax
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# break ;
parse_break:
    call advance_tok
    mov rdi, TOK_SEMI
    call expect_tok
    mov rdi, ND_BREAK
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# continue ;
parse_continue:
    call advance_tok
    mov rdi, TOK_SEMI
    call expect_tok
    mov rdi, ND_CONTINUE
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    call new_node
    ret

# ident = expr ;
parse_assign:
    push rbx
    call peek_type
    cmp rax, TOK_IDENT
    je parse_assign_ok
    jmp die_parse_error
parse_assign_ok:
    call advance_tok
    mov rbx, rdx
    mov rdi, TOK_ASSIGN
    call expect_tok
    call parse_expr
    push rax
    mov rdi, TOK_SEMI
    call expect_tok
    pop rax
    mov rdi, ND_ASSIGN
    mov rsi, rbx
    mov rdx, rax
    xor rcx, rcx
    call new_node
    pop rbx
    ret

