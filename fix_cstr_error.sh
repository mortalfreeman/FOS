#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление зависимостей (удаление cstr 1.0)..."
cat > pep/Cargo.toml << 'EOF'
[package]
name = "pep"
version = "1.0.0"
edition = "2021"

[dependencies]
qmetaobject = { version = "0.2", features = ["qtquick"] }
xlang-lexer = { path = "../xlang-lexer" }
EOF

echo "==> Исправление импортов в main.rs..."
python3 - << 'PYEOF'
with open('pep/src/main.rs', 'r') as f:
    content = f.read()

# Меняем импорт cstr на qmetaobject::cstr
content = content.replace(
    "use cstr::cstr;",
    "use qmetaobject::cstr;"
)

with open('pep/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Сборка..."
cargo build --release

echo "==> Установка..."
cp target/release/pep ~/.local/bin/pep

echo "========================================="
echo "🎉 PEP v1.0 (Qt6 GUI) УСПЕШНО СОБРАН!"
echo "========================================="
echo "Запускай редактор (откроется нативное окно):"
echo "  pep"
