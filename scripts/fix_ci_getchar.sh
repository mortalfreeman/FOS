#!/bin/bash
set -e
cd ~/FOS

echo "==> Замена std_read_line на getchar..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Убираем read из Libc
content = content.replace('read: FunctionValue<\'ctx>, ', '')

# 2. Добавляем getchar в Libc
content = content.replace(
    'let read_fn = module.add_function("read", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None);',
    'let getchar = module.add_function("getchar", i32_type.fn_type(&[], false), None);'
)

# 3. Переписываем тело std_read_line
old_read_line_start = '    // Генерация std_read_line'
old_read_line_end = '    let libc = Libc {'
start_idx = content.find(old_read_line_start)
end_idx = content.find(old_read_line_end)

if start_idx != -1 and end_idx != -1:
    new_read_line = '''    // Генерация std_read_line (через getchar)
    let bb = context.append_basic_block(std_read_line, "entry");
    builder.position_at_end(bb);
    let i_alloca = builder.build_alloca(i64_type, "i").unwrap();
    builder.build_store(i_alloca, i64_type.const_zero()).unwrap();
    
    let loop_bb = context.append_basic_block(std_read_line, "loop");
    let end_bb = context.append_basic_block(std_read_line, "end");
    builder.build_unconditional_branch(loop_bb).unwrap();
    
    builder.position_at_end(loop_bb);
    let i_val = builder.build_load(i64_type, i_alloca, "i_val").unwrap().into_int_value();
    let is_max = builder.build_int_compare(IntPredicate::SGE, i_val, i64_type.const_int(4095, false), "is_max").unwrap();
    let read_bb = context.append_basic_block(std_read_line, "read");
    builder.build_conditional_branch(is_max, end_bb, read_bb).unwrap();
    
    builder.position_at_end(read_bb);
    let c_int = builder.build_call(getchar, &[], "getchar").unwrap().try_as_basic_value().left().unwrap().into_int_value();
    let is_eof = builder.build_int_compare(IntPredicate::SLT, c_int, i32_type.const_int(0, false), "is_eof").unwrap();
    let check_nl_bb = context.append_basic_block(std_read_line, "check_nl");
    builder.build_conditional_branch(is_eof, end_bb, check_nl_bb).unwrap();
    
    builder.position_at_end(check_nl_bb);
    let is_nl = builder.build_int_compare(IntPredicate::EQ, c_int, i32_type.const_int(10, false), "is_nl").unwrap();
    let store_bb = context.append_basic_block(std_read_line, "store");
    builder.build_conditional_branch(is_nl, end_bb, store_bb).unwrap();
    
    builder.position_at_end(store_bb);
    let c_byte = builder.build_int_truncate(c_int, i8_type, "c_byte").unwrap();
    let gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_in_buf.as_pointer_value(), &[i64_type.const_zero(), i_val], "gep").unwrap() };
    builder.build_store(gep, c_byte).unwrap();
    let new_i = builder.build_int_add(i_val, i64_type.const_int(1, false), "new_i").unwrap();
    builder.build_store(i_alloca, new_i).unwrap();
    builder.build_unconditional_branch(loop_bb).unwrap();
    
    builder.position_at_end(end_bb);
    let final_i = builder.build_load(i64_type, i_alloca, "final_i").unwrap().into_int_value();
    let final_gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_in_buf.as_pointer_value(), &[i64_type.const_zero(), final_i], "final_gep").unwrap() };
    builder.build_store(final_gep, i8_type.const_zero()).unwrap();
    builder.build_return(Some(&final_i)).unwrap();
    
'''
    content = content[:start_idx] + new_read_line + content[end_idx:]

# 4. Обновляем структуру Libc (добавляем getchar вместо read)
content = content.replace(
    'std_read_line: FunctionValue<\'ctx>, std_in_buf: PointerValue<\'ctx>, read: FunctionValue<\'ctx>, strtoll: FunctionValue<\'ctx>, strtod: FunctionValue<\'ctx>,',
    'std_read_line: FunctionValue<\'ctx>, std_in_buf: PointerValue<\'ctx>, getchar: FunctionValue<\'ctx>, strtoll: FunctionValue<\'ctx>, strtod: FunctionValue<\'ctx>,'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста (getchar)..."
cd ~/test_ci
xc input_test.x -out input_test
./input_test
