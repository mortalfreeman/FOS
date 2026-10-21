#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление вариантов In и Len в enum Token..."
python3 - << 'PYEOF'
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()

# Ищем определение enum Token и добавляем In, Len после Switch
old_enum = "Switch, Case, Default, Colon,"
new_enum = "Switch, Case, Default, Colon, In, Len,"

if "In, Len," not in content:
    content = content.replace(old_enum, new_enum)

with open('xlang-lexer/src/lib.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-lexer
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест новых фич..."
mkdir -p /tmp/test_v3
cd /tmp/test_v3

cat > test.x << 'XLANG'
.use GOIO

func main {
    con("=== Test 1: For-in loop ===");
    numbers = [10, 20, 30, 40];
    sum = 0;
    for (num in numbers) {
        con("Number: ", num);
        sum = sum + num;
    }
    con("Sum: ", sum);

    con("\n=== Test 2: String comparison ===");
    password = "secret";
    if (password == "secret") {
        con("Access granted!");
    } else {
        con("Access denied!");
    }

    con("\n=== Test 3: len() function ===");
    name = "X-lang";
    con("Length of string: ", len(name));
    con("Length of array: ", len(numbers));
}
XLANG

xc test.x -out test_bin
./test_bin
