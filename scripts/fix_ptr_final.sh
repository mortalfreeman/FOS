#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление указателей (f64*)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# В gen_expr для Ref меняем создание alloca на f64 ptr
content = content.replace(
    'let alloca = builder.build_alloca(val.get_type(), "ref_tmp").unwrap();',
    'let alloca = builder.build_alloca(f64_type.ptr_type(AddressSpace::default()), "ref_tmp").unwrap();'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_pointer
xc ptr.x -out ptr
./ptr
