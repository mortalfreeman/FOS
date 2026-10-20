#!/bin/bash
set -e
cd ~/FOS

echo "==> Настройка Cargo Workspace..."
cat > Cargo.toml << 'TOML'
[workspace]
members = [
    "xstd",
    "xlang-lexer",
    "xlang-compiler",
    "xlang-lsp",
]
resolver = "2"

[profile.release]
panic = "abort"
opt-level = 3
TOML

echo "==> Сборка xstd..."
cargo build --release -p xstd
cp target/release/libxstd.a .

echo "==> Сборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Создание теста Zero-Dependency..."
mkdir -p ~/test_zero_full
cd ~/test_zero_full

cat > zero.x << 'XLANG'
func main {
    name = "X-lang";
    greeting = "Hello, " + name + "!";
    con(greeting);

    arr = [10, 20, 30];
    sum = 0;
    for (i = 0; i < 3; i = i + 1) {
        sum = sum + arr[i];
    }
    con("Sum: ", sum);

    if (sum > 50) {
        con("Sum is greater than 50");
    }
}
XLANG

echo "==> Компиляция..."
xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
