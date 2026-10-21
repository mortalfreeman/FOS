#!/bin/bash
set -e
cd ~/FOS

echo "==> Жесткая вставка -static и логики линковки..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Находим начало парсинга аргументов и заменяем весь блок до files_to_compile
start_idx = content.find('let args: Vec<String> = env::args().collect();')
end_idx = content.find('let files_to_compile = resolve_project_files(&target_path);')

if start_idx != -1 and end_idx != -1:
    new_block = '''let args: Vec<String> = env::args().collect();
    if args.len() < 2 { println!("Usage: xc <file.x> [-out <name>] [--target windows] [-static]"); process::exit(1); }
    
    let mut target_os = "linux".to_string();
    let mut is_static = false;
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
        } else if args[i] == "-static" {
            is_static = true;
            i += 1;
        } else if args[i] == "run" || args[i] == "build" {
            is_run = args[i] == "run";
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
    println!("DEBUG: target_os = {}, static = {}, out = {}", target_os, is_static, final_out);

    '''
    content = content[:start_idx] + new_block + content[end_idx:]

# 2. Заменяем блок линковки на основе is_static
pattern = re.compile(r'let link_status =.*?\n    \};', re.DOTALL)
new_linker = '''let link_status = if is_static && target_os == "linux" {
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
    };'''
content = pattern.sub(new_linker, content)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Блоки парсинга и линковки успешно заменены.")
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
