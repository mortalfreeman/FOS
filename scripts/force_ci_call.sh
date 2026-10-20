#!/bin/bash
set -e
cd ~/FOS

echo "==> Принудительная проверка вызова ci..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Находим блок "ci" в gen_expr и добавляем туда printf в самое начало
old_ci_start = '''                "ci" => {
                    if args.len() >= 2 {'''
new_ci_start = '''                "ci" => {
                    let debug_msg = builder.build_global_string_ptr("[CI CALLED]\\n", "debug_ci").unwrap();
                    builder.build_call(printf, &[debug_msg.as_pointer_value().into()], "debug_ci_call").unwrap();
                    if args.len() >= 2 {'''

content = content.replace(old_ci_start, new_ci_start)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста (проверка вызова ci)..."
cd ~/test_ci
xc input_test.x -out input_test
./input_test
