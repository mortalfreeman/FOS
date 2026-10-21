#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создаем ассемблерный рантайм xstd.s в корне проекта..."
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

echo "==> 2. Жесткая вставка флага -static в main.rs..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем переменную is_static, если её нет
if 'let mut is_static = false;' not in content:
    content = content.replace('let mut target_os = "linux".to_string();', 'let mut target_os = "linux".to_string();\n    let mut is_static = false;')

# 2. Вставляем обработку -static прямо в начало while i < args.len()
# Заменяем первую строку внутри while на проверку -static
content = re.sub(
    r'while i < args\.len\(\) \{',
    'while i < args.len() {\n        if args[i] == "-static" { is_static = true; i += 1; continue; }',
    content,
    count=1
)

# 3. Заменяем блок линковки
pattern = re.compile(r'let link_status =.*?\};', re.DOTALL)
new_linker = """let link_status = if is_static && target_os == "linux" {
        println!("DEBUG: Static linking via as/ld...");
        let _ = std::fs::copy("/home/freeman/FOS/xstd.s", "xstd.s");
        let as_status = process::Command::new("as").arg("xstd.s").arg("-o").arg("xstd.o").status().expect("as failed");
        if as_status.success() {
            process::Command::new("ld").arg("-o").arg(&final_out).arg("output.o").arg("xstd.o").arg("-static").status().expect("ld failed")
        } else {
            std::process::exit(1);
        }
    } else {
        let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };
        process::Command::new(linker).arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("Linker failed")
    };"""
content = pattern.sub(new_linker, content)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Патч применен.")
PYEOF

echo "==> 3. Пересборка компилятора..."
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

echo "--- Компиляция (-static) ---"
xc test.x -static -out test_static
file test_static

echo "--- Запуск ---"
./test_static
