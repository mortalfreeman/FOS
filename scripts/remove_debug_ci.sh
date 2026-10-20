#!/bin/bash
set -e
cd ~/FOS

echo "==> Удаление сломанной отладки..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Удаляем отладочные вызовы
content = content.replace('''            let debug_msg = builder.build_global_string_ptr("[ENTERED MATCH]\\n", "debug_match").unwrap();
            builder.build_call(printf, &[debug_msg.as_pointer_value().into()], "debug_match_call").unwrap();
''', '')

# На случай, если остался кусок
content = content.replace('''            let debug_msg = builder.build_global_string_ptr("[CI CALLED]\\n", "debug_ci").unwrap();
            builder.build_call(printf, &[debug_msg.as_pointer_value().into()], "debug_ci_call").unwrap();
''', '')

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
