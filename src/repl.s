# ==================================================================== repl ==
# Interactive REPL — the compiler's simple TUI.
#
# Started from _start when qafc is run with no arguments, or with "repl" as
# the program name. Reads a line, tokenizes + parses it, and runs it. Parse
# and runtime errors print a message and continue instead of killing the
# process (see die_repl / repl_recover in syscalls.s).
#
# State persists across lines: variables, functions, lists and the string
# pool survive, so definitions typed earlier stay available.

start_repl:
    mov qword ptr [repl_active], 1
    lea rdi, [msg_repl_banner]
    mov rsi, msg_repl_banner_len
    call write_str

# One input line per iteration. Parser/runtime state resets each round;
# user-visible state (symbols, functions, strings) is left alone.
repl_loop:
    mov qword ptr [call_depth], 0
    mov qword ptr [cur_tok], 0
    mov qword ptr [tok_count], 0
    mov qword ptr [tok_write_pos], 0
    lea rdi, [msg_repl_prompt]
    mov rsi, msg_repl_prompt_len
    call write_str
    lea rdi, [repl_line_buf]
    call repl_read_line
    cmp rax, 0
    jl repl_exit               # EOF / read error
    jz repl_loop               # empty line: read again
    # Point the lexer at the fresh line.
    mov rcx, rax               # rcx = line length
    lea rdx, [repl_line_buf]
    mov [lex_src_ptr], rdx
    mov [src_len], rcx
    # From here on, a parse or runtime error jumps back to repl_recover
    # instead of exiting (die_repl restores this saved rsp).
    mov [repl_rspsave], rsp
    mov rax, [tok_count]
    mov [tok_write_pos], rax
    call tokenize
    call parse_program
    mov rdi, rax
    test rdi, rdi
    jz repl_loop               # nothing to run (comments / whitespace)
    call exec_list
    jmp repl_loop

# Abort target for errors raised while parsing or running a REPL line
# (see die_repl in syscalls.s). The stack has already been unwound.
repl_recover:
    mov qword ptr [call_depth], 0
    jmp repl_loop

repl_exit:
    lea rdi, [msg_repl_bye]
    mov rsi, msg_repl_bye_len
    call write_str
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

# ---------------------------------------------------------------- repl_read_line
# rdi = destination buffer (4096 bytes). Reads one line from stdin, byte at a
# time (so it never steals input from read/getchar builtins), stripping the
# trailing newline and NUL-terminating the line.
# Returns rax:  -1 on EOF/error, else the number of bytes in the line.
repl_read_line:
    push rbx
    push r12
    push r13
    mov r12, rdi               # r12 = buffer
    xor r13, r13               # r13 = byte count
repl_read_line_loop:
    cmp r13, 4095
    jge repl_read_line_done
    mov rdi, 0
    lea rsi, [char_io_buf]
    mov rdx, 1
    mov rax, SYS_READ
    syscall
    cmp rax, 1
    jl repl_read_line_eof
    movzx eax, byte ptr [char_io_buf]
    cmp al, 10                 # '\n' ends the line
    je repl_read_line_done
    cmp al, 13                 # strip '\r'
    je repl_read_line_loop
    mov [r12 + r13], al
    inc r13
    jmp repl_read_line_loop
repl_read_line_eof:
    test r13, r13
    jnz repl_read_line_done    # bytes already collected: treat as a line
    mov rax, -1                # true EOF with no data
    jmp repl_read_line_out
repl_read_line_done:
    mov byte ptr [r12 + r13], 0
    mov rax, r13
repl_read_line_out:
    pop r13
    pop r12
    pop rbx
    ret
