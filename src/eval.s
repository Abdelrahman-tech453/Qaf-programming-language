# ------------------------------------------------------------- evaluator --
# cmp_helper: r12 = comparison node (set by caller). Evaluates node_a and
# node_b and leaves FLAGS set from `cmp left, right`.
cmp_helper:
    push rbx
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    cmp rbx, rax
    pop rbx
    ret

# eval: rdi = node index -> rax = value
eval:
    push rbx
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_NUM
    je eval_num
    cmp rax, ND_VAR
    je eval_var
    cmp rax, ND_NEG
    je eval_neg
    cmp rax, ND_ADD
    je eval_add
    cmp rax, ND_SUB
    je eval_sub
    cmp rax, ND_MUL
    je eval_mul
    cmp rax, ND_DIV
    je eval_div
    cmp rax, ND_MOD
    je eval_mod
    cmp rax, ND_EQ
    je eval_eq
    cmp rax, ND_NE
    je eval_ne
    cmp rax, ND_LT
    je eval_lt
    cmp rax, ND_GT
    je eval_gt
    cmp rax, ND_LE
    je eval_le
    cmp rax, ND_GE
    je eval_ge
    cmp rax, ND_NOT
    je eval_not
    cmp rax, ND_AND
    je eval_and
    cmp rax, ND_OR
    je eval_or
    cmp rax, ND_CALL
    je eval_call
    cmp rax, ND_STR
    je eval_str
    cmp rax, ND_READ
    je eval_read
    cmp rax, ND_PUTCHAR
    je eval_putchar
    cmp rax, ND_GETCHAR
    je eval_getchar
    cmp rax, ND_FLOAT
    je eval_float
    cmp rax, ND_LIST_CALL
    je eval_list_call
    cmp rax, ND_LEN
    je eval_len
    cmp rax, ND_PUSH
    je eval_push
    cmp rax, ND_POP
    je eval_pop
    cmp rax, ND_INDEX
    je eval_index
    cmp rax, ND_TYPE
    je eval_type
    cmp rax, ND_INT2STR
    je eval_int2str
    cmp rax, ND_FLOAT2STR
    je eval_float2str
    cmp rax, ND_STR2INT
    je eval_str2int
    cmp rax, ND_STR2FLOAT
    je eval_str2float
    cmp rax, ND_INT2FLOAT
    je eval_int2float
    cmp rax, ND_FLOAT2INT
    je eval_float2int
    cmp rax, ND_BOOL2INT
    je eval_bool2int
    cmp rax, ND_INT2BOOL
    je eval_int2bool
    cmp rax, ND_CONCAT
    je eval_concat
    cmp rax, ND_CHAR
    je eval_char
    cmp rax, ND_STR_GET
    je eval_str_get
    cmp rax, ND_STR_SET
    je eval_str_set
    cmp rax, ND_FLOOR
    je eval_floor
    cmp rax, ND_SQRT
    je eval_sqrt
    cmp rax, ND_EXP
    je eval_exp
    cmp rax, ND_LOG
    je eval_log
    cmp rax, ND_DLOPEN
    je eval_dlopen
    cmp rax, ND_DLSYM
    je eval_dlsym
    cmp rax, ND_CALL_NATIVE
    je eval_call_native
    cmp rax, ND_CALL_NATIVE_F
    je eval_call_native_f
    cmp rax, ND_DLERROR
    je eval_dlerror
    jmp die_parse_error

eval_num:
    mov rax, [node_a + r12*8]
    jmp eval_out

eval_float:
    mov rax, [node_a + r12*8]
    jmp eval_out

eval_str:
    mov rdi, [node_a + r12*8]
    call make_str
    jmp eval_out

eval_read:
    call read_int
    shl rax, 3
    jmp eval_out

eval_putchar:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    sar rdi, 3
    call putchar_int
    shl rax, 3
    jmp eval_out

eval_getchar:
    call getchar_tagged
    jmp eval_out

eval_var:
    mov rax, [node_a + r12*8]     # sym_id
    mov rbx, [call_depth]
    imul rcx, rbx, MAXSYM
    add rcx, rax
    mov rax, [call_stack + rcx*8]
    jmp eval_out

eval_neg:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call builtin_neg
    jmp eval_out

eval_not:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    xor rax, 8
    jmp eval_out

eval_add:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_add
    jmp eval_out

eval_sub:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_sub
    jmp eval_out

eval_mul:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_mul
    jmp eval_out

eval_div:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_div
    jmp eval_out

eval_mod:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_mod
    jmp eval_out

eval_eq:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_eq
    jmp eval_out

eval_ne:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_ne
    jmp eval_out

eval_lt:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_lt
    jmp eval_out

eval_gt:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_gt
    jmp eval_out

eval_le:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_le
    jmp eval_out

eval_ge:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call bin_ge
    jmp eval_out

eval_and:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    je eval_and_false
    mov rdi, [node_b + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    jmp eval_out
eval_and_false:
    mov rax, BOOL_FALSE
    jmp eval_out

eval_or:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    jne eval_or_true
    mov rdi, [node_b + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    jmp eval_out
eval_or_true:
    mov rax, BOOL_TRUE
    jmp eval_out

eval_list_call:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    xor rbp, rbp
    mov r13, [node_b + r12*8]
eval_list_call_args:
    test r13, r13
    jz eval_list_call_args_done
    mov rdi, r13
    call eval
    push rax
    inc rbp
    mov r13, [node_next + r13*8]
    jmp eval_list_call_args
eval_list_call_args_done:
    mov rdi, rbp
    call list_make
    lea rsp, [rsp + rbp*8]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

# eval_call_native / eval_call_native_f: variadic, args pushed in order
# (arg0 = function address). node_a = arg count, node_b = first arg node.
# native_call / native_call_f read the count in rdi and the args from the
# stack, then advance nothing — the callee restores rsp.
eval_call_native:
    push rbx
    push r13
    push r14
    push r15
    mov r15, [node_b + r12*8]   # first arg node
eval_call_native_args:
    test r15, r15
    jz eval_call_native_done
    mov rdi, r15
    call eval
    push rax
    mov r15, [node_next + r15*8]
    jmp eval_call_native_args
eval_call_native_done:
    mov r13, [node_a + r12*8]   # count (reload: eval clobbers r13)
    mov rdi, r13
    call native_call            # int-returning variant
    lea rsp, [rsp + r13*8]
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out
eval_call_native_f:
    push rbx
    push r13
    push r14
    push r15
    mov r15, [node_b + r12*8]
eval_call_native_f_args:
    test r15, r15
    jz eval_call_native_f_done
    mov rdi, r15
    call eval
    push rax
    mov r15, [node_next + r15*8]
    jmp eval_call_native_f_args
eval_call_native_f_done:
    mov r13, [node_a + r12*8]   # count (reload: eval clobbers r13)
    mov rdi, r13
    call native_call_f
    lea rsp, [rsp + r13*8]
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

eval_dlopen:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call dlopen_builtin
    jmp eval_out

eval_dlsym:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call dlsym_builtin
    jmp eval_out

eval_dlerror:
    call dlerror_builtin
    jmp eval_out

eval_len:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call builtin_len
    jmp eval_out

eval_push:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call list_push
    jmp eval_out

eval_pop:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call list_pop
    jmp eval_out

eval_index:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call builtin_index
    jmp eval_out

eval_type:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call builtin_type
    jmp eval_out

eval_int2str:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call int2str_builtin
    jmp eval_out

eval_float2str:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call float2str_builtin
    jmp eval_out

eval_str2int:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call str2int
    jmp eval_out

eval_str2float:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call str2float
    jmp eval_out

eval_int2float:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call int_to_float_tagged
    jmp eval_out

eval_float2int:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call float2int_builtin
    jmp eval_out

eval_bool2int:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call bool2int_builtin
    jmp eval_out

eval_int2bool:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call int2bool_builtin
    jmp eval_out

eval_concat:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    xor rbp, rbp
    mov r13, [node_b + r12*8]
eval_concat_args:
    test r13, r13
    jz eval_concat_args_done
    mov rdi, r13
    call eval
    push rax
    inc rbp
    mov r13, [node_next + r13*8]
    jmp eval_concat_args
eval_concat_args_done:
    mov rdi, rbp
    call str_concat_all
    lea rsp, [rsp + rbp*8]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

eval_char:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call char_of_int
    jmp eval_out

eval_str_get:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rsi, rax
    mov rdi, rbx
    call str_index
    jmp eval_out

eval_str_set:
    mov rdi, [node_a + r12*8]
    call eval
    mov rbx, rax
    mov rdi, [node_b + r12*8]
    call eval
    mov rcx, rax
    mov rdi, [node_c + r12*8]
    call eval
    mov rdx, rax
    mov rdi, rbx
    mov rsi, rcx
    call str_set
    jmp eval_out

eval_floor:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call floor_builtin
    jmp eval_out

eval_sqrt:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call sqrt_builtin
    jmp eval_out

eval_exp:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call exp_builtin
    jmp eval_out

eval_log:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call log_builtin
    jmp eval_out

# eval_call: node_a = fn_sym_id, node_b = first arg node (0 if none)
eval_call:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    mov r14, [node_a + r12*8] # function symbol ID
    xor rbx, rbx
    mov r15, [fn_n]
eval_call_lookup:
    cmp rbx, r15
    jge die_undef_fn
    cmp [fn_sym + rbx*8], r14
    je eval_call_found
    inc rbx
    jmp eval_call_lookup
eval_call_found:
    # rbx = function index
    mov r13, [node_b + r12*8] # first arg node
    xor rbp, rbp              # number of arguments pushed
eval_call_eval_args:
    test r13, r13
    jz eval_call_args_done
    mov rdi, r13
    call eval
    push rax                  # push evaluated argument
    inc rbp
    mov r13, [node_next + r13*8]
    jmp eval_call_eval_args
eval_call_args_done:
    # JIT fast path: call the native code if this function was compiled.
    # rbx = fn index, rbp = number of arguments pushed (rsp = last arg).
    mov rax, [fn_jit + rbx*8]
    test rax, rax
    jz eval_call_interp
    test rbp, rbp
    jz eval_call_native_zero
    lea rdi, [rsp + rbp*8 - 8]    # argv: first argument
    jmp eval_call_native_call
eval_call_native_zero:
    mov rdi, rsp
eval_call_native_call:
    call rax
    lea rsp, [rsp + rbp*8]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out
eval_call_interp:
    # Check max call depth
    mov rax, [call_depth]
    cmp rax, MAXFRAMES - 1
    jge die_stackoverflow
    inc rax
    mov [call_depth], rax     # rax = new depth D
    # Zero out new frame variable storage
    imul rdi, rax, MAXSYM*8
    lea rdi, [call_stack + rdi]
    xor rax, rax
    mov rcx, MAXSYM
    rep stosq
    # Pop evaluated arguments into new frame
    mov rcx, rbp
eval_call_pop_args:
    test rcx, rcx
    jz eval_call_pop_done
    dec rcx
    pop rax                   # rax = argument value
    cmp rcx, [fn_param_count + rbx*8]
    jge eval_call_pop_args    # ignore excess args
    imul r8, rbx, MAXPARAMS
    add r8, rcx
    mov r8, [fn_param_syms + r8*8] # r8 = param symbol ID
    mov r9, [call_depth]
    imul r9, r9, MAXSYM
    add r9, r8
    mov [call_stack + r9*8], rax
    jmp eval_call_pop_args
eval_call_pop_done:
    mov qword ptr [return_val], 0
    mov rdi, [fn_body + rbx*8]
    call exec_list
    dec qword ptr [call_depth]
    mov rax, [return_val]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    jmp eval_out

die_undef_fn:
    lea rdi, [msg_undef_fn]
    mov rsi, msg_undef_fn_len
    call die

die_stackoverflow:
    lea rdi, [msg_stackoverflow]
    mov rsi, msg_stackoverflow_len
    call die

eval_out:
    pop r12
    pop rbx
    ret

# ------------------------------------------------------------- executor --
# exec_list: rdi = index of first statement in a block (0 = empty)
# Returns rax: 0 = OK, 1 = BREAK, 2 = CONTINUE, 3 = RETURN
exec_list:
    push rbx
    mov rbx, rdi
    xor rax, rax
exec_list_loop:
    test rbx, rbx
    jz exec_list_done
    mov rdi, rbx
    call exec_stmt
    test rax, rax
    jnz exec_list_done
    mov rbx, [node_next + rbx*8]
    jmp exec_list_loop
exec_list_done:
    pop rbx
    ret

# exec_stmt: rdi = statement node index
# Returns rax: 0 = OK, 1 = BREAK, 2 = CONTINUE, 3 = RETURN
exec_stmt:
    push rbx
    push r12
    mov r12, rdi
    mov rax, [node_type + r12*8]
    cmp rax, ND_ASSIGN
    je exec_stmt_assign
    cmp rax, ND_PRINT
    je exec_stmt_print
    cmp rax, ND_IF
    je exec_stmt_if
    cmp rax, ND_WHILE
    je exec_stmt_while_check
    cmp rax, ND_BREAK
    je exec_stmt_break
    cmp rax, ND_CONTINUE
    je exec_stmt_continue
    cmp rax, ND_FN
    je exec_stmt_fn
    cmp rax, ND_RETURN
    je exec_stmt_return
    cmp rax, ND_EXPR_STMT
    je exec_stmt_expr
    cmp rax, ND_IMPORT
    je exec_stmt_fn
    cmp rax, ND_VAR_DECL
    je exec_stmt_var_decl
    cmp rax, ND_INDEX_ASSIGN
    je exec_stmt_index_assign
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_var_decl:
    mov rdi, [node_b + r12*8]
    call eval
    mov rcx, [node_a + r12*8]
    mov r8, [call_depth]
    imul rdx, r8, MAXSYM
    add rdx, rcx
    mov [call_stack + rdx*8], rax
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_assign:
    mov rdi, [node_b + r12*8]
    call eval
    mov rcx, [node_a + r12*8]
    cmp qword ptr [sym_mutable + rcx*8], 1
    je exec_stmt_assign_imm
    mov r8, [call_depth]
    imul rdx, r8, MAXSYM
    add rdx, rcx
    mov [call_stack + rdx*8], rax
    xor rax, rax
    jmp exec_stmt_done
exec_stmt_assign_imm:
    lea rdi, [msg_imm]
    mov rsi, msg_imm_len
    call die

exec_stmt_index_assign:
    mov rdi, [node_c + r12*8]
    call eval
    mov rcx, rax              # index
    mov rdi, [node_b + r12*8]
    call eval
    mov rdx, rax              # value
    mov rax, [node_a + r12*8] # sym id
    mov r8, [call_depth]
    imul r8, r8, MAXSYM
    add r8, rax
    mov rdi, [call_stack + r8*8]   # current target value
    mov rbx, rdi
    and rbx, 7
    cmp rbx, TAG_LIST
    jne exec_stmt_index_assign_bad
    mov rsi, rcx
    call list_index_assign
    xor rax, rax
    jmp exec_stmt_done
exec_stmt_index_assign_bad:
    jmp die_type_err

exec_stmt_print:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call print_value
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_if:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    je exec_stmt_else
    mov rdi, [node_b + r12*8]
    call exec_list
    jmp exec_stmt_done
exec_stmt_else:
    mov rdi, [node_c + r12*8]
    call exec_list
    jmp exec_stmt_done

exec_stmt_while_check:
    mov rdi, [node_a + r12*8]
    call eval
    mov rdi, rax
    call is_truthy
    cmp rax, BOOL_FALSE
    je exec_stmt_while_done_ok
    mov rdi, [node_b + r12*8]
    call exec_list
    cmp rax, 1                 # STATUS_BREAK
    je exec_stmt_while_done_ok
    cmp rax, 3                 # STATUS_RETURN
    je exec_stmt_done          # propagate return out of while immediately
    # STATUS_CONTINUE (2) or STATUS_OK (0): loop again
    jmp exec_stmt_while_check
exec_stmt_while_done_ok:
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_break:
    mov rax, 1
    jmp exec_stmt_done

exec_stmt_continue:
    mov rax, 2
    jmp exec_stmt_done

exec_stmt_fn:
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_return:
    mov rdi, [node_a + r12*8]
    test rdi, rdi
    jz exec_stmt_return_zero
    call eval
    mov [return_val], rax
    mov rax, 3                 # STATUS_RETURN
    jmp exec_stmt_done
exec_stmt_return_zero:
    mov qword ptr [return_val], 0
    mov rax, 3                 # STATUS_RETURN
    jmp exec_stmt_done

exec_stmt_expr:
    mov rdi, [node_a + r12*8]
    call eval
    xor rax, rax
    jmp exec_stmt_done

exec_stmt_done:
    pop r12
    pop rbx
    ret
