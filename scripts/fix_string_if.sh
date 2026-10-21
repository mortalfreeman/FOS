#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление сравнения строк в if, while, for..."
python3 - << 'PYEOF'
import re
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Паттерн для поиска блока сравнения (он одинаковый для if, while и for)
# Ищем: let cmp = if left.is_int_value() && right.is_int_value() { ... } else { let l = to_float...
pattern = r'(let cmp = if left\.is_int_value\(\) && right\.is_int_value\(\) \{\n\s*let l = left\.into_int_value\(\); let r = right\.into_int_value\(\);\n\s*match (.*?)\.as_str\(\) \{(.*?)\n\s*\}\n\s*\}) else \{\n\s*let l = to_float'

def replace_block(match):
    cond_var = match.group(1) # condition.1, cond.1, etc.
    match_body = match.group(2)
    
    # Формируем новый блок с добавлением проверки на указатели
    new_block = match.group(1) + f''' else if left.is_pointer_value() && right.is_pointer_value() {{
                let l = left.into_pointer_value(); let r = right.into_pointer_value();
                let strcmp_res = builder.build_call(libc.strcmp, &[l.into(), r.into()], "strcmp").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let zero = i32_type.const_zero();
                match {cond_var}.as_str() {{
                    "==" => builder.build_int_compare(IntPredicate::EQ, strcmp_res, zero, "cmp").unwrap(),
                    "!=" => builder.build_int_compare(IntPredicate::NE, strcmp_res, zero, "cmp").unwrap(),
                    _ => panic!("Unsupported string comparison operator")
                }}
            }} else {{
                let l = to_float'''
    
    return new_block

# Применяем замену
new_content = re.sub(pattern, replace_block, content, flags=re.DOTALL)

if new_content == content:
    print("⚠️ Внимание: не удалось найти блоки сравнения. Возможно, код уже изменен.")
else:
    content = new_content
    print("✅ Успешно добавлено сравнение строк в условия.")

# 5d. Проверяем, что libc.strcmp вообще есть в структуре
if 'strcmp: FunctionValue' not in content:
    print("⚠️ Внимание: strcmp не найден в структуре Libc. Добавляем...")
    content = content.replace("strcat: FunctionValue<'ctx>,", "strcat: FunctionValue<'ctx>, strcmp: FunctionValue<'ctx>,")
    content = content.replace("strcat: module.add_function(\"strcat\",", "strcmp: module.add_function(\"strcmp\", i32_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None),\n        strcat: module.add_function(\"strcat\",")

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест..."
cd ~/FOS/test_v3
xc test.x -out test_bin
./test_bin
