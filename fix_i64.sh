#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление i64_type в gen_stmt..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Ищем начало функции gen_stmt и добавляем i64_type
old_start = """    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());"""

new_start = """    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());"""

content = content.replace(old_start, new_start)
with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_zero_full
xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
