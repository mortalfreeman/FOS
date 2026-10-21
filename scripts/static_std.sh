#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание ассемблерного рантайма (xstd.s)..."
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
.loop:
    cmpb $0, (%rdi, %rax)
    je .done
    inc %rax
    jmp .loop
.done:
    ret

.global strcpy
strcpy:
    xor %rax, %rax
.loop:
    movb (%rsi, %rax), %cl
    movb %cl, (%rdi, %rax)
    test %cl, %cl
    je .done
    inc %rax
    jmp .loop
.done:
    ret

.global strcat
strcat:
    xor %rax, %rax
.find_end:
    cmpb $0, (%rdi, %rax)
    je .copy
    inc %rax
    jmp .find_end
.copy:
    xor %rcx, %rcx
.loop:
    movb (%rsi, %rcx), %dl
    movb %dl, (%rdi, %rax)
    test %dl, %dl
    je .done
    inc %rax
    inc %rcx
    jmp .loop
.done:
    ret

.global strcmp
strcmp:
    xor %rax, %rax
.loop:
    movb (%rdi, %rax), %cl
    movb (%rsi, %rax), %dl
    cmp %dl, %cl
    jne .diff
    test %cl, %cl
    je .eq
    inc %rax
    jmp .loop
.diff:
    movzbl %cl, %eax
    movzbl %dl, %edx
    sub %edx, %eax
    ret
.eq:
    xor %eax, %eax
    ret
ASM_EOF

echo "==> 2. Модификация main.rs (флаг -static)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем флаг -static
content = content.replace(
    'let mut target_os = "linux".to_string();',
    'let mut target_os = "linux".to_string();\n    let mut is_static = false;'
)
content = content.replace(
    'else if args[i] == "--target" && i + 1 < args.len() {',
    'else if args[i] == "-static" { is_static = true; i += 1; }\n        else if args[i] == "--target" && i + 1 < args.len() {'
)

# 2. Подменяем вызовы libc на наши функции, если static
# Заменяем все libc.xxx на пустышки, если static. Но проще: использовать один и тот же IR, 
# но линковать с xstd.s вместо libc.
# В static режиме мы не используем printf, а используем наш sys_write.
# Но наш std_print_str уже использует libc.write. 
# Давай просто переименуем libc.write в sys_write, а libc.getchar в простую заглушку.
# (getchar нам пока не нужен для static, но для компиляции нужен).

if 'let write_fn = if is_static {' not in content:
    content = content.replace(
        'let write_fn = module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None);',
        'let write_fn = if is_static { module.add_function("sys_write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None) } else { module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None) };'
    )

# 3. Меняем логику линковки
old_link = '''    let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };
    if process::Command::new(linker).arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("Linker failed").success() {'''
new_link = '''    let link_status = if is_static && target_os == "linux" {
        // Сборка статического бинарника через ld
        let as_status = process::Command::new("as").arg("xstd.s").arg("-o").arg("xstd.o").status().expect("as failed");
        if as_status.success() {
            process::Command::new("ld").arg("-o").arg(&final_out).arg("output.o").arg("xstd.o").arg("-static").status().expect("ld failed")
        } else {
            std::process::exit(1);
        }
    } else {
        let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };
        process::Command::new(linker).arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("Linker failed")
    };

    if link_status.success() {'''
content = content.replace(old_link, new_link)

# 4. Убираем std_flush вызов в static режиме (или оставляем, но он будет использовать sys_write)
# (Это необязательно, так как sys_write уже есть)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ main.rs обновлен для поддержки -static.")
PYEOF

echo "==> 3. Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 4. Тестирование статической сборки..."
mkdir -p /tmp/test_static
cd /tmp/test_static

cat > test.x << 'XLANG'
.use GOIO

func main {
    con("Hello from static binary!");
    con("2 + 2 = ", 2 + 2);
}
XLANG

echo "--- Обычная сборка (libc) ---"
xc test.x -out test_dynamic
file test_dynamic

echo "--- Статическая сборка (-static) ---"
xc test.x -static -out test_static
file test_static

echo "--- Запуск статического бинарника ---"
./test_static
