#!/bin/bash
set -e
cd ~/FOS

echo "==> Замена sys_write на write (для линковки с libc)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Меняем имя функции в объявлении
content = content.replace(
    'let sys_write = module.add_function("sys_write",',
    'let sys_write = module.add_function("write",'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста буферизации..."
cd ~/test_std
xc fast_io.x -out fast_io
START=$(date +%s%N)
./fast_io > /dev/null
END=$(date +%s%N)
echo "Время буферизированного вывода: $(( (END-START)/1000000 )) мс"
