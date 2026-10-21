#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание структуры WASM-крейта..."
mkdir -p xlang-wasm/src
mkdir -p web/playground
mkdir -p web/wasm

cat > xlang-wasm/Cargo.toml << 'EOF'
[package]
name = "xlang-wasm"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
wasm-bindgen = "0.2"
xlang-lexer = { path = "../xlang-lexer" }
xlang-parser = { path = "../xlang-parser" }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

# Добавляем в Workspace
if ! grep -q '"xlang-wasm"' Cargo.toml; then
    sed -i 's/"xlang-parser",/"xlang-parser",\n    "xlang-wasm",/' Cargo.toml
fi

cat > xlang-wasm/src/lib.rs << 'EOF'
use wasm_bindgen::prelude::*;
use xlang_lexer::Lexer;
use xlang_parser::parser::Parser;
use xlang_parser::sema::Sema;

#[wasm_bindgen]
pub fn compile_xlang(code: &str) -> String {
    let mut parser = Parser::new(code, "playground.x", false, false, true);
    let program = parser.parse_program();

    if !parser.errors.is_empty() {
        return format!("Ошибки компиляции:\n{}", parser.errors.join("\n"));
    }

    let mut sema = Sema::new(false, false, "playground.x");
    sema.analyze(&program);

    if !sema.errors.is_empty() {
        return format!("Ошибки семантики:\n{}", sema.errors.join("\n"));
    }

    let mut lexer = Lexer::new(code);
    let tokens = lexer.tokenize();
    
    let mut token_count = 0;
    for (tok, _, _) in tokens {
        if !matches!(tok, xlang_lexer::Token::EOF | xlang_lexer::Token::Comment(_)) {
            token_count += 1;
        }
    }

    format!("✅ Успешно!\nНайдено токенов: {}\nПарсинг: OK\nСемантика: OK", token_count)
}
EOF

echo "==> 2. Создание веб-интерфейса Playground..."
cat > web/playground/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>X-lang Playground</title>
    <style>
        body { background: #1e1e24; color: #e0e0e0; font-family: 'Fira Code', monospace; margin: 0; padding: 20px; }
        .container { display: flex; gap: 20px; }
        textarea { width: 50%; height: 500px; background: #141419; color: #e0e0e0; border: 1px solid #333; padding: 15px; font-family: monospace; font-size: 16px; border-radius: 8px; resize: none; }
        .output { width: 50%; height: 500px; background: #141419; color: #96ff96; border: 1px solid #333; padding: 15px; font-family: monospace; font-size: 16px; border-radius: 8px; overflow-y: auto; white-space: pre-wrap; }
        button { background: #64C8FF; color: #1e1e24; border: none; padding: 10px 20px; font-size: 16px; font-weight: bold; cursor: pointer; border-radius: 6px; margin-top: 10px; }
        button:hover { background: #96ff96; }
        h1 { color: #64C8FF; }
    </style>
</head>
<body>
    <h1>X-lang Playground 🚀</h1>
    <div class="container">
        <textarea id="code">.use GOIO

func main {
    con("Hello, World!");
    x = 10;
    con("x is: ", x);
}</textarea>
        <div class="output" id="output">Нажми "Run", чтобы скомпилировать код.</div>
    </div>
    <button onclick="runCode()">▶ Run</button>

    <script type="module">
        import init, { compile_xlang } from './wasm/xlang_wasm.js';

        async function runCode() {
            await init();
            const code = document.getElementById('code').value;
            const output = document.getElementById('output');
            try {
                const result = compile_xlang(code);
                output.textContent = result;
                output.style.color = result.startsWith("✅") ? "#96ff96" : "#ff6464";
            } catch (e) {
                output.textContent = "Ошибка: " + e.message;
                output.style.color = "#ff6464";
            }
        }
        window.runCode = runCode;
    </script>
</body>
</html>
EOF

echo "==> 3. Проверка wasm-pack и установка..."
if ! command -v wasm-pack &> /dev/null; then
    sudo pacman -S --needed --noconfirm wasm-pack || cargo install wasm-pack
fi

echo "==> 4. Сборка WASM..."
cd xlang-wasm
wasm-pack build --target web --out-dir ../web/wasm
cd ..

echo "==> 5. Запуск сервера..."
echo ""
echo "========================================="
echo "🎉 PLAYGROUND ГОТОВ!"
echo "========================================="
echo "Сейчас запустится сервер. Открой в браузере:"
echo "  http://localhost:8080/playground/index.html"
echo ""
cd web && python3 -m http.server 8080
