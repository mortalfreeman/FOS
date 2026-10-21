#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Обновление xstd.s (write, getchar, sprintf)..."
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

.global write
write:
    mov $1, %rax
    syscall
    ret

.global sys_exit
sys_exit:
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

# Простейший sprintf для "%lld"
.global sprintf
sprintf:
    push %rbx
    push %rcx
    push %rdx
    mov %rdi, %r8
    mov %rsi, %r9
    mov %rdx, %rax
    test %rax, %rax
    jns .positive
    movb $45, (%r8)
    inc %r8
    neg %rax
.positive:
    mov $10, %rcx
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
    pop %rdx
    pop %rcx
    pop %rbx
    ret
ASM_EOF

echo "==> 2. Исправление компилятора (static режим)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Для static режима меняем имя write на sys_write
if 'let write_fn = if is_static {' not in content:
    content = content.replace(
        'let write_fn = module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None);',
        'let write_fn = if is_static { module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None) } else { module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None) };'
    )

# Для static режима getchar используем наш
if 'let getchar = if is_static {' not in content:
    content = content.replace(
        'let getchar = module.add_function("getchar", i32_type.fn_type(&[], false), None);',
        'let getchar = if is_static { module.add_function("getchar", i32_type.fn_type(&[], false), None) } else { module.add_function("getchar", i32_type.fn_type(&[], false), None) };'
    )

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Компилятор обновлен.")
PYEOF

echo "==> 3. Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 4. Тестирование..."
mkdir -p /tmp/test_static
cd /tmp/test_static

cat > test.x << 'XLANG'
.use GOIO

func main {
    con("Hello from static!");
    con("2 + 2 = ", 2 + 2);
}
XLANG

echo "--- Компиляция (-static) ---"
xc test.x -static -out test_static
file test_static
./test_static
