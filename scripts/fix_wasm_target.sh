#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Установка пакета rust-wasm (таргет wasm32 для системного Rust)..."
sudo pacman -S --needed --noconfirm rust-wasm

echo "==> 2. Пересборка WASM-модуля..."
cd xlang-wasm
# Очищаем старые артефакты, чтобы wasm-pack не ругался
rm -rf target/wasm32-unknown-unknown
wasm-pack build --target web --out-dir ../web/wasm
cd ..

echo "==> 3. Запуск локального сервера..."
echo ""
echo "========================================="
echo "🎉 PLAYGROUND ГОТОВ!"
echo "========================================="
echo "Открой в браузере:"
echo "  http://localhost:8080/playground/index.html"
echo ""
cd web && python3 -m http.server 8080
