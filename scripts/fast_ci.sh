#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление быстрого std_read_line и умного ci (UTF-8)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем поля в Libc
content = content.replace(
    'std_print_num: FunctionValue<\'ctx>, std_print_int: FunctionValue<\'ctx>,',
    'std_print_num: FunctionValue<\'ctx>, std_print_int: FunctionValue<\'ctx>,\n    std_read_line: FunctionValue<\'ctx>, std_in_buf: PointerValue<\'ctx>, read: FunctionValue<\'ctx>, strtoll: FunctionValue<\'ctx>, strtod: FunctionValue<\'ctx>,'
)

# 2. Объявляем функции
content = content.replace(
    'let std_print_int = module.add_function("std_print_int", context.void_type().fn_type(&[i64_type.into()], false), None);',
    '''let std_print_int = module.add_function("std_print_int", context.void_type().fn_type(&[i64_type.into()], false), None);
    let read_fn = module.add_function("read", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None);
    let strtoll = module.add_function("strtoll", i64_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into(), i32_type.into()], false), None);
    let strtod = module.add_function("strtod", f64_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None);
    let std_read_line = module.add_function("std_read_line", i64_type.fn_type(&[], false), None);
    let std_in_buf = module.add_global(i8_type.array_type(4096), None, "std_in_buf");
    std_in_buf.set_initializer(&i8_type.const_array(&[i8_type.const_zero(); 4096]));'''
)

# 3. Генерируем тело std_read_line
std_read_line_gen = """
    // Генерация std_read_line
    let bb = context.append_basic_block(std_read_line, "entry");
    builder.position_at_end(bb);
    let i_alloca = builder.build_alloca(i64_type, "i").unwrap();
    builder.build_store(i_alloca, i64_type.const_zero()).unwrap();
    let c_alloca = builder.build_alloca(i8_type, "c").unwrap();
    
    let loop_bb = context.append_basic_block(std_read_line, "loop");
    let end_bb = context.append_basic_block(std_read_line, "end");
    builder.build_unconditional_branch(loop_bb).unwrap();
    
    builder.position_at_end(loop_bb);
    let i_val = builder.build_load(i64_type, i_alloca, "i_val").unwrap().into_int_value();
    let is_max = builder.build_int_compare(IntPredicate::SGE, i_val, i64_type.const_int(4095, false), "is_max").unwrap();
    let read_bb = context.append_basic_block(std_read_line, "read");
    builder.build_conditional_branch(is_max, end_bb, read_bb).unwrap();
    
    builder.position_at_end(read_bb);
    let c_ptr = builder.build_pointer_cast(c_alloca, i8_ptr_type, "c_ptr").unwrap();
    let bytes_read = builder.build_call(read_fn, &[i32_type.const_zero().into(), c_ptr.into(), i64_type.const_int(1, false).into()], "read").unwrap().try_as_basic_value().left().unwrap().into_int_value();
    let is_eof = builder.build_int_compare(IntPredicate::SLE, bytes_read, i64_type.const_zero(), "is_eof").unwrap();
    let check_nl_bb = context.append_basic_block(std_read_line, "check_nl");
    builder.build_conditional_branch(is_eof, end_bb, check_nl_bb).unwrap();
    
    builder.position_at_end(check_nl_bb);
    let c_val = builder.build_load(i8_type, c_alloca, "c_val").unwrap().into_int_value();
    let is_nl = builder.build_int_compare(IntPredicate::EQ, c_val, i8_type.const_int(b'\\n' as u64, false), "is_nl").unwrap();
    let store_bb = context.append_basic_block(std_read_line, "store");
    builder.build_conditional_branch(is_nl, end_bb, store_bb).unwrap();
    
    builder.position_at_end(store_bb);
    let gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_in_buf.as_pointer_value(), &[i64_type.const_zero(), i_val], "gep").unwrap() };
    builder.build_store(gep, c_val).unwrap();
    let new_i = builder.build_int_add(i_val, i64_type.const_int(1, false), "new_i").unwrap();
    builder.build_store(i_alloca, new_i).unwrap();
    builder.build_unconditional_branch(loop_bb).unwrap();
    
    builder.position_at_end(end_bb);
    let final_i = builder.build_load(i64_type, i_alloca, "final_i").unwrap().into_int_value();
    let final_gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_in_buf.as_pointer_value(), &[i64_type.const_zero(), final_i], "final_gep").unwrap() };
    builder.build_store(final_gep, i8_type.const_zero()).unwrap();
    builder.build_return(Some(&final_i)).unwrap();
"""
content = content.replace(
    'let libc = Libc { printf, scanf, sprintf, pow, sin, cos, round, floor, ceil, malloc, strlen, strcpy, strcat, sys_write, std_flush, std_print_str, std_print_num, std_print_int };',
    std_read_line_gen + '\n    let libc = Libc { printf, scanf, sprintf, pow, sin, cos, round, floor, ceil, malloc, strlen, strcpy, strcat, sys_write, std_flush, std_print_str, std_print_num, std_print_int, std_read_line, std_in_buf: std_in_buf.as_pointer_value(), read: read_fn, strtoll, strtod };'
)

# 4. Переписываем "ci" в gen_expr
old_ci = '''                "ci" => {
                    if args.len() >= 2 {
                        if let ast::Expr::String(prompt) = &args[0] {
                            let fmt_global = builder.build_global_string_ptr(prompt.as_str(), "prompt").unwrap();
                            builder.build_call(libc.printf, &[fmt_global.as_pointer_value().into()], "call_ci_prompt").unwrap();
                        }
                        if let ast::Expr::Identifier(var_name) = &args[1] {
                            let is_string = if let Some(VarInfo::String(_)) = vars.get(var_name.as_str()) { true } else { false };
                            if is_string {
                                let buf_size = i64_type.const_int(1024, false);
                                let buf = builder.build_call(libc.malloc, &[buf_size.into()], "str_buf").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                                let scanf_fmt = builder.build_global_string_ptr("%s", "scanf_str").unwrap();
                                builder.build_call(libc.scanf, &[scanf_fmt.as_pointer_value().into(), buf.into()], "call_ci_scan").unwrap();
                                let alloca = builder.build_alloca(i8_ptr_type, var_name).unwrap();
                                builder.build_store(alloca, buf).unwrap();
                                vars.insert(var_name.clone(), VarInfo::String(alloca));
                            } else {
                                let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(var_name.as_str()) { *ptr } 
                                             else { let ptr = builder.build_alloca(f64_type, var_name).unwrap(); vars.insert(var_name.clone(), VarInfo::Scalar(ptr)); ptr };
                                let scanf_fmt = builder.build_global_string_ptr("%lf", "scanf_fmt").unwrap();
                                builder.build_call(libc.scanf, &[scanf_fmt.as_pointer_value().into(), alloca.into()], "call_ci_scan").unwrap();
                            }
                        }
                    }
                    f64_type.const_float(0.0).into()
                }'''

new_ci = '''                "ci" => {
                    if args.len() >= 2 {
                        if let ast::Expr::String(prompt) = &args[0] {
                            let fmt_global = builder.build_global_string_ptr(prompt.as_str(), "prompt").unwrap();
                            builder.build_call(libc.std_print_str, &[fmt_global.as_pointer_value().into()], "print_prompt").unwrap();
                            builder.build_call(libc.std_flush, &[], "flush_prompt").unwrap();
                        }
                        if let ast::Expr::Identifier(var_name) = &args[1] {
                            let len = builder.build_call(libc.std_read_line, &[], "read_line").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                            
                            let is_string = if let Some(VarInfo::String(_)) = vars.get(var_name.as_str()) { true } else { false };
                            let is_int = if let Some(VarInfo::Int(_)) = vars.get(var_name.as_str()) { true } else { false };
                            
                            let in_buf_ptr = builder.build_pointer_cast(libc.std_in_buf, i8_ptr_type, "in_buf_ptr").unwrap();
                            
                            if is_string || !is_int && !vars.contains_key(var_name.as_str()) {
                                let total_len = builder.build_int_add(len, i64_type.const_int(1, false), "total").unwrap();
                                let malloc_ptr = builder.build_call(libc.malloc, &[total_len.into()], "malloc").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                                builder.build_call(libc.strcpy, &[malloc_ptr.into(), in_buf_ptr.into()], "strcpy").unwrap();
                                let alloca = builder.build_alloca(i8_ptr_type, var_name).unwrap();
                                builder.build_store(alloca, malloc_ptr).unwrap();
                                vars.insert(var_name.clone(), VarInfo::String(alloca));
                            } else if is_int {
                                let null_ptr = i8_ptr_type.const_null();
                                let int_val = builder.build_call(libc.strtoll, &[in_buf_ptr.into(), null_ptr.into(), i32_type.const_int(10, false).into()], "strtoll").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                                let alloca = if let Some(VarInfo::Int(ptr)) = vars.get(var_name.as_str()) { *ptr } 
                                             else { let ptr = builder.build_alloca(i64_type, var_name).unwrap(); vars.insert(var_name.clone(), VarInfo::Int(ptr)); ptr };
                                builder.build_store(alloca, int_val).unwrap();
                            } else {
                                let null_ptr = i8_ptr_type.const_null();
                                let f_val = builder.build_call(libc.strtod, &[in_buf_ptr.into(), null_ptr.into()], "strtod").unwrap().try_as_basic_value().left().unwrap().into_float_value();
                                let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(var_name.as_str()) { *ptr } 
                                             else { let ptr = builder.build_alloca(f64_type, var_name).unwrap(); vars.insert(var_name.clone(), VarInfo::Scalar(ptr)); ptr };
                                builder.build_store(alloca, f_val).unwrap();
                            }
                        }
                    }
                    f64_type.const_float(0.0).into()
                }'''
content = content.replace(old_ci, new_ci)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест ввода (UTF-8, строки, числа)..."
mkdir -p ~/test_ci
cd ~/test_ci

cat > input_test.x << 'XLANG'
.use std

func main {
    con("Введите ваше имя (с пробелами): ");
    name = "";
    ci("", name);
    con("Привет, ", name, "!");

    con("Введите целое число: ");
    x = 0;
    ci("", x);
    con("Вы ввели (int): ", x);

    con("Введите дробное число: ");
    y = 0.0;
    ci("", y);
    con("Вы ввели (float): ", y);
}
XLANG

xc input_test.x -out input_test
./input_test
