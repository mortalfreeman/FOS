#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление флага --fast-math в main.rs..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Парсинг флага
content = content.replace(
    "let mut is_rtos = false;",
    "let mut is_rtos = false;\n    let mut fast_math = false;"
)
content = content.replace(
    "else if args[i] == \"--rtos\" { is_rtos = true; i += 1; }",
    "else if args[i] == \"--rtos\" { is_rtos = true; i += 1; }\n        else if args[i] == \"--fast-math\" { fast_math = true; i += 1; }"
)

# 2. Применение fast-math к builder
content = content.replace(
    "let builder = context.create_builder();",
    "let builder = context.create_builder();\n    if fast_math {\n        builder.set_fast_math_flags(inkwell::builder::FastMathFlags::all());\n    }"
)

# На случай, если в inkwell 0.6 нет FastMathFlags::all(), используем set_fast_math(true)
# Но давай попробуем сначала правильный вариант с флагами.

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Пересборка компилятора..."
# В inkwell 0.6 может не быть метода set_fast_math_flags на Builder, 
# тогда компилятор ругнется, и мы применим фоллбек.
cargo build --release -p xlang-compiler 2>/dev/null || {
    echo "⚠️ Ошибка компиляции (возможно, API inkwell отличается). Применяем фоллбек..."
    python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

content = content.replace(
    "if fast_math {\n        builder.set_fast_math_flags(inkwell::builder::FastMathFlags::all());\n    }",
    "if fast_math {\n        builder.set_fast_math(true);\n    }"
)
with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF
    cargo build --release -p xlang-compiler
}
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Тест с --fast-math (Ожидается 1-3 мс)..."
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

echo "Замер скорости выполнения (3 прогона):"
for i in 1 2 3; do
    START=$(date +%s%N)
    ./fast_math_bin > /dev/null
    END=$(date +%s%N)
    echo "  Прогон $i: $(( (END-START)/1000000 )) мс"
done

echo -e "\nДля сравнения (без --fast-math):"
xc fast_math.x -out standard_bin
for i in 1 2 3; do
    START=$(date +%s%N)
    ./standard_bin > /dev/null
    END=$(date +%s%N)
    echo "  Прогон $i: $(( (END-START)/1000000 )) мс"
done
