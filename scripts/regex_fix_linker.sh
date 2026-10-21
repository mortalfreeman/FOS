#!/bin/bash
set -e
cd ~/FOS

echo "==> Замена блока линковки через Regex..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Регулярное выражение, которое ловит блок от let linker = ... до success() {
pattern = re.compile(r'let linker = if target_os == "windows".*?\.success\(\) \{', re.DOTALL)

replacement = '''let link_status = if is_static && target_os == "linux" {
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

if not pattern.search(content):
    print("❌ ОШИБКА: Блок линковки не найден по регулярному выражению.")
    exit(1)

content = pattern.sub(replacement, content)

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
