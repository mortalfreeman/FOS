#!/bin/bash
cd ~/FOS

echo "==> Исправление флага --fast-math..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Убеждаемся, что переменная fast_math объявлена как mut
content = content.replace("let fast_math = false;", "let mut fast_math = false;")

# 2. Вставляем парсинг флага в цикл while (находим начало разбора аргументов)
if 'args[i] == "--fast-math"' not in content:
    # Ищем любой блок, где обрабатывается -out
    content = content.replace(
        'if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }',
        'if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }\n        else if args[i] == "--fast-math" { fast_math = true; i += 1; }'
    )
    # Если и это не сработало, ищем else if args[i] == "-out"
    if 'args[i] == "--fast-math"' not in content:
        content = content.replace(
            'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }',
            'else if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }\n        else if args[i] == "--fast-math" { fast_math = true; i += 1; }'
        )

# 3. Применение атрибута unsafe-fp-math
if 'unsafe-fp-math' not in content:
    content = content.replace(
        "    let mut user_functions = std::collections::HashMap::new();",
        """    if fast_math {
        let attr = context.create_string_attribute("unsafe-fp-math", "true");
        for (_, (llvm_fn, _)) in &user_functions {
            llvm_fn.add_attribute(inkwell::attributes::AttributeLoc::Function, attr);
        }
    }

    let mut user_functions = std::collections::HashMap::new();"""
    )

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler 2>/dev/null || cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
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

echo "--- Компиляция с --fast-math ---"
xc fast_math.x --fast-math -out fast_math_bin

echo "--- Замер (3 прогона) ---"
for i in 1 2 3; do
    START=$(date +%s%N)
    ./fast_math_bin > /dev/null
    RET=$?
    END=$(date +%s%N)
    if [ $RET -ne 0 ]; then
        echo "  Прогон $i: ОШИБКА (код $RET)"
    else
        echo "  Прогон $i: $(( (END-START)/1000000 )) мс"
    fi
done

echo -e "\n--- Компиляция без флага ---"
xc fast_math.x -out standard_bin
for i in 1 2 3; do
    START=$(date +%s%N)
    ./standard_bin > /dev/null
    RET=$?
    END=$(date +%s%N)
    if [ $RET -ne 0 ]; then
        echo "  Прогон $i: ОШИБКА (код $RET)"
    else
        echo "  Прогон $i: $(( (END-START)/1000000 )) мс"
    fi
done
