#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление Token::Len в parse_primary..."
python3 - << 'PYEOF'
with open('xlang-parser/src/parser.rs', 'r') as f:
    content = f.read()

# Ищем список токенов в parse_primary и добавляем Token::Len
old_primary = "Token::Con | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil => {"
new_primary = "Token::Con | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil | Token::Len => {"

if old_primary in content:
    content = content.replace(old_primary, new_primary)
else:
    # Если не нашли, пробуем другой вариант (на случай если Token::Ci добавлен)
    old_primary2 = "Token::Con | Token::Ci | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil => {"
    new_primary2 = "Token::Con | Token::Ci | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil | Token::Len => {"
    if old_primary2 in content:
        content = content.replace(old_primary2, new_primary2)
    else:
        print("⚠️ Не удалось найти список токенов в parse_primary. Возможно, он уже изменен.")

# Добавляем маппинг имени для Token::Len
old_match = '''                    Token::Round => "round", Token::Floor => "floor", Token::Ceil => "ceil",
                    _ => unreachable!(),'''
new_match = '''                    Token::Round => "round", Token::Floor => "floor", Token::Ceil => "ceil",
                    Token::Len => "len",
                    _ => unreachable!(),'''
if old_match in content:
    content = content.replace(old_match, new_match)

with open('xlang-parser/src/parser.rs', 'w') as f:
    f.write(content)
print("✅ Парсер обновлен.")
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тестирование..."
cd ~/FOS/test_v3
xc test.x -out test_bin
./test_bin
