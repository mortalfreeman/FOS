#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Исправление парсинга --fast-math и атрибутов..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Удаляем старые кривые вставки
content = content.replace("let mut fast_math = false;", "")
content = content.replace("if fast_math {\n        let attr = context.create_string_attribute(\"unsafe-fp-math\", \"true\");\n        for (_, (llvm_fn, _)) in &user_functions {\n            llvm_fn.add_attribute(inkwell::attributes::AttributeLoc::Function, attr);\n        }\n    }\n", "")

# Вставляем корректно
content = content.replace(
    "let mut out_name = None;",
    "let mut out_name = None;\n    let mut fast_math = false;"
)

if 'args[i] == "--fast-math"' not in content:
    content = content.replace(
        'if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }',
        'if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }\n        else if args[i] == "--fast-math" { fast_math = true; i += 1; }'
    )

# Применяем атрибут ПОСЛЕ того, как user_functions заполнен
old_functions_loop = """    for item in &global_program.items {
        if let ast::Item::Func(func) = item {
            let fn_type = f64_type.fn_type(&vec![f64_type.into(); func.args.len()], false);
            user_functions.insert(func.name.clone(), (module.add_function(&func.name, fn_type, None), func.clone()));
        }
    }"""
new_functions_loop = old_functions_loop + """

    if fast_math {
        let attr = context.create_string_attribute("unsafe-fp-math", "true");
        for (_, (llvm_fn, _)) in &user_functions {
            llvm_fn.add_attribute(inkwell::attributes::AttributeLoc::Function, attr);
        }
    }"""
content = content.replace(old_functions_loop, new_functions_loop)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Создание изолированных тестов..."
mkdir -p ~/test_crash
cd ~/test_crash

cat > t_con.x << 'XLANG'
func main {
    x = 42;
    con(x);
}
XLANG

cat > t_loop.x << 'XLANG'
func main {
    sum = 0;
    for (i = 0; i < 10000000; i = i + 1) {
        sum = sum + i;
    }
    con(sum);
}
XLANG

echo "--- Тест 1: con(x) (Проверка вывода числа) ---"
xc t_con.x -out t_con_bin
./t_con_bin || echo "ОШИБКА: код $?"

echo -e "\n--- Тест 2: Цикл без fast-math ---"
xc t_loop.x -out t_loop_bin
START=$(date +%s%N)
./t_loop_bin || echo "ОШИБКА: код $?"
END=$(date +%s%N)
echo "Время: $(( (END-START)/1000000 )) мс"

echo -e "\n--- Тест 3: Цикл с fast-math ---"
xc t_loop.x --fast-math -out t_loop_fast
START=$(date +%s%N)
./t_loop_fast || echo "ОШИБКА: код $?"
END=$(date +%s%N)
echo "Время: $(( (END-START)/1000000 )) мс"
