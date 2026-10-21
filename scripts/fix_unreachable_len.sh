#!/bin/bash
set -e
cd ~/FOS

echo "==> Принудительное добавление Token::Len в match..."
python3 - << 'PYEOF'
with open('xlang-parser/src/parser.rs', 'r') as f:
    content = f.read()

# Вставляем Token::Len перед _ => unreachable!()
if 'Token::Len => "len",' not in content:
    content = content.replace(
        '_ => unreachable!(),',
        'Token::Len => "len",\n                    _ => unreachable!(),'
    )
    print("✅ Добавлена ветка Token::Len => \"len\".")
else:
    print("✅ Ветка уже существует.")

with open('xlang-parser/src/parser.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тестирование..."
cd ~/FOS/test_v3
xc test.x -out test_bin
./test_bin
