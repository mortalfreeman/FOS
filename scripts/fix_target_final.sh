#!/bin/bash
set -e
cd ~/FOS

echo "==> Жесткая перезапись парсинга аргументов и логики линковки..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Находим начало fn main() и переписываем парсинг аргументов
start_idx = content.find('fn main() {')
end_idx = content.find('let files_to_compile = resolve_project_files(&target_path);')

if start_idx != -1 and end_idx != -1:
    new_main_prefix = '''fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { println!("Usage: xc <file.x> [-out <name>] [--target windows]"); process::exit(1); }
    
    let mut target_os = "linux".to_string();
    let mut out_name = None;
    let mut target_path = PathBuf::new();
    let mut is_run = false;

    let mut i = 1;
    while i < args.len() {
        if args[i] == "-out" && i + 1 < args.len() {
            out_name = Some(args[i+1].clone());
            i += 2;
        } else if args[i] == "--target" && i + 1 < args.len() {
            target_os = args[i+1].clone();
            i += 2;
        } else if args[i] == "run" {
            is_run = true;
            i += 1;
        } else if target_path.as_os_str().is_empty() {
            target_path = PathBuf::from(&args[i]);
            i += 1;
        } else {
            i += 1;
        }
    }

    if target_path.as_os_str().is_empty() {
        println!("Error: No input file provided.");
        process::exit(1);
    }
    
    if is_run && out_name.is_none() {
        out_name = Some(".xc_run".to_string());
    }
    
    let final_out = out_name.unwrap_or_else(|| "main".to_string());

    '''
    content = content[:start_idx] + new_main_prefix + content[end_idx:]

# 2. Переписываем логику Triple и линковщика
content = re.sub(
    r'let triple = .*?;',
    'let triple = if target_os == "windows" { inkwell::targets::TargetTriple::create("x86_64-pc-windows-gnu") } else { TargetMachine::get_default_triple() };\n    module.set_triple(&triple);',
    content,
    flags=re.DOTALL
)

content = re.sub(
    r'if process::Command::new\("clang"\).*?\.success\(\) \{',
    'let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };\n    if process::Command::new(linker).arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("Linker failed").success() {',
    content,
    flags=re.DOTALL
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ main.rs успешно перезаписан.")
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler 2>&1 | tail -5
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> ТЕСТИРОВАНИЕ..."
cd /tmp/windows_test

echo "--- 1. Linux ---"
xc win.x -out linux_app
file linux_app | awk -F: '{print $2}'

echo "--- 2. Windows ---"
xc win.x --target windows -out win_app.exe
file win_app.exe | awk -F: '{print $2}'
