#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Убираем жесткую привязку к /usr/local/use в компиляторе..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Ищем блок поиска библиотек
old_lib_search = """                    if parts.len() >= 2 { let sys_lib_path = PathBuf::from(format!("/usr/local/use/{}.xh", parts[1])); if sys_lib_path.exists() { std_libs.push(sys_lib_path); } }"""

new_lib_search = """                    if parts.len() >= 2 {
                        let lib_name = format!("{}.xh", parts[1]);
                        let base_dir = path.parent().unwrap_or(Path::new(""));
                        
                        // Ищем в 4 местах: рядом с файлом, в ./lib, в /usr/local/use (Linux), в C:\\fos_lib (Windows)
                        let candidates = vec![
                            base_dir.join(&lib_name),
                            base_dir.join("lib").join(&lib_name),
                            PathBuf::from(format!("/usr/local/use/{}", lib_name)),
                            PathBuf::from(format!("C:\\\\fos_lib\\\\{}", lib_name)),
                        ];
                        
                        for candidate in candidates {
                            if candidate.exists() {
                                std_libs.push(candidate);
                                break;
                            }
                        }
                    }"""

if old_lib_search in content:
    content = content.replace(old_lib_search, new_lib_search)
else:
    print("Внимание: Не удалось найти старый блок поиска библиотек, возможно, он уже изменен.")

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Компиляция xc для Linux (нативная)..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Попытка кросс-компиляции xc для Windows (xc.exe)..."
# Проверяем, установлен ли таргет для Windows
if rustup target list | grep -q "x86_64-pc-windows-gnu (installed)"; then
    cargo build --release --target x86_64-pc-windows-gnu -p xlang-compiler || echo "⚠️ Не удалось собрать xc для Windows (возможно, нужен mingw-llvm)."
else
    echo "⚠️ Для сборки xc.exe нужен rustup с таргетом x86_64-pc-windows-gnu."
fi

echo "==> 4. Создание портативных библиотек (чтобы работало везде)..."
mkdir -p /tmp/fos_portable/lib
cat > /tmp/fos_portable/lib/GOIO.xh << 'EOF'
#Define Header=GOIO
#END
EOF
cat > /tmp/fos_portable/lib/GOMATH.xh << 'EOF'
#Define Header=GOMATH
#END
EOF
cat > /tmp/fos_portable/lib/FILEMAN.xh << 'EOF'
#Define Header=FILEMAN
#END
EOF

echo "==> 5. Тест портативности (локальные библиотеки)..."
mkdir -p /tmp/test_portable
cp /tmp/fos_portable/lib/*.xh /tmp/test_portable/
cd /tmp/test_portable

cat > main.x << 'XLANG'
.use GOIO
.use GOMATH

func main {
    con("Portable X-lang!");
    con("2 + 2 = ", 2 + 2);
}
XLANG

xc main.x -out main_test
./main_test

echo "========================================="
echo "🎉 КРОСС-ПЛАТФОРМЕННАЯ БАЗА ГОТОВА!"
echo "========================================="
echo "Теперь библиотеки ищутся в папке с проектом!"
