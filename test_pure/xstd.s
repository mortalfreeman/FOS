.global _start
_start:
    call main
    mov $60, %rax
    xor %rdi, %rdi
    syscall

.global sys_write
sys_write:
    mov $1, %rax
    syscall
    ret

.global write
write:
    mov $1, %rax
    syscall
    ret

.global sys_exit
sys_exit:
exit:
    mov $60, %rax
    syscall
    ret

.global getchar
getchar:
    sub $8, %rsp
    mov $0, %rax
    mov $0, %rdi
    mov %rsp, %rsi
    mov $1, %rdx
    syscall
    movzbl (%rsp), %eax
    add $8, %rsp
    ret

.global malloc
malloc:
    push %rdi
    mov $12, %rax
    xor %rdi, %rdi
    syscall
    mov %rax, %r8
    pop %rdi
    add %r8, %rdi
    add $7, %rdi
    and $-8, %rdi
    mov $12, %rax
    syscall
    mov %r8, %rax
    ret

.global strlen
strlen:
    xor %rax, %rax
strlen_loop:
    cmpb $0, (%rdi, %rax)
    je strlen_done
    inc %rax
    jmp strlen_loop
strlen_done:
    ret

.global strcpy
strcpy:
    xor %rax, %rax
strcpy_loop:
    movb (%rsi, %rax), %cl
    movb %cl, (%rdi, %rax)
    test %cl, %cl
    je strcpy_done
    inc %rax
    jmp strcpy_loop
strcpy_done:
    ret

.global strcat
strcat:
    xor %rax, %rax
strcat_find_end:
    cmpb $0, (%rdi, %rax)
    je strcat_copy
    inc %rax
    jmp strcat_find_end
strcat_copy:
    xor %rcx, %rcx
strcat_loop:
    movb (%rsi, %rcx), %dl
    movb %dl, (%rdi, %rax)
    test %dl, %dl
    je strcat_done
    inc %rax
    inc %rcx
    jmp strcat_loop
strcat_done:
    ret

.global strcmp
strcmp:
    xor %rax, %rax
strcmp_loop:
    movb (%rdi, %rax), %cl
    movb (%rsi, %rax), %dl
    cmp %dl, %cl
    jne strcmp_diff
    test %cl, %cl
    je strcmp_eq
    inc %rax
    jmp strcmp_loop
strcmp_diff:
    movzbl %cl, %eax
    movzbl %dl, %edx
    sub %edx, %eax
    ret
strcmp_eq:
    xor %eax, %eax
    ret

# printf: только для строк без спецификаторов (используется для ошибок)
.global printf
printf:
    call strlen
    mov %rax, %rdx
    mov %rdi, %rsi
    mov $1, %rax
    mov $1, %rdi
    syscall
    ret

# sprintf: упрощенная версия для %lld (целые) и %.2f (float)
.global sprintf
sprintf:
    push %rbx          # Сохраняем callee-saved регистр
    # rdi = buffer, rsi = format, rdx = value
    # Пока поддерживаем только %lld
    mov %rdi, %r8      # buffer
    mov %rdx, %rax     # value
    mov $10, %rcx
    test %rax, %rax
    jns .positive
    movb $45, (%r8)
    inc %r8
    neg %rax
.positive:
    xor %rbx, %rbx
.push_digits:
    xor %rdx, %rdx
    div %rcx
    add $48, %dl
    push %rdx
    inc %rbx
    test %rax, %rax
    jnz .push_digits
.pop_digits:
    pop %rdx
    mov %dl, (%r8)
    inc %r8
    dec %rbx
    jnz .pop_digits
    movb $0, (%r8)
    mov %r8, %rax
    sub %rdi, %rax
    pop %rbx           # Восстанавливаем callee-saved регистр
    ret
