#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление file-write-num в компилятор..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

if '"file-write-num"' not in content:
    file_write_num = r'''
                "file-write-num" => {
                    if args.len() >= 2 {
                        let file_val = gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars);
                        let file_ptr = match file_val { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected file") };
                        let num_raw = gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars);
                        let num_i = to_int(builder, num_raw, i64_type);
                        
                        let temp_buf = builder.build_alloca(i8_type.array_type(32), "tmp_num").unwrap();
                        let buf_cast = builder.build_pointer_cast(temp_buf, i8_ptr_type, "cast").unwrap();
                        let fmt = builder.build_global_string_ptr("%lld\n", "fmt_num").unwrap();
                        builder.build_call(libc.sprintf, &[buf_cast.into(), fmt.as_pointer_value().into(), num_i.into()], "sprintf").unwrap();
                        let len = builder.build_call(libc.strlen, &[buf_cast.into()], "len_num").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                        builder.build_call(libc.fwrite, &[buf_cast.into(), i64_type.const_int(1, false).into(), len.into(), file_ptr.into()], "fwrite").unwrap();
                    }
                    f64_type.const_float(0.0).into()
                }
'''
    content = content.replace('                "file-write" => {', file_write_num + '                "file-write" => {')

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Создание C-теста..."
cat > /tmp/writeC.c << 'CCODE'
#include <stdio.h>
int main() {
    FILE *f = fopen("/tmp/writeC.test.log", "w");
    if (!f) return 1;
    for (long long i = 1; i <= 50000000; i++) {
        fprintf(f, "%lld\n", i);
    }
    fclose(f);
    return 0;
}
CCODE
gcc -O3 /tmp/writeC.c -o /tmp/writeC

echo "==> 4. Создание X-lang теста..."
cat > /tmp/writeX.x << 'XCODE'
.use std
.use fileman

func main {
    f = file-open("/tmp/writeX.test.log");
    for (i = 1; i <= 50000000; i = i + 1) {
        file-write-num(f, i);
    }
    file-close(f);
}
XCODE
xc /tmp/writeX.x -out /tmp/writeX

echo "==> 5. ЗАПУСК (это займет ~10-30 секунд)..."
rm -f /tmp/writeC.test.log /tmp/writeX.test.log

echo "--- Запуск C ---"
START=$(date +%s%N)
/tmp/writeC
END=$(date +%s%N)
C_TIME=$(( (END-START)/1000000 ))
echo "C время: ${C_TIME} мс"

echo "--- Запуск X-lang ---"
START=$(date +%s%N)
/tmp/writeX
END=$(date +%s%N)
X_TIME=$(( (END-START)/1000000 ))
echo "X-lang время: ${X_TIME} мс"

echo ""
echo "========================================="
echo "📊 РЕЗУЛЬТАТ"
echo "========================================="
echo "C (gcc -O3):     ${C_TIME} мс"
echo "X-lang (LLVM):   ${X_TIME} мс"
echo ""
echo "Размер C файла:   $(stat -c%s /tmp/writeC.test.log 2>/dev/null || echo 0) байт"
echo "Размер X файла:   $(stat -c%s /tmp/writeX.test.log 2>/dev/null || echo 0) байт"
echo ""
echo "=== Первые 5 строк из C ==="
head -5 /tmp/writeC.test.log 2>/dev/null || echo "файл не создан"
echo "=== Первые 5 строк из X ==="
head -5 /tmp/writeX.test.log 2>/dev/null || echo "файл не создан"
