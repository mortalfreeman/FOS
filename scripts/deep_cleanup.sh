#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Удаление неиспользуемых папок..."
rm -rf pep pep-qt pep-installer xstd xlang-wasm web/playground web/wasm
rm -rf target

echo "==> 2. Обновление Cargo.toml (оставляем только нужные крейты)..."
cat > Cargo.toml << 'EOF'
[workspace]
members = [
    "xlang-lexer",
    "xlang-parser",
    "xlang-compiler",
    "xlang-lsp",
]
resolver = "2"

[profile.release]
panic = "abort"
opt-level = 3
EOF

echo "==> 3. Проверка, что проект все еще собирается..."
cargo build --release -p xlang-compiler
cargo build --release -p xlang-lsp
cp target/release/xlang-compiler ~/.local/bin/xc
cp target/release/xlang-lsp ~/.local/bin/xlang-lsp

echo "==> 4. Обновление README.md (удаление упоминаний PEP и WASM)..."
# Быстро чистим README от старых компонентов
sed -i '/PEP/d' README.md
sed -i '/wasm/d' README.md
sed -i '/playground/d' README.md

echo "==> 5. Коммит и пуш на GitHub..."
git add -A
git commit -m "Refactor: Deep cleanup. Removed obsolete PEP editors, WASM playground, and no_std experiments. Kept only X-lang core, LSP, and Web."
git push origin main

echo "========================================="
echo "🧹 РЕПОЗИТОРИЙ ПОЛНОСТЬЮ ОЧИЩЕН!"
echo "========================================="
echo "Теперь на GitHub лежит только:"
echo "- xlang-compiler (xc)"
echo "- xlang-lexer + xlang-parser"
echo "- xlang-lsp"
echo "- web (лендинг)"
echo "- benchmarks + examples + scripts"
