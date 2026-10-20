#!/bin/bash
set -e
cd ~/FOS

echo "==> Поиск блока match name.as_str() и добавление отладки..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Находим "match name.as_str()" и вставляем отладку перед ним
old_match = '''            match name.as_str() {
                "con" => {'''
new_match = '''            let debug_msg = builder.build_global_string_ptr("[ENTERED MATCH]\\n", "debug_match").unwrap();
            builder.build_call(printf, &[debug_msg.as_pointer_value().into()], "debug_match_call").unwrap();
            match name.as_str() {
                "con" => {'''

content = content.replace(old_match, new_match)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_ci
xc input_test.x -out input_test
./input_test
