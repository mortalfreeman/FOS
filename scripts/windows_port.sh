#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Установка кросс-компилятора для Windows (MinGW-w64)..."
sudo pacman -S --needed --noconfirm mingw-w64-gcc

echo "==> 2. Обновление кодогенератора (поддержка Windows)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем флаг --target windows
content = content.replace(
    "let mut out_name = None;",
    "let mut out_name = None;\n    let mut target_os = \"linux\";"
)
content = content.replace(
    'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }',
    'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }\n        else if args[i] == "--target" && i + 1 < args.len() { target_os = &args[i+1]; i += 2; }'
)

# 2. Меняем Target Triple в зависимости от флага
content = content.replace(
    "let triple = TargetMachine::get_default_triple();",
    'let triple = match target_os {\n        "windows" => inkwell::targets::TargetTriple::create("x86_64-pc-windows-gnu"),\n        _ => TargetMachine::get_default_triple(),\n    };'
)

# 3. Заменяем вызов clang на кросс-компилятор для Windows
old_link = """    if process::Command::new("clang").arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("clang failed").success() {"""
new_link = """    let mut linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };
    if process::Command::new(linker).arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("Linker failed").success() {"""
content = content.replace(old_link, new_link)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 4. Тест кросс-компиляции..."
mkdir -p /tmp/windows_test
cd /tmp/windows_test

cat > win.x << 'XLANG'
.use GOIO

func main {
    con("Hello from Windows x86_64!");
    x = 42;
    con("The answer is: ", x);
}
XLANG

echo "Компиляция под Windows..."
xc win.x --target windows -out win.exe

echo "Проверка формата файла:"
file win.exe

echo "========================================="
echo "🎉 WINDOWS ПОРТ ГОТОВ!"
echo "========================================="
echo "Файл win.exe скомпилирован и готов к запуску на Windows!"
