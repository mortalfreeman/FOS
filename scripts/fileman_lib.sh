#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание библиотеки FILEMAN.xh..."
sudo bash -c 'cat > /usr/local/use/fileman.xh << "EOF"
#Define Header=FILEMAN
! Библиотека для работы с файлами (fopen, fclose, fwrite, fread)
#END
EOF'

echo "==> 2. Добавление встроенных функций файлов в компилятор..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем File в VarInfo
if 'File(PointerValue' not in content:
    content = content.replace(
        "Pointer(PointerValue<'ctx>) \n}",
        "Pointer(PointerValue<'ctx>),\n    File(PointerValue<'ctx>) \n}"
    )

# 2. Добавляем libc-функции в структуру
if 'fopen: FunctionValue' not in content:
    content = content.replace(
        'malloc: FunctionValue<\'ctx>, strlen: FunctionValue<\'ctx>, strcpy: FunctionValue<\'ctx>, strcat: FunctionValue<\'ctx>,',
        'malloc: FunctionValue<\'ctx>, strlen: FunctionValue<\'ctx>, strcpy: FunctionValue<\'ctx>, strcat: FunctionValue<\'ctx>,\n    fopen: FunctionValue<\'ctx>, fclose: FunctionValue<\'ctx>, fwrite: FunctionValue<\'ctx>, fread: FunctionValue<\'ctx>, fseek: FunctionValue<\'ctx>, ftell: FunctionValue<\'ctx>, rewind: FunctionValue<\'ctx>,'
    )

# 3. Объявляем функции
if 'let fopen = module.add_function' not in content:
    content = content.replace(
        'let strcat = module.add_function("strcat",',
        '''let fopen = module.add_function("fopen", i8_ptr_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None);
    let fclose = module.add_function("fclose", i32_type.fn_type(&[i8_ptr_type.into()], false), None);
    let fwrite = module.add_function("fwrite", i64_type.fn_type(&[i8_ptr_type.into(), i64_type.into(), i64_type.into(), i8_ptr_type.into()], false), None);
    let fread = module.add_function("fread", i64_type.fn_type(&[i8_ptr_type.into(), i64_type.into(), i64_type.into(), i8_ptr_type.into()], false), None);
    let fseek = module.add_function("fseek", i32_type.fn_type(&[i8_ptr_type.into(), i64_type.into(), i32_type.into()], false), None);
    let ftell = module.add_function("ftell", i64_type.fn_type(&[i8_ptr_type.into()], false), None);
    let rewind = module.add_function("rewind", context.void_type().fn_type(&[i8_ptr_type.into()], false), None);
    let strcat = module.add_function("strcat",'''
    )

# 4. Инициализируем в Libc
if 'fopen, fclose, fwrite' not in content:
    content = content.replace(
        'malloc, strlen, strcpy, strcat,',
        'malloc, strlen, strcpy, strcat, fopen, fclose, fwrite, fread, fseek, ftell, rewind,'
    )

# 5. Добавляем обработку функций файлов в gen_expr (Call)
if '"file-open"' not in content:
    file_funcs = r'''
                "file-open" => {
                    if args.len() >= 1 {
                        let path_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let path_ptr = match path_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let mode = builder.build_global_string_ptr("r+", "mode").unwrap();
                        let file = builder.build_call(libc.fopen, &[path_ptr.into(), mode.as_pointer_value().into()], "fopen").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                        return file.into();
                    }
                    f64_type.const_float(0.0).into()
                }
                "file-close" => {
                    if args.len() >= 1 {
                        let file_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let file_ptr = match file_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected file") };
                        builder.build_call(libc.fclose, &[file_ptr.into()], "fclose").unwrap();
                    }
                    f64_type.const_float(0.0).into()
                }
                "file-write" => {
                    if args.len() >= 2 {
                        let file_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let file_ptr = match file_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected file") };
                        let text_val = gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars);
                        let text_ptr = match text_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let len = builder.build_call(libc.strlen, &[text_ptr.into()], "len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        builder.build_call(libc.fwrite, &[text_ptr.into(), i64_type.const_int(1, false).into(), len.into(), file_ptr.into()], "fwrite").unwrap();
                    }
                    f64_type.const_float(0.0).into()
                }
                "file-new" => {
                    if args.len() >= 3 {
                        let name_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let name_ptr = match name_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let ext_val = gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars);
                        let ext_ptr = match ext_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let text_val = gen_expr(context, builder, module, &args[2], aliases, user_functions, libc, vars);
                        let text_ptr = match text_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };

                        let dot_str = builder.build_global_string_ptr(".", "dot").unwrap();
                        let name_len = builder.build_call(libc.strlen, &[name_ptr.into()], "name_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        let ext_len = builder.build_call(libc.strlen, &[ext_ptr.into()], "ext_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        let total_len = builder.build_int_add(name_len, ext_len, "total").unwrap();
                        let total_len = builder.build_int_add(total_len, i64_type.const_int(2, false), "total2").unwrap();
                        let full_buf = builder.build_call(libc.malloc, &[total_len.into()], "malloc").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                        
                        builder.build_call(libc.strcpy, &[full_buf.into(), name_ptr.into()], "strcpy").unwrap();
                        builder.build_call(libc.strcat, &[full_buf.into(), dot_str.as_pointer_value().into()], "strcat").unwrap();
                        builder.build_call(libc.strcat, &[full_buf.into(), ext_ptr.into()], "strcat").unwrap();

                        let mode = builder.build_global_string_ptr("w", "mode_w").unwrap();
                        let file = builder.build_call(libc.fopen, &[full_buf.into(), mode.as_pointer_value().into()], "fopen").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();

                        let text_len = builder.build_call(libc.strlen, &[text_ptr.into()], "text_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        builder.build_call(libc.fwrite, &[text_ptr.into(), i64_type.const_int(1, false).into(), text_len.into(), file.into()], "fwrite").unwrap();

                        builder.build_call(libc.fclose, &[file.into()], "fclose").unwrap();
                    }
                    f64_type.const_float(0.0).into()
                }
                "file-read" => {
                    if args.len() >= 2 {
                        let path_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let path_ptr = match path_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };
                        let name_val = gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars);
                        let name_ptr = match name_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected string") };

                        let path_len = builder.build_call(libc.strlen, &[path_ptr.into()], "path_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        let name_len = builder.build_call(libc.strlen, &[name_ptr.into()], "name_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        let total_len = builder.build_int_add(path_len, name_len, "total").unwrap();
                        let total_len = builder.build_int_add(total_len, i64_type.const_int(1, false), "total1").unwrap();
                        let full_buf = builder.build_call(libc.malloc, &[total_len.into()], "malloc").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                        
                        builder.build_call(libc.strcpy, &[full_buf.into(), path_ptr.into()], "strcpy").unwrap();
                        builder.build_call(libc.strcat, &[full_buf.into(), name_ptr.into()], "strcat").unwrap();

                        let mode = builder.build_global_string_ptr("r", "mode_r").unwrap();
                        let file = builder.build_call(libc.fopen, &[full_buf.into(), mode.as_pointer_value().into()], "fopen").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();

                        builder.build_call(libc.fseek, &[file.into(), i64_type.const_int(0, false).into(), i32_type.const_int(2, false).into()], "fseek").unwrap();
                        let size = builder.build_call(libc.ftell, &[file.into()], "ftell").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        builder.build_call(libc.rewind, &[file.into()], "rewind").unwrap();
                        let buf_size = builder.build_int_add(size, i64_type.const_int(1, false), "buf_size").unwrap();
                        let buf = builder.build_call(libc.malloc, &[buf_size.into()], "malloc_buf").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                        builder.build_call(libc.fread, &[buf.into(), i64_type.const_int(1, false).into(), size.into(), file.into()], "fread").unwrap();
                        let end_ptr = unsafe { builder.build_gep(i8_type, buf, &[size], "end_ptr").unwrap() };
                        builder.build_store(end_ptr, i8_type.const_zero()).unwrap();
                        builder.build_call(libc.fclose, &[file.into()], "fclose").unwrap();

                        return buf.into();
                    }
                    f64_type.const_float(0.0).into()
                }
'''
    content = content.replace('                "con" => {', file_funcs + '                "con" => {')

# 6. В Stmt::Assign обрабатываем file-open
if 'VarInfo::File' not in content.split('fn gen_stmt')[0]:
    old_assign = '''                } else if val.is_pointer_value() {
                    let alloca = if let Some(VarInfo::String(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::String(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else {'''
    new_assign = '''                } else if val.is_pointer_value() {
                    if let ast::Expr::Call { name: call_name, .. } = value {
                        if call_name == "file-open" {
                            let alloca = builder.build_alloca(i8_ptr_type, name).unwrap();
                            builder.build_store(alloca, val.into_pointer_value()).unwrap();
                            vars.insert(name.clone(), VarInfo::File(alloca));
                            return;
                        }
                    }
                    let alloca = if let Some(VarInfo::String(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::String(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else {'''
    content = content.replace(old_assign, new_assign)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 4. Тестирование FILEMAN..."
mkdir -p /tmp/fileman_test
cd /tmp/fileman_test

cat > test_file.x << 'XLANG'
.use std
.use fileman

func main {
    con("=== FILEMAN TEST ===");
    
    ! Создаем файл test.txt с текстом !
    file-new("test", "txt", "Hello, FILEMAN!\nThis is a new line.");
    con("File 'test.txt' created.");
    
    ! Читаем его обратно !
    content = file-read("./", "test.txt");
    con("Content read from file:");
    con(content);
    
    ! Открываем для записи и дописываем !
    f = file-open("test.txt");
    file-write(f, "\nAppended line.");
    file-close(f);
    con("Appended text.");
    
    ! Читаем снова !
    content2 = file-read("./", "test.txt");
    con("Updated content:");
    con(content2);
}
XLANG

xc test_file.x -out test_file
./test_file

echo ""
echo "=== Содержимое test.txt ==="
cat test.txt
