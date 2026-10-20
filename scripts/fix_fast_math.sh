#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление флага --fast-math (через атрибуты LLVM)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Убираем сломанный set_fast_math
content = content.replace(
    "    if fast_math {\n        builder.set_fast_math(true);\n    }\n",
    ""
)

# 2. Убеждаемся, что fast_math объявлен в main()
if 'let mut fast_math = false;' not in content:
    content = content.replace(
        "let mut out_name = None;",
        "let mut out_name = None;\n    let mut fast_math = false;"
    )

# 3. Добавляем парсинг флага --fast-math
if '--fast-math' not in content:
    content = content.replace(
        'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }',
        'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }\n        else if args[i] == "--fast-math" { fast_math = true; i += 1; }'
    )

# 4. Применяем атрибут unsafe-fp-math ко всем функциям, если флаг включен
old_funcs = """    for (_, (llvm_fn, func_decl)) in &user_functions {"""
new_funcs = """    if fast_math {
        let attr = context.create_string_attribute("unsafe-fp-math", "true");
        for (_, (llvm_fn, _)) in &user_functions {
            llvm_fn.add_attribute(inkwell::attributes::AttributeLoc::Function, attr);
        }
    }

    for (_, (llvm_fn, func_decl)) in &user_functions {"""
content = content.replace(old_funcs, new_funcs)

# 5. Убираем возможные дубликаты (если скрипт запускался дважды)
content = content.replace("let mut is_rtos = false;", "")

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск бенчмарка (Ожидается 1-3 мс)..."
mkdir -p ~/benchmark_xlang/t2
cd ~/benchmark_xlang/t2

cat > fast_math.x << 'EOF'
.use GOIO
func main {
    sum = 0;
    for (i = 0; i < 10000000; i = i + 1) {
        sum = sum + i;
    }
    con(sum);
}
EOF

echo "Компиляция с флагом --fast-math..."
xc fast_math.x --fast-math -out fast_math_bin

echo "Замер скорости (3 прогона):"
for i in 1 2 3; do
    START=$(date +%s%N)
    ./fast_math_bin > /dev/null
    END=$(date +%s%N)
    echo "  Прогон $i: $(( (END-START)/1000000 )) мс"
done

echo -e "\nДля сравнения (без флага --fast-math):"
xc fast_math.x -out standard_bin
for i in 1 2 3; do
    START=$(date +%s%N)
    ./standard_bin > /dev/null
    END=$(date +%s%N)
    echo "  Прогон $i: $(( (END-START)/1000000 )) мс"
done
