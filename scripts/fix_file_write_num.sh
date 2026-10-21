#!/bin/bash
set -e
cd ~/FOS

echo "==> Замена file-write-num на fprintf..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем fprintf в Libc
if 'fprintf' not in content:
    content = content.replace(
        'fopen: FunctionValue<\'ctx>, fclose: FunctionValue<\'ctx>, fwrite: FunctionValue<\'ctx>,',
        'fopen: FunctionValue<\'ctx>, fclose: FunctionValue<\'ctx>, fwrite: FunctionValue<\'ctx>, fprintf: FunctionValue<\'ctx>,'
    )
    content = content.replace(
        'let fwrite = module.add_function("fwrite", i64_type.fn_type(&[i8_ptr_type.into(), i64_type.into(), i64_type.into(), i8_ptr_type.into()], false), None);',
        'let fwrite = module.add_function("fwrite", i64_type.fn_type(&[i8_ptr_type.into(), i64_type.into(), i64_type.into(), i8_ptr_type.into()], false), None);\n    let fprintf = module.add_function("fprintf", i32_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], true), None);'
    )
    content = content.replace(
        'malloc, strlen, strcpy, strcat, fopen, fclose, fwrite,',
        'malloc, strlen, strcpy, strcat, fopen, fclose, fwrite, fprintf,'
    )

# 2. Заменяем реализацию file-write-num
old_write_num = '''                "file-write-num" => {
                    if args.len() >= 2 {
                        let file_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let file_ptr = match file_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected file") };
                        let num_raw = gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars);
                        let num_i = to_int(builder, num_raw, i64_type);
                        
                        let temp_buf = builder.build_alloca(i8_type.array_type(32), "tmp_num").unwrap();
                        let buf_cast = builder.build_pointer_cast(temp_buf, i8_ptr_type, "cast").unwrap();
                        let fmt = builder.build_global_string_ptr("%lld\\n", "fmt_num").unwrap();
                        builder.build_call(libc.sprintf, &[buf_cast.into(), fmt.as_pointer_value().into(), num_i.into()], "sprintf").unwrap();
                        let len = builder.build_call(libc.strlen, &[buf_cast.into()], "len_num").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        builder.build_call(libc.fwrite, &[buf_cast.into(), i64_type.const_int(1, false).into(), len.into(), file_ptr.into()], "fwrite").unwrap();
                    }
                    f64_type.const_float(0.0).into()
                }'''

new_write_num = '''                "file-write-num" => {
                    if args.len() >= 2 {
                        let file_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let file_ptr = match file_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected file") };
                        let num_raw = gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars);
                        let num_i = to_int(builder, num_raw, i64_type);
                        
                        let fmt = builder.build_global_string_ptr("%lld\\n", "fmt_num").unwrap();
                        builder.build_call(libc.fprintf, &[file_ptr.into(), fmt.as_pointer_value().into(), num_i.into()], "fprintf").unwrap();
                    }
                    f64_type.const_float(0.0).into()
                }'''

content = content.replace(old_write_num, new_write_num)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
rm -f /tmp/writeX.test.log
xc /tmp/writeX.x -out /tmp/writeX
START=$(date +%s%N)
/tmp/writeX
END=$(date +%s%N)
echo "X-lang время: $(( (END-START)/1000000 )) мс"
echo "Размер файла: $(stat -c%s /tmp/writeX.test.log 2>/dev/null || echo 0) байт"
head -5 /tmp/writeX.test.log 2>/dev/null || echo "Файл не создан"
