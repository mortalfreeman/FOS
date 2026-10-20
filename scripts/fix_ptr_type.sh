#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление типа ptr_val..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Заменяем загрузку указателя на явное извлечение PointerValue
content = content.replace(
    'let ptr_val = builder.build_load(i8_ptr_type, *ptr, "ptr_load").unwrap();',
    'let ptr_val_bv = builder.build_load(i8_ptr_type, *ptr, "ptr_load").unwrap();\n                    let ptr_val = match ptr_val_bv { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected pointer") };'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_pointer
xc ptr.x -out ptr
./ptr
