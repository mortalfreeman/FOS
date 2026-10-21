#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Исправление флага -static и путей в main.rs..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Принудительно добавляем is_static в парсинг
if 'let mut is_static = false;' not in content:
    content = content.replace(
        'let mut target_os = "linux".to_string();',
        'let mut target_os = "linux".to_string();\n    let mut is_static = false;'
    )
    content = content.replace(
        'else if args[i] == "--target" && i + 1 < args.len() {',
        'else if args[i] == "-static" { is_static = true; i += 1; }\n        else if args[i] == "--target" && i + 1 < args.len() {'
    )

# 2. Меняем объявление sys_write/write, если static
if 'let write_fn = if is_static {' not in content:
    content = content.replace(
        'let write_fn = module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None);',
        'let write_fn = if is_static { module.add_function("sys_write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None) } else { module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None) };'
    )

# 3. Заменяем логику линковки
old_link = '''    let link_status = if is_static && target_os == "linux" {
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
    };'''

new_link = '''    let link_status = if is_static && target_os == "linux" {
        println!("DEBUG: Static linking via as/ld...");
        // Копируем xstd.s в текущую папку, чтобы as его нашел
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
    };'''

# 4. Если блок уже заменен, но не работает, заменяем на новый
if 'let link_status = if is_static && target_os == "linux" {' in content:
    # Заменяем старый блок на новый
    import re
    content = re.sub(
        r'let link_status = if is_static && target_os == "linux" \{.*?\};',
        new_link,
        content,
        flags=re.DOTALL
    )

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Логика линковки обновлена.")
PYEOF

echo "==> 2. Пересборка..."
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

echo "--- Статическая сборка (-static) ---"
xc test.x -static -out test_static
file test_static

echo "--- Запуск ---"
./test_static
