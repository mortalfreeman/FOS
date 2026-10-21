#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление проверки NULL в file-open..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

old_open = '''                "file-open" => {
                    if args.len() >= 1 {
                        let path_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let path_ptr = match path_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let mode = builder.build_global_string_ptr("a+", "mode").unwrap();
                        let file = builder.build_call(libc.fopen, &[path_ptr.into(), mode.as_pointer_value().into()], "fopen").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                        return file.into();
                    }
                    f64_type.const_float(0.0).into()
                }'''

new_open = '''                "file-open" => {
                    if args.len() >= 1 {
                        let path_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let path_ptr = match path_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let mode = builder.build_global_string_ptr("a+", "mode").unwrap();
                        let file = builder.build_call(libc.fopen, &[path_ptr.into(), mode.as_pointer_value().into()], "fopen").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                        
                        // Проверка на NULL
                        let is_null = builder.build_is_null(file, "is_null").unwrap();
                        let ok_bb = context.append_basic_block(context.get_insert_block().unwrap().get_parent().unwrap(), "file_ok");
                        let err_bb = context.append_basic_block(context.get_insert_block().unwrap().get_parent().unwrap(), "file_err");
                        builder.build_conditional_branch(is_null, err_bb, ok_bb).unwrap();
                        
                        builder.position_at_end(err_bb);
                        let err_msg = builder.build_global_string_ptr("Error: cannot open file!\\n", "err_msg").unwrap();
                        builder.build_call(libc.printf, &[err_msg.as_pointer_value().into()], "print_err").unwrap();
                        builder.build_call(libc.std_flush, &[], "flush").unwrap();
                        builder.build_unreachable().unwrap();
                        
                        builder.position_at_end(ok_bb);
                        return file.into();
                    }
                    f64_type.const_float(0.0).into()
                }'''

content = content.replace(old_open, new_open)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста (с проверкой)..."
rm -f /tmp/writeX.test.log
xc /tmp/writeX.x -out /tmp/writeX
START=$(date +%s%N)
/tmp/writeX
END=$(date +%s%N)
echo "X-lang время: $(( (END-START)/1000000 )) мс"
echo "Размер файла: $(stat -c%s /tmp/writeX.test.log 2>/dev/null || echo 0) байт"
head -5 /tmp/writeX.test.log 2>/dev/null || echo "Файл не создан"
