#!/bin/bash
cd ~/FOS

echo "==> Возврат стандартного ret i32 0 из main..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

old_main = """    if let Some((llvm_user_main, _)) = user_functions.get("main") {
        builder.build_call(*llvm_user_main, &[], "call_main").unwrap();
    }
    
    // Явно вызываем exit(0), чтобы программа завершилась корректно
    builder.build_call(libc.exit, &[i32_type.const_int(0, false).into()], "call_exit").unwrap();
    builder.build_unreachable().unwrap();"""

new_main = """    if let Some((llvm_user_main, _)) = user_functions.get("main") {
        builder.build_call(*llvm_user_main, &[], "call_main").unwrap();
    }
    
    // Просто возвращаем 0 (стандартное завершение)
    builder.build_return(Some(&i32_type.const_int(0, false))).unwrap();"""

content = content.replace(old_main, new_main)
with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тестирование (без set -e)..."
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
