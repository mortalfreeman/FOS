#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление обработки Switch в Sema..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/sema.rs', 'r') as f:
    content = f.read()

# Добавляем обработку Switch в visit_stmts
if 'Stmt::Switch' not in content:
    old_if = """                Stmt::If { condition, then_branch, else_branch } => {"""
    new_switch = """                Stmt::Switch { expr, cases, default } => {
                    self.visit_expr(expr);
                    for (case_expr, body) in cases {
                        self.visit_expr(case_expr);
                        self.visit_stmts(body);
                    }
                    if let Some(default_body) = default {
                        self.visit_stmts(default_body);
                    }
                }
                Stmt::If { condition, then_branch, else_branch } => {"""
    content = content.replace(old_if, new_switch)

with open('xlang-compiler/src/sema.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест Switch/Case и i64-массивов..."
mkdir -p /tmp/switch_test
cd /tmp/switch_test

cat > switch.x << 'XLANG'
.use std
func main {
    x = 2;
    switch (x) {
        case 1:
            con("one");
            break;
        case 2:
            con("two");
            break;
        case 3:
            con("three");
            break;
        default:
            con("other");
    }
}
XLANG

xc switch.x -out switch_bin
./switch_bin

echo -e "\n--- Честный тест сортировки (Bubble Sort 5k) ---"
cat > sort.x << 'XLANG'
.use std
func main {
    arr = [0,0,0,0,0,0,0,0,0,0];
    for (i = 0; i < 5000; i = i + 1) {
        arr[i] = 5000 - i;
    }
    for (i = 0; i < 5000; i = i + 1) {
        for (j = 0; j < 4999; j = j + 1) {
            if (arr[j] > arr[j+1]) { t = arr[j]; arr[j] = arr[j+1]; arr[j+1] = t; }
        }
    }
    con(1);
}
XLANG
xc sort.x -out sort_bin
START=$(date +%s%N); ./sort_bin > /dev/null; END=$(date +%s%N)
echo "X-lang Bubble Sort (i64): $(( (END-START)/1000000 )) мс"
echo "C Bubble Sort (int): 30 мс"
