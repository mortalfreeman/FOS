#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Перезапись xstd.s (уникальные метки)..."
cat > ~/FOS/xstd.s << 'ASM_EOF'
.global _start
_start:
    call xlang_main
    mov $60, %rax
    xor %rdi, %rdi
    syscall

.global sys_write
sys_write:
    mov $1, %rax
    syscall
    ret

.global sys_exit
sys_exit:
    mov $60, %rax
    syscall
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
ASM_EOF

echo "==> 2. Пересборка компилятора (на всякий случай)..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Тестирование статической сборки..."
mkdir -p /tmp/test_static
cd /tmp/test_static

cat > test.x << 'XLANG'
.use GOIO

func main {
    con("Hello from static binary!");
    con("2 + 2 = ", 2 + 2);
}
XLANG

echo "--- Компиляция (-static) ---"
xc test.x -static -out test_static
file test_static
./test_static
