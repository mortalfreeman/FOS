#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление exit(0) и исправление fast-math для main..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Объявляем exit в libc (если ещё не объявлен)
if 'exit: FunctionValue' not in content:
    content = content.replace(
        'malloc: FunctionValue<\'ctx>,',
        'exit: FunctionValue<\'ctx>,\n        malloc: FunctionValue<\'ctx>,'
    )
    content = content.replace(
        'malloc: module.add_function("malloc", i8_ptr_type.fn_type(&[i64_type.into()], false), None),',
        'exit: module.add_function("exit", context.void_type().fn_type(&[i32_type.into()], false), None),\n        malloc: module.add_function("malloc", i8_ptr_type.fn_type(&[i64_type.into()], false), None),'
    )

# 2. В генерации main-функции (системной) добавляем вызов exit(0)
old_main_gen = """    let main_fn = module.add_function("main", i32_type.fn_type(&[], false), None);
    builder.position_at_end(context.append_basic_block(main_fn, "entry"));
    if let Some((llvm_user_main, _)) = user_functions.get("main") {
        builder.build_call(*llvm_user_main, &[], "call_main").unwrap();
    }
    builder.build_return(Some(&i32_type.const_int(0, false))).unwrap();"""

new_main_gen = """    let main_fn = module.add_function("main", i32_type.fn_type(&[], false), None);
    builder.position_at_end(context.append_basic_block(main_fn, "entry"));
    
    // Применяем fast-math к main, если нужно
    if fast_math {
        let attr = context.create_string_attribute("unsafe-fp-math", "true");
        main_fn.add_attribute(inkwell::attributes::AttributeLoc::Function, attr);
    }

    if let Some((llvm_user_main, _)) = user_functions.get("main") {
        builder.build_call(*llvm_user_main, &[], "call_main").unwrap();
    }
    
    // Явно вызываем exit(0), чтобы программа завершилась корректно
    builder.build_call(libc.exit, &[i32_type.const_int(0, false).into()], "call_exit").unwrap();
    builder.build_unreachable().unwrap();"""

content = content.replace(old_main_gen, new_main_gen)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Запуск изолированных тестов..."
cd ~/test_crash

echo "--- Тест 1: con(x) ---"
xc t_con.x -out t_con_bin
./t_con_bin
echo "Код возврата: $?"

echo -e "\n--- Тест 2: Цикл (без fast-math) ---"
xc t_loop.x -out t_loop_bin
START=$(date +%s%N)
./t_loop_bin
END=$(date +%s%N)
echo "Код возврата: $?"
echo "Время: $(( (END-START)/1000000 )) мс"

echo -e "\n--- Тест 3: Цикл (с fast-math) ---"
xc t_loop.x --fast-math -out t_loop_fast
START=$(date +%s%N)
./t_loop_fast
END=$(date +%s%N)
echo "Код возврата: $?"
echo "Время: $(( (END-START)/1000000 )) мс"
