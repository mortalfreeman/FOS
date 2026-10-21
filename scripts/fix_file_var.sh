#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление File в обработку Identifier..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

old_ident = """                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    VarInfo::Pointer(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => panic!("Unsupported variable type for '{}'", name)"""

new_ident = """                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    VarInfo::Pointer(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    VarInfo::File(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => panic!("Unsupported variable type for '{}'", name)"""

content = content.replace(old_ident, new_ident)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест FILEMAN..."
cd /tmp/fileman_test

xc test_file.x -out test_file
./test_file

echo ""
echo "=== Содержимое test.txt ==="
cat test.txt
