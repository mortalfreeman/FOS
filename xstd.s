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
