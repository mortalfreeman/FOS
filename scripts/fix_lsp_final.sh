#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Принудительное завершение старого LSP..."
pkill -9 -f xlang-lsp || true
sleep 1

echo "==> 2. Исправление логики парсера (Regex)..."
python3 - << 'PYEOF'
import re
with open('xlang-parser/src/parser.rs', 'r') as f:
    content = f.read()

# Ищем любую вариацию `if !self.no_sec && !self.null_sec {`
pattern = r'if\s+!self\.no_sec\s*&&\s*!self\.null_sec\s*(?:&&\s*!self\.is_lsp\s*)?\{'
    
replacement = """if self.is_lsp {
                        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
                        self.errors.push(format!("{}:{}:{}: error: '=' used instead of '=='", self.filename, line, col));
                        op = "==".to_string();
                    } else if !self.no_sec && !self.null_sec {"""

new_content, count = re.subn(pattern, replacement, content)

if count == 0:
    print("❌ ОШИБКА: Не удалось найти блок 'if !self.no_sec' в parser.rs.")
    exit(1)
    
with open('xlang-parser/src/parser.rs', 'w') as f:
    f.write(new_content)
print(f"✅ Найдено и исправлено {count} блоков в parser.rs.")
PYEOF

echo "==> 3. Пересборка всего проекта..."
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cargo build --release -p xlang-lsp

echo "==> 4. Обновление бинарников..."
cp target/release/xlang-lsp ~/.local/bin/
cp target/release/xlang-compiler ~/.local/bin/xc

echo "========================================="
echo "🎉 ВСЁ ГОТОВО!"
echo "========================================="
echo "1. Открой Neovim: nvim /tmp/test_cli/main.x"
echo "2. Напиши с ошибкой: if (op = 5) {"
echo "3. Нажми Esc. Жди красную линию."
