#!/bin/bash
set -e
cd ~/FOS

echo "==> Удаление сломанной строки с кавычками..."
python3 - << 'PYEOF'
with open('xlang-lsp/src/main.rs', 'r') as f:
    content = f.read()

old_block = """                                let mut start_line = 0;
                                let mut start_char = 0;
                                if let Some(var_name) = msg.split(''').nth(1) {
                                    // В реальном проекте мы бы нашли точную строку через парсер AST,
                                    // а пока просто ищем имя в тексте (для наглядности)
                                }"""

new_block = """                                let start_line = 0;
                                let start_char = 0;"""

content = content.replace(old_block, new_block)
with open('xlang-lsp/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Сборка LSP..."
cargo build --release
cp target/release/xlang-lsp ~/.local/bin/

echo "========================================="
echo "🎉 LSP УСПЕШНО СОБРАН!"
echo "========================================="
echo "Теперь запускай Neovim:"
echo "  nvim hi.x"
echo ""
echo "1. Внизу должно появиться 'LSP сервер xlang-lsp запущен!'"
echo "2. Нажми :w, чтобы сохранить и увидеть ошибку."
