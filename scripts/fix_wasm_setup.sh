#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Установка wasm-pack и таргета wasm32 через pacman/rustup..."
if command -v pacman &> /dev/null; then
    sudo pacman -S --needed --noconfirm wasm-pack
else
    # Если не Arch, пробуем через cargo
    cargo install wasm-pack
fi

# Добавляем target для WASM (если используется rustup)
if command -v rustup &> /dev/null; then
    rustup target add wasm32-unknown-unknown
fi

echo "==> 2. Сборка WASM..."
cd xlang-wasm
# Если wasm-pack не видит Rust, передаем путь
export PATH="$PATH:$HOME/.cargo/bin"
wasm-pack build --target web --out-dir ../web/wasm
cd ..

echo "==> 3. Запуск локального сервера..."
echo ""
echo "========================================="
echo "🎉 PLAYGROUND ГОТОВ!"
echo "========================================="
echo "Сейчас запустится сервер. Открой в браузере:"
echo "  http://localhost:8080/playground/index.html"
echo ""
cd web && python3 -m http.server 8080
