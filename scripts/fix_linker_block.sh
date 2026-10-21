#!/bin/bash
set -e
cd ~/FOS

echo "==> Жесткая замена блока линковки..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Ищем старый блок линковки (точная строка)
old_linker = '''    let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };
    if process::Command::new(linker).arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("Linker failed").success() {'''

new_linker = '''    let link_status = if is_static && target_os == "linux" {
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
    };

    if link_status.success() {'''

if old_linker not in content:
    print("❌ ОШИБКА: Не найден старый блок линковки. Проверь структуру файла.")
    exit(1)

content = content.replace(old_linker, new_linker)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Блок линковки успешно заменен.")
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тестирование..."
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
