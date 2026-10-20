#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление пропущенных вызовов gen_expr..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. В массивах (Array)
content = content.replace(
    "let val = gen_expr(context, builder, module, elem, user_functions, libc, vars).into_float_value();",
    "let val = gen_expr(context, builder, module, elem, aliases, user_functions, libc, vars).into_float_value();"
)

# 2. В бинарных операциях (левая и правая часть)
content = content.replace(
    "let left_val = gen_expr(context, builder, module, left, user_functions, libc, vars);",
    "let left_val = gen_expr(context, builder, module, left, aliases, user_functions, libc, vars);"
)
content = content.replace(
    "let right_val = gen_expr(context, builder, module, right, user_functions, libc, vars);",
    "let right_val = gen_expr(context, builder, module, right, aliases, user_functions, libc, vars);"
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста (Макросы + Ввод строк)..."
cd ~/test_full
xc final_test.x -out final_test
./final_test
