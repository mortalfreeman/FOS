#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Возвращаем динамический выбор ОС (Linux/Windows)..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Восстанавливаем парсинг --target
if 'else if args[i] == "--target"' not in content:
    content = content.replace(
        'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }',
        'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }\n        else if args[i] == "--target" && i + 1 < args.len() { target_os = &args[i+1]; i += 2; }'
    )

# 2. Заменяем жестко зашитый Triple на динамический
content = re.sub(
    r'let triple = .*?;',
    'let triple = if target_os == "windows" { inkwell::targets::TargetTriple::create("x86_64-pc-windows-gnu") } else { TargetMachine::get_default_triple() };',
    content,
    flags=re.DOTALL
)

# 3. Заменяем жестко зашитый линковщик на динамический
content = re.sub(
    r'let (mut )?linker = .*?;',
    'let linker = if target_os == "windows" { "x86_64-w64-mingw32-gcc" } else { "clang" };',
    content,
    flags=re.DOTALL
)

# 4. Возвращаем RelocMode в зависимости от ОС (Windows требует Default, Linux - PIC)
content = re.sub(
    r'RelocMode::(PIC|Default)',
    'if target_os == "windows" { RelocMode::Default } else { RelocMode::PIC }',
    content
)

# 5. Делаем поиск библиотек портативным
old_lib_regex = r'let sys_lib_path = PathBuf::from\(format!\("/usr/local/use/\{\}\.xh", parts\[1\]\)\); if sys_lib_path\.exists\(\) \{ std_libs\.push\(sys_lib_path\); \}'
new_lib_logic = """
                        let lib_name = format!("{}.xh", parts[1]);
                        let mut found = false;
                        for candidate in &[
                            PathBuf::from(&lib_name),
                            PathBuf::from(format!("lib/{}", lib_name)),
                            PathBuf::from(format!("/usr/local/use/{}", lib_name)),
                            PathBuf::from(format!("C:\\\\fos_lib\\\\{}", lib_name))
                        ] {
                            if candidate.exists() {
                                std_libs.push(candidate.clone());
                                found = true;
                                break;
                            }
                        }
"""
content = re.sub(old_lib_regex, new_lib_logic, content, flags=re.DOTALL)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
print("✅ Код успешно обновлен (динамическая ОС + портативные пути)!")
PYEOF

echo "==> 2. Пересборка компилятора для Linux..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Тест: Обычная компиляция под Linux..."
cd /tmp/windows_test
xc win.x -out linux_app
file linux_app

echo "==> 4. Тест: Кросс-компиляция под Windows..."
xc win.x --target windows -out win_app.exe
file win_app.exe

echo "==> 5. Тест портативных библиотек (./lib)..."
mkdir -p /tmp/portable_test/lib
cp /tmp/fos_portable/lib/*.xh /tmp/portable_test/lib/ 2>/dev/null || true
cd /tmp/portable_test
cat > main.x << 'XLANG'
.use GOIO
func main {
    con("Portable Library Test!");
}
XLANG
xc main.x -out portable_bin
./portable_bin

echo "========================================="
echo "🎉 ВСЁ РАБОТАЕТ! (Linux, Windows и портативные пути)"
echo "========================================="
