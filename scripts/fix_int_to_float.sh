#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление безопасной конвертации IntValue -> FloatValue..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Вставляем вспомогательную функцию для конвертации
helper = """
fn to_float<'ctx>(builder: &Builder<'ctx>, val: BasicValueEnum<'ctx>, f64_type: inkwell::types::FloatType<'ctx>) -> inkwell::values::FloatValue<'ctx> {
    match val {
        BasicValueEnum::FloatValue(f) => f,
        BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "int_to_float").unwrap(),
        _ => panic!("Cannot convert to float"),
    }
}
"""
if 'fn to_float' not in content:
    content = content.replace('fn resolve_project_files', helper + '\nfn resolve_project_files')

# 2. В IndexAssign: заменяем into_float_value() на to_float()
content = content.replace(
    'let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars).into_float_value();\n            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };\n            builder.build_store(ptr, val).unwrap();',
    'let val_raw = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);\n            let val = to_float(builder, val_raw, f64_type);\n            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };\n            builder.build_store(ptr, val).unwrap();'
)

# 3. В создании массива (Array literal)
content = content.replace(
    'let val = gen_expr(context, builder, module, elem, aliases, user_functions, libc, vars).into_float_value();\n                    let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };',
    'let val_raw = gen_expr(context, builder, module, elem, aliases, user_functions, libc, vars);\n                    let val = to_float(builder, val_raw, f64_type);\n                    let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };'
)

# 4. В Return: заменяем into_float_value()
content = content.replace(
    'ast::Stmt::Return { value } => {\n            let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars).into_float_value();\n            builder.build_return(Some(&val)).unwrap();\n        }',
    'ast::Stmt::Return { value } => {\n            let val_raw = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);\n            let val = to_float(builder, val_raw, f64_type);\n            builder.build_return(Some(&val)).unwrap();\n        }'
)

# 5. В функции Call (передача аргументов)
content = content.replace(
    'let f_val = match val { BasicValueEnum::FloatValue(f) => f, BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(), _ => f64_type.const_float(0.0) };',
    'let f_val = to_float(builder, val, f64_type);'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск оставшихся тестов (7-15)..."
bash /tmp/finish_all_tests.sh
