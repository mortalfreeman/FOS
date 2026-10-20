#!/bin/bash
cd ~/FOS

echo "==> Исправление set_fast_math_flags и вывод IR..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Исправляем вызов: передаем битовую маску (все флаги включены)
content = content.replace(
    'unsafe { i.set_fast_math_flags(true, true, true, true, true); }',
    'unsafe { i.set_fast_math_flags(0b11111); }'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Вывод LLVM IR для t_con.x..."
cd ~/test_crash
xc t_con.x --dump-ir -out t_con_bin
echo "--- Запуск ---"
./t_con_bin
echo "Код возврата: $?"
