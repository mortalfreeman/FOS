#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление получения текущей функции для проверки NULL..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

old_bb = '''                        let ok_bb = context.append_basic_block(context.get_insert_block().unwrap().get_parent().unwrap(), "file_ok");
                        let err_bb = context.append_basic_block(context.get_insert_block().unwrap().get_parent().unwrap(), "file_err");'''

new_bb = '''                        let current_fn = builder.get_insert_block().unwrap().get_parent().unwrap();
                        let ok_bb = context.append_basic_block(current_fn, "file_ok");
                        let err_bb = context.append_basic_block(current_fn, "file_err");'''

content = content.replace(old_bb, new_bb)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста (с проверкой)..."
rm -f /tmp/writeX.test.log
xc /tmp/writeX.x -out /tmp/writeX
START=$(date +%s%N)
/tmp/writeX
END=$(date +%s%N)
echo "X-lang время: $(( (END-START)/1000000 )) мс"
echo "Размер файла: $(stat -c%s /tmp/writeX.test.log 2>/dev/null || echo 0) байт"
head -5 /tmp/writeX.test.log 2>/dev/null || echo "Файл не создан"
