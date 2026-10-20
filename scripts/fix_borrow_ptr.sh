#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление Borrow Checker (копирование указателя)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Заменяем проблемный блок на копирование указателя до вызова gen_expr
old_block = """                if let Some(VarInfo::Scalar(ptr)) = vars.get(ptr_name) {
                    // Генерируем новое значение
                    let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars).into_float_value();
                    // Загружаем указатель из alloca и сохраняем по нему
                    let ptr_val_bv = builder.build_load(i8_ptr_type, *ptr, "ptr_load").unwrap();
                    let ptr_val = match ptr_val_bv { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected pointer") };
                    builder.build_store(ptr_val, val).unwrap();
                    return;
                } else {
                    panic!("Pointer '{}' not found", ptr_name);
                }"""

new_block = """                let ptr = if let Some(VarInfo::Scalar(p)) = vars.get(ptr_name) {
                    *p // копируем сам PointerValue, а не ссылку на него
                } else {
                    panic!("Pointer '{}' not found", ptr_name);
                };
                
                // Генерируем новое значение (теперь vars свободна для изменений)
                let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars).into_float_value();
                
                // Загружаем указатель из alloca и сохраняем по нему
                let ptr_val_bv = builder.build_load(i8_ptr_type, ptr, "ptr_load").unwrap();
                let ptr_val = match ptr_val_bv { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected pointer") };
                builder.build_store(ptr_val, val).unwrap();
                return;"""

content = content.replace(old_block, new_block)

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
