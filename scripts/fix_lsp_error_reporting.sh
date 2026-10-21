#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление логики ошибок в парсере для LSP..."
python3 - << 'PYEOF'
with open('xlang-parser/src/parser.rs', 'r') as f:
    content = f.read()

# Находим логику обработки '='
old_logic = """                if self.match_token(Token::Assign) {
                    if !self.no_sec && !self.null_sec && !self.is_lsp {
                        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
                        let prompt = format!("Do you want to insert another = in {} (...) ? (Line {}:{})", if is_while {"while"} else {"if"}, line, col);
                        let choice = Confirm::new().with_prompt(prompt).default(false).interact().unwrap();
                        if choice { op = "==".to_string(); }
                        else { self.errors.push(format!("{}:{}:{}: error: '=' used instead of '=='", self.filename, line, col)); return None; }
                    } else { op = "==".to_string(); }"""

new_logic = """                if self.match_token(Token::Assign) {
                    if self.is_lsp {
                        // В LSP режиме записываем ошибку, но продолжаем парсить, чтобы не зависнуть
                        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
                        self.errors.push(format!("{}:{}:{}: error: '=' used instead of '=='", self.filename, line, col));
                        op = "==".to_string();
                    } else if !self.no_sec && !self.null_sec {
                        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
                        let prompt = format!("Do you want to insert another = in {} (...) ? (Line {}:{})", if is_while {"while"} else {"if"}, line, col);
                        let choice = Confirm::new().with_prompt(prompt).default(false).interact().unwrap();
                        if choice { op = "==".to_string(); }
                        else { self.errors.push(format!("{}:{}:{}: error: '=' used instead of '=='", self.filename, line, col)); return None; }
                    } else {
                        op = "==".to_string();
                    }"""

if old_logic not in content:
    print("ОШИБКА: Не удалось найти блок логики '=' в parser.rs.")
    exit(1)

content = content.replace(old_logic, new_logic)
with open('xlang-parser/src/parser.rs', 'w') as f:
    f.write(content)
print("✅ Логика парсера исправлена.")
PYEOF

echo "==> Пересборка всего..."
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cargo build --release -p xlang-lsp

echo "==> Убиваем старый LSP и обновляем..."
pkill -f xlang-lsp || true
sleep 1
cp target/release/xlang-lsp ~/.local/bin/
cp target/release/xlang-compiler ~/.local/bin/xc

echo "========================================="
echo "🎉 ГОТОВО! Теперь LSP видит ошибки."
echo "========================================="
echo "1. Закрой Neovim (нажми :q! если он открыт)."
echo "2. Открой файл снова: nvim /tmp/test_cli/main.x"
echo "3. Нажми 'i' и напиши 'if (op = 5) {'."
echo "4. Нажми Esc и посмотри на строку 11 — должна появиться красная линия!"
