#!/bin/bash
set -e
cd ~/FOS

echo "==> Удаление нерабочего set_flags и пересборка..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Удаляем строку с set_flags, которая вызывает ошибку
content = content.replace(
    '    if let Err(e) = module.set_flags(inkwell::module::Flag::UnsafeFpMath) { eprintln!("Flag error: {:?}", e); }\n',
    ''
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск честного бенчмарка..."
cd ~/FOS/benchmarks
xc test.x -out test_x_opt

echo -e "\n--- C++ (Fair, int64) ---"
time ./test_cpp_fair

echo -e "\n--- X-lang (LLVM default<O3>) ---"
time ./test_x_opt
