#!/bin/bash
set -e
cd ~/FOS

echo "==> Восстановление структур Xstd и VarInfo..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Проверяем, есть ли уже VarInfo с String
if 'enum VarInfo<' not in content or 'String(PointerValue' not in content:
    # Ищем, куда вставить (перед fn main)
    insert_pos = content.find('fn main()')
    if insert_pos != -1:
        structs = """
enum VarInfo<'ctx> { 
    Scalar(PointerValue<'ctx>), 
    Array(PointerValue<'ctx>, u32), 
    String(PointerValue<'ctx>) 
}

struct Xstd<'ctx> {
    malloc: FunctionValue<'ctx>, strlen: FunctionValue<'ctx>, strcpy: FunctionValue<'ctx>,
    strcat: FunctionValue<'ctx>, print_str: FunctionValue<'ctx>, print_num: FunctionValue<'ctx>,
    sys_exit: FunctionValue<'ctx>, sys_write: FunctionValue<'ctx>,
}

"""
        content = content[:insert_pos] + structs + content[insert_pos:]
        print("Структуры восстановлены.")
    else:
        print("ОШИБКА: не удалось найти fn main()")
else:
    print("Структуры уже на месте.")

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_zero_full
xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
