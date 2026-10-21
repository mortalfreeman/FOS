#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление оператора ^ (XOR) в лексер и парсер..."
python3 - << 'PYEOF'
# Лексер
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()
if 'Caret' not in content:
    content = content.replace('Amp,', 'Amp, Caret,')
    content = content.replace("'&' => { self.advance(); tokens.push((Token::Amp, start_line, start_col)); }", "'&' => { self.advance(); tokens.push((Token::Amp, start_line, start_col)); }\n                '^' => { self.advance(); tokens.push((Token::Caret, start_line, start_col)); }")
    with open('xlang-lexer/src/lib.rs', 'w') as f:
        f.write(content)

# Парсер
with open('xlang-compiler/src/parser.rs', 'r') as f:
    content = f.read()
content = content.replace(
    "while self.current() == &Token::Star || self.current() == &Token::Slash || self.current() == &Token::Percent {",
    "while self.current() == &Token::Star || self.current() == &Token::Slash || self.current() == &Token::Percent || self.current() == &Token::Caret {"
)
content = content.replace(
    "let op = if self.current() == &Token::Star { \"*\" } else if self.current() == &Token::Slash { \"/\" } else { \"%\" };",
    "let op = if self.current() == &Token::Star { \"*\" } else if self.current() == &Token::Slash { \"/\" } else if self.current() == &Token::Percent { \"%\" } else { \"^\" };"
)
with open('xlang-compiler/src/parser.rs', 'w') as f:
    f.write(content)

# Кодогенератор
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()
content = content.replace(
    '"%" => builder.build_int_signed_rem(l, r, "remtmp").unwrap().into(),',
    '"%" => builder.build_int_signed_rem(l, r, "remtmp").unwrap().into(),\n                    "^" => builder.build_xor(l, r, "xortmp").unwrap().into(),'
)
with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-lexer
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Исправление честных тестов (4, 8, 11) и их запуск..."
cd /tmp/nuclear_bench
LOG="/tmp/result.test.log"

echo "" >> "$LOG"
echo "▶ ЧЕСТНЫЙ ТЕСТ 4: Bubble Sort (10k)" >> "$LOG"
printf "%-15s | %-10s | %-10s | %-10s\n" "Язык" "Компиляция" "Размер" "Время" >> "$LOG"
echo "----------------------------------------------------------------" >> "$LOG"

# Генерируем массив из 10000 элементов на X-lang
python3 -c "print('func main {\n    arr = [' + ','.join(['0']*10000) + '];\n    for (i = 0; i < 10000; i = i + 1) { arr[i] = 10000 - i; }\n    for (i = 0; i < 10000; i = i + 1) {\n        for (j = 0; j < 9999; j = j + 1) {\n            if (arr[j] > arr[j+1]) { t = arr[j]; arr[j] = arr[j+1]; arr[j+1] = t; }\n        }\n    }\n    con(1);\n}')" > test4.x
xc test4.x -out test4_x
START=$(date +%s%N); ./test4_x > /dev/null; END=$(date +%s%N)
printf "%-15s | %-10s | %-10s | %-10s мс\n" "X-lang" "-" "-" "$(( (END-START)/1000000 ))" >> "$LOG"

echo "" >> "$LOG"
echo "▶ ЧЕСТНЫЙ ТЕСТ 8: Bubble Sort (5k)" >> "$LOG"
printf "%-15s | %-10s | %-10s | %-10s\n" "Язык" "Компиляция" "Размер" "Время" >> "$LOG"
echo "----------------------------------------------------------------" >> "$LOG"
python3 -c "print('func main {\n    arr = [' + ','.join(['0']*5000) + '];\n    for (i = 0; i < 5000; i = i + 1) { arr[i] = 5000 - i; }\n    for (i = 0; i < 5000; i = i + 1) {\n        for (j = 0; j < 4999; j = j + 1) {\n            if (arr[j] > arr[j+1]) { t = arr[j]; arr[j] = arr[j+1]; arr[j+1] = t; }\n        }\n    }\n    con(1);\n}')" > test8.x
xc test8.x -out test8_x
START=$(date +%s%N); ./test8_x > /dev/null; END=$(date +%s%N)
printf "%-15s | %-10s | %-10s | %-10s мс\n" "X-lang" "-" "-" "$(( (END-START)/1000000 ))" >> "$LOG"

echo "" >> "$LOG"
echo "▶ ЧЕСТНЫЙ ТЕСТ 11: Bitwise XOR (100M)" >> "$LOG"
printf "%-15s | %-10s | %-10s | %-10s\n" "Язык" "Компиляция" "Размер" "Время" >> "$LOG"
echo "----------------------------------------------------------------" >> "$LOG"
cat > test11.x << 'XLANG'
func main {
    s = 0;
    for (i = 0; i < 100000000; i = i + 1) {
        s = s ^ i;
    }
    con(s);
}
XLANG
xc test11.x -out test11_x
START=$(date +%s%N); ./test11_x > /dev/null; END=$(date +%s%N)
printf "%-15s | %-10s | %-10s | %-10s мс\n" "X-lang" "-" "-" "$(( (END-START)/1000000 ))" >> "$LOG"

echo ""
echo "🎉 ИСПРАВЛЕННЫЕ ТЕСТЫ ДОБАВЛЕНЫ В ЛОГ!"
echo "Посмотри результат: tail -n 20 /tmp/result.test.log"
