#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление парсинга --target и генерации PE32+..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Жестко переписываем блок парсинга аргументов
old_args = """    let mut out_name = None;
    let mut target_os = "linux";
    let mut i = if is_run || is_build { 3 } else { 2 };
    while i < args.len() {
        if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }
        else if args[i] == "--target" && i + 1 < args.len() { target_os = &args[i+1]; i += 2; }
        else { i += 1; }
    }"""

new_args = """    let mut out_name = None;
    let mut target_os = "linux".to_string();
    let mut i = if is_run || is_build { 3 } else { 2 };
    while i < args.len() {
        if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }
        else if args[i] == "--target" && i + 1 < args.len() { target_os = args[i+1].clone(); i += 2; }
        else { i += 1; }
    }"""

if old_args in content:
    content = content.replace(old_args, new_args)
else:
    print("Внимание: не найден блок парсинга args (возможно, он изменился).")

# 2. Переписываем создание Target и Triple
old_triple = """    let triple = inkwell::targets::TargetTriple::create("x86_64-pc-windows-gnu");
    let target = Target::from_triple(&triple).unwrap();"""
new_triple = """    let triple = if target_os == "windows" {
        inkwell::targets::TargetTriple::create("x86_64-pc-windows-gnu")
    } else {
        TargetMachine::get_default_triple()
    };
    module.set_triple(&triple);
    let target = Target::from_triple(&triple).unwrap();"""
if old_triple in content:
    content = content.replace(old_triple, new_triple)
else:
    # Если там уже стоит динамический, но без set_triple
    content = content.replace(
        "let triple = if target_os == \"windows\" { inkwell::targets::TargetTriple::create(\"x86_64-pc-windows-gnu\") } else { TargetMachine::get_default_triple() };",
        "let triple = if target_os == \"windows\" { inkwell::targets::TargetTriple::create(\"x86_64-pc-windows-gnu\") } else { TargetMachine::get_default_triple() };\n    module.set_triple(&triple);"
    )

# 3. Переписываем RelocMode и linker
content = content.replace(
    "RelocMode::Default, CodeModel::Default",
    "if target_os == \"windows\" { RelocMode::Default } else { RelocMode::PIC }, CodeModel::Default"
)
content = content.replace(
    "RelocMode::PIC, CodeModel::Default",
    "if target_os == \"windows\" { RelocMode::Default } else { RelocMode::PIC }, CodeModel::Default"
)
content = content.replace(
    'let linker = "x86_64-w64-mingw32-gcc";',
    'let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };'
)
content = content.replace(
    'let mut linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };',
    'let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Патч применен.")
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тестирование..."
cd /tmp/windows_test

echo "--- 1. Linux ---"
xc win.x -out linux_app
file linux_app

echo "--- 2. Windows ---"
xc win.x --target windows -out win_app.exe
file win_app.exe
