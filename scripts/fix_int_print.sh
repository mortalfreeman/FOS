#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление std_print_int для вывода целых чисел..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем поле в структуру Libc
content = content.replace(
    'std_print_num: FunctionValue<\'ctx>,',
    'std_print_num: FunctionValue<\'ctx>, std_print_int: FunctionValue<\'ctx>,'
)

# 2. Объявляем функцию std_print_int
content = content.replace(
    'let std_print_num = module.add_function("std_print_num", context.void_type().fn_type(&[f64_type.into()], false), None);',
    'let std_print_num = module.add_function("std_print_num", context.void_type().fn_type(&[f64_type.into()], false), None);\n    let std_print_int = module.add_function("std_print_int", context.void_type().fn_type(&[i64_type.into()], false), None);'
)

# 3. Генерируем тело std_print_int (используем %lld)
std_print_int_gen = """
    // Генерация std_print_int
    let bb = context.append_basic_block(std_print_int, "entry");
    builder.position_at_end(bb);
    let num_val = std_print_int.get_nth_param(0).unwrap().into_int_value();
    let temp_buf = builder.build_alloca(i8_type.array_type(64), "tmp_buf").unwrap();
    let fmt = builder.build_global_string_ptr("%lld", "fmt_int").unwrap();
    let buf_cast = builder.build_pointer_cast(temp_buf, i8_ptr_type, "buf_cast").unwrap();
    builder.build_call(sprintf, &[buf_cast.into(), fmt.as_pointer_value().into(), num_val.into()], "sprintf").unwrap();
    builder.build_call(std_print_str, &[buf_cast.into()], "print_str").unwrap();
    builder.build_return(None).unwrap();
"""
content = content.replace(
    'let libc = Libc { printf, scanf, sprintf, pow, sin, cos, round, floor, ceil, malloc, strlen, strcpy, strcat, sys_write, std_flush, std_print_str, std_print_num };',
    std_print_int_gen + '\n    let libc = Libc { printf, scanf, sprintf, pow, sin, cos, round, floor, ceil, malloc, strlen, strcpy, strcat, sys_write, std_flush, std_print_str, std_print_num, std_print_int };'
)

# 4. В gen_expr (для con) используем std_print_int для целых чисел
old_con = """                                } else if val.is_int_value() {
                                    let f = builder.build_signed_int_to_float(val.into_int_value(), f64_type, "tmp").unwrap();
                                    builder.build_call(libc.std_print_num, &[f.into()], "print_num").unwrap();
                                } else {"""
new_con = """                                } else if val.is_int_value() {
                                    builder.build_call(libc.std_print_int, &[val.into()], "print_int").unwrap();
                                } else {"""
content = content.replace(old_con, new_con)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест вывода (целые числа)..."
cd ~/test_std
xc fast_io.x -out fast_io
./fast_io | head -n 5
