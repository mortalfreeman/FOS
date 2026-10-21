#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Сборка релизной версии компилятора..."
cargo build --release -p xlang-compiler

echo "==> 2. Подготовка портативного архива..."
mkdir -p release_build/lib
cp target/release/xlang-compiler release_build/xc
cp /usr/local/use/GOIO.xh release_build/lib/ 2>/dev/null || true
cp /usr/local/use/GOMATH.xh release_build/lib/ 2>/dev/null || true
cp /usr/local/use/FILEMAN.xh release_build/lib/ 2>/dev/null || true

# Создаем README для архива
cat > release_build/README.txt << 'EOF'
FOS X-lang Compiler (xc) v2.0.0
===============================

Установка:
1. Распакуйте архив.
2. Переместите файл 'xc' в /usr/local/bin/ (Linux) или добавьте папку в PATH (Windows).
3. Переместите папку 'lib' в папку с вашим проектом.

Пример кода:
.use GOIO
func main {
    con("Hello, FOS!");
}

Запуск:
xc main.x -out main && ./main
EOF

cd release_build
tar -czvf ../fos-linux-x86_64.tar.gz *
cd ..
rm -rf release_build

echo "==> 3. Проверка наличия GitHub CLI (gh)..."
if ! command -v gh &> /dev/null; then
    echo "⚠️ GitHub CLI (gh) не установлен. Устанавливаем..."
    sudo pacman -S --needed --noconfirm github-cli
fi

echo "==> 4. Проверка авторизации в GitHub..."
if ! gh auth status &> /dev/null; then
    echo "⚠️ Вы не авторизованы в GitHub."
    echo "Пожалуйста, выполните 'gh auth login' (выберите GitHub.com -> HTTPS -> Login with a web browser),"
    echo "а затем запустите этот скрипт снова."
    exit 1
fi

echo "==> 5. Создание тега и публикация релиза..."
git tag -a v2.0.0 -m "Release v2.0.0: Cross-platform compiler (Linux + Windows)"
git push origin v2.0.0

gh release create v2.0.0 \
    ./fos-linux-x86_64.tar.gz \
    --title "FOS X-lang v2.0.0 — Cross-Platform Release 🚀" \
    --notes "Первый официальный релиз X-lang!
    
Включает:
- Кроссплатформенный компилятор xc (сборка под Linux и Windows).
- Системные библиотеки: GOIO, GOMATH, FILEMAN.
- Встроенный менеджер проектов (xc new, xc run).

**Установка (Linux):**
\`\`\`bash
tar -xzvf fos-linux-x86_64.tar.gz
sudo mv xc /usr/local/bin/
\`\`\`"

echo "========================================="
echo "🎉 РЕЛИЗ v2.0.0 УСПЕШНО ОПУБЛИКОВАН!"
echo "========================================="
echo "Зайди на https://github.com/mortalfreeman/FOS/releases и посмотри на свой релиз!"
