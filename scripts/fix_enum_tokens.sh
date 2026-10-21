#!/bin/bash
set -e
cd ~/FOS

echo "==> Принудительное добавление In и Len в enum Token..."
python3 - << 'PYEOF'
import re
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()

# Ищем начало enum Token и добавляем In, Len, если их там нет
if 'In,' not in content or 'Len,' not in content:
    # Вставляем после открывающей скобки { или после первого элемента
    content = re.sub(
        r'pub enum Token \{',
        'pub enum Token {\n    In, Len,',
        content,
        count=1
    )
    print("Добавлено In, Len в начало enum Token.")

with open('xlang-lexer/src/lib.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-lexer
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест новых фич..."
cd /tmp/test_v3

xc test.x -out test_bin
./test_bin
