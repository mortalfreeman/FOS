#!/bin/bash
set -e
cd ~/FOS

echo "==> Отладка std_read_line..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Добавляем отладочный вывод в std_read_line (после read)
old_read = """    let bytes_read = builder.build_call(read_fn, &[i32_type.const_zero().into(), c_ptr.into(), i64_type.const_int(1, false).into()], "read").unwrap().try_as_basic_value().left().unwrap().into_int_value();
    let is_eof = builder.build_int_compare(IntPredicate::SLE, bytes_read, i64_type.const_zero(), "is_eof").unwrap();"""

new_read = """    let bytes_read = builder.build_call(read_fn, &[i32_type.const_zero().into(), c_ptr.into(), i64_type.const_int(1, false).into()], "read").unwrap().try_as_basic_value().left().unwrap().into_int_value();
    
    // Отладка: выводим прочитанный байт
    let fmt_char = builder.build_global_string_ptr("[read: %lld] ", "fmt_char").unwrap();
    builder.build_call(printf, &[fmt_char.as_pointer_value().into(), bytes_read.into()], "debug_read").unwrap();
    
    let is_eof = builder.build_int_compare(IntPredicate::SLE, bytes_read, i64_type.const_zero(), "is_eof").unwrap();"""

content = content.replace(old_read, new_read)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста (с отладкой)..."
cd ~/test_ci
xc input_test.x -out input_test
./input_test
