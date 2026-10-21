#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление индексации (IntValue для GEP)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Исправляем Index в gen_expr (чтение)
old_index = '''        ast::Expr::Index { name, index } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_val = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars).into_float_value();
            let idx_int = builder.build_float_to_signed_int(idx_val, i32_type, "idx").unwrap();
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_load(f64_type, ptr, "load_arr").unwrap()
        }'''
new_index = '''        ast::Expr::Index { name, index } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_raw = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars);
            let idx_int = match idx_raw {
                BasicValueEnum::IntValue(i) => builder.build_int_truncate(i, i32_type, "idx_trunc").unwrap(),
                BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i32_type, "idx_float").unwrap(),
                _ => panic!("Invalid index type"),
            };
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_load(f64_type, ptr, "load_arr").unwrap()
        }'''
content = content.replace(old_index, new_index)

# 2. Исправляем IndexAssign в gen_stmt (запись)
old_index_assign = '''        ast::Stmt::IndexAssign { name, index, value } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_val = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars).into_float_value();
            let idx_int = builder.build_float_to_signed_int(idx_val, i32_type, "idx").unwrap();
            let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars).into_float_value();
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_store(ptr, val).unwrap();
        }'''
new_index_assign = '''        ast::Stmt::IndexAssign { name, index, value } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_raw = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars);
            let idx_int = match idx_raw {
                BasicValueEnum::IntValue(i) => builder.build_int_truncate(i, i32_type, "idx_trunc").unwrap(),
                BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i32_type, "idx_float").unwrap(),
                _ => panic!("Invalid index type"),
            };
            let val_raw = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
            let val = to_float(builder, val_raw, f64_type);
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_store(ptr, val).unwrap();
        }'''
content = content.replace(old_index_assign, new_index_assign)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск оставшихся тестов (7-15)..."
bash /tmp/finish_all_tests.sh
