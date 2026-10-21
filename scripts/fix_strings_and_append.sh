#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление обработки \\n в лексер..."
python3 - << 'PYEOF'
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()

# В цикле чтения строки заменяем \n на реальный перенос строки
old_string = """                '"' => {
                    self.advance(); let mut string = String::new();
                    while let Some(c) = self.peek() { if c == '"' { self.advance(); break; } string.push(self.advance().unwrap()); }
                    tokens.push((Token::StringLiteral(string), start_line, start_col));
                }"""

new_string = """                '"' => {
                    self.advance(); let mut string = String::new();
                    while let Some(c) = self.peek() { 
                        if c == '"' { self.advance(); break; } 
                        if c == '\\\\' {
                            self.advance();
                            if let Some(esc) = self.peek() {
                                match esc {
                                    'n' => string.push('\\n'),
                                    't' => string.push('\\t'),
                                    _ => string.push(esc),
                                }
                                self.advance();
                            }
                        } else {
                            string.push(self.advance().unwrap()); 
                        }
                    }
                    tokens.push((Token::StringLiteral(string), start_line, start_col));
                }"""

content = content.replace(old_string, new_string)
with open('xlang-lexer/src/lib.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Исправление режима file-open на 'a+' (добавление в конец)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# В file-open меняем "r+" на "a+"
content = content.replace(
    'let mode = builder.build_global_string_ptr("r+", "mode").unwrap();',
    'let mode = builder.build_global_string_ptr("a+", "mode").unwrap();'
)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Пересборка лексера и компилятора..."
cargo build --release -p xlang-lexer 2>&1 | tail -2
cargo build --release -p xlang-compiler 2>&1 | tail -2
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 4. Повторный тест FILEMAN..."
rm -f /tmp/fileman_test/test.txt
cd /tmp/fileman_test

cat > test_file.x << 'XLANG'
.use std
.use fileman

func main {
    con("=== FILEMAN TEST ===");
    
    file-new("test", "txt", "Hello, FILEMAN!\nThis is a new line.");
    con("File 'test.txt' created.");
    
    content = file-read("./", "test.txt");
    con("Content read from file:");
    con(content);
    
    f = file-open("test.txt");
    file-write(f, "\nAppended line.");
    file-close(f);
    con("Appended text.");
    
    content2 = file-read("./", "test.txt");
    con("Updated content:");
    con(content2);
}
XLANG

xc test_file.x -out test_file
./test_file

echo ""
echo "=== Содержимое test.txt ==="
cat test.txt
