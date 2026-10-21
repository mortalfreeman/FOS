#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Проверка mingw-w64..."
if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    echo "Установка mingw-w64-gcc..."
    sudo pacman -S --needed --noconfirm mingw-w64-gcc
fi

echo "==> 2. Модификация main.rs (жесткая привязка Windows для теста)..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Жестко меняем triple на Windows (чтобы проверить, работает ли LLVM)
content = re.sub(
    r'let triple = .*?;',
    'let triple = inkwell::targets::TargetTriple::create("x86_64-pc-windows-gnu");',
    content,
    flags=re.DOTALL
)

# Меняем RelocMode на Default (PIC для Windows не нужен)
content = content.replace('RelocMode::PIC', 'RelocMode::Default')

# Меняем линковщик на mingw
content = re.sub(
    r'let mut linker = .*?;',
    'let linker = "x86_64-w64-mingw32-gcc";',
    content,
    flags=re.DOTALL
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 4. Компиляция с выводом объектного файла..."
cd /tmp/windows_test
rm -f output.o win.exe

xc win.x -out win.exe

echo "==> 5. Проверка объектного файла (должен быть COFF/PE, а не ELF)..."
if [ -f output.o ]; then
    file output.o
    rm output.o
fi

echo "==> 6. Проверка исполняемого файла..."
file win.exe
