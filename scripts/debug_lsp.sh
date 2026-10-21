#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Убиваем старый LSP..."
pkill -9 -f xlang-lsp || true
sleep 1

echo "==> 2. Добавление отладочных логов в LSP..."
python3 - << 'PYEOF'
with open('xlang-lsp/src/main.rs', 'r') as f:
    content = f.read()

# Логи в did_open
content = content.replace(
    'async fn did_open(&self, params: DidOpenTextDocumentParams) {',
    'async fn did_open(&self, params: DidOpenTextDocumentParams) {\n        eprintln!("LSP DEBUG: did_open called for {}", params.text_document.uri);'
)

# Логи в did_change
content = content.replace(
    'async fn did_change(&self, params: DidChangeTextDocumentParams) {',
    'async fn did_change(&self, params: DidChangeTextDocumentParams) {\n        eprintln!("LSP DEBUG: did_change called");'
)

# Логи в validate_doc
content = content.replace(
    'let mut parser = Parser::new(text, uri.as_str(), false, false, true);',
    'let mut parser = Parser::new(text, uri.as_str(), false, false, true);\n        eprintln!("LSP DEBUG: Parsing document...");'
)
content = content.replace(
    'for err in parser.errors {',
    'eprintln!("LSP DEBUG: Found {} errors", parser.errors.len());\n        for err in parser.errors {\n            eprintln!("LSP DEBUG: Error -> {}", err);'
)

# Логи перед отправкой
content = content.replace(
    'let _ = self.client.publish_diagnostics(uri.clone(), diagnostics, None).await;',
    'eprintln!("LSP DEBUG: Sending {} diagnostics", diagnostics.len());\n        let _ = self.client.publish_diagnostics(uri.clone(), diagnostics, None).await;'
)

with open('xlang-lsp/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Пересборка LSP..."
cargo build --release -p xlang-lsp
cp target/release/xlang-lsp ~/.local/bin/

echo "========================================="
echo "🎉 ГОТОВО!"
echo "========================================="
echo "1. Открой Neovim заново: nvim /tmp/test_cli/main.x"
echo "2. Сделай ошибку: if (op = 5) {"
echo "3. Выйди из Neovim и выполни:"
echo "   cat ~/.local/state/nvim/lsp.log | grep 'LSP DEBUG' | tail -n 20"
