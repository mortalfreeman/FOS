#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание надежного .gitignore..."
cat > .gitignore << 'EOF'
# Rust
target/
**/*.rs.bk
Cargo.lock

# C++ / CMake
build/
cmake-build-*/
*.o
*.obj

# IDE / Editor
.vscode/
.idea/
*.swp
.DS_Store

# Архивы
*.tar.gz
*.zip

# Node.js (для веба)
node_modules/
EOF

echo "==> 2. Создание современной веб-страницы (HTML/CSS/JS)..."
mkdir -p web
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FOS — Free Open Source Software</title>
    <link rel="stylesheet" href="style.css">
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;700&family=Inter:wght@300;400;700&display=swap" rel="stylesheet">
</head>
<body>
    <div class="glass-container">
        <header>
            <div class="logo">FOS<span>.</span></div>
            <nav>
                <a href="#xlang">X-lang</a>
                <a href="#pep">PEP Editor</a>
                <a href="#lsp">LSP</a>
                <a href="https://github.com" class="btn-github" target="_blank">GitHub</a>
            </nav>
        </header>

        <main>
            <section class="hero">
                <h1 id="typing-text">Суверенный стек разработки.</h1>
                <p>Fast = Easy, Fast = Secure. Экосистема инструментов, созданная с нуля.</p>
            </section>

            <section id="xlang" class="feature-grid">
                <div class="card">
                    <h2>X-lang</h2>
                    <p>Компилируемый язык программирования (Rust + LLVM). Встроенная система сборки, макросы и интерактивное исправление ошибок.</p>
                </div>
                <div class="card">
                    <h2>PEP Editor</h2>
                    <p>Ультра-легкий редактор на C++ Qt6 с кастомной подсветкой синтаксиса и стеклянным интерфейсом.</p>
                </div>
                <div class="card">
                    <h2>xlang-lsp</h2>
                    <p>Сервер языкового протокола для Neovim и VS Code. Мгновенная диагностика ошибок и автодополнение.</p>
                </div>
            </section>

            <section class="code-section">
                <h2>Почувствуй скорость</h2>
                <pre><code><span class="keyword">use</span> GOIO

<span class="keyword">$alias</span> greet {
    con(<span class="string">"Hello FOS!"</span>);
}

<span class="keyword">func</span> main {
    x = <span class="number">10</span>;
    <span class="macro">$greet</span>;
    con(<span class="string">"Value: "</span>, x);
}</code></pre>
            </section>
        </main>

        <footer>
            <p>&copy; 2026 FOS Project. Licensed under FSL-Permissive.</p>
        </footer>
    </div>
    <script src="script.js"></script>
</body>
</html>
EOF

cat > web/style.css << 'EOF'
:root {
    --bg-color: #0f0f13;
    --glass-bg: rgba(30, 30, 36, 0.6);
    --text-main: #e0e0e0;
    --accent: #64C8FF;
    --accent-glow: rgba(100, 200, 255, 0.3);
}

* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: 'Inter', sans-serif;
    background-color: var(--bg-color);
    background-image: 
        radial-gradient(circle at 15% 50%, rgba(100, 200, 255, 0.08), transparent 25%),
        radial-gradient(circle at 85% 30%, rgba(255, 150, 255, 0.08), transparent 25%);
    color: var(--text-main);
    min-height: 100vh;
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 2rem;
}

.glass-container {
    background: var(--glass-bg);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 24px;
    padding: 3rem;
    max-width: 1100px;
    width: 100%;
    box-shadow: 0 30px 60px rgba(0, 0, 0, 0.4);
}

header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 4rem;
}

.logo { font-size: 2rem; font-weight: 700; letter-spacing: 2px; }
.logo span { color: var(--accent); }

nav a {
    color: var(--text-main);
    text-decoration: none;
    margin-left: 2rem;
    font-size: 0.9rem;
    transition: color 0.3s;
}

nav a:hover { color: var(--accent); }

.btn-github {
    background: var(--accent);
    color: var(--bg-color) !important;
    padding: 0.5rem 1.5rem;
    border-radius: 8px;
    font-weight: 700;
    box-shadow: 0 0 15px var(--accent-glow);
}

.hero { text-align: center; margin-bottom: 4rem; }
.hero h1 {
    font-size: 3.5rem;
    margin-bottom: 1rem;
    background: linear-gradient(90deg, #fff, var(--accent));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}
.hero p { font-size: 1.2rem; color: #888; }

.feature-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 2rem;
    margin-bottom: 4rem;
}

.card {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.05);
    padding: 2rem;
    border-radius: 16px;
    transition: transform 0.3s, border-color 0.3s;
}

.card:hover {
    transform: translateY(-5px);
    border-color: var(--accent);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
}

.card h2 { color: var(--accent); margin-bottom: 1rem; font-size: 1.5rem; }

.code-section {
    background: #141419;
    border-radius: 16px;
    padding: 2rem;
    border: 1px solid rgba(255, 255, 255, 0.05);
}

.code-section h2 { text-align: center; margin-bottom: 1.5rem; font-weight: 400; }

pre { font-family: 'Fira Code', monospace; font-size: 1rem; line-height: 1.6; overflow-x: auto; }
.keyword { color: #64C8FF; font-weight: bold; }
.string { color: #96FF96; }
.number { color: #FFC864; }
.macro { color: #FF96FF; }
.comment { color: #808080; font-style: italic; }

footer { text-align: center; margin-top: 4rem; color: #555; font-size: 0.9rem; }
EOF

cat > web/script.js << 'EOF'
// Простая анимация печатающегося текста
const text = "Суверенный стек разработки.";
const element = document.getElementById("typing-text");
let index = 0;

function type() {
    if (index < text.length) {
        element.textContent = text.slice(0, index + 1);
        index++;
        setTimeout(type, 100);
    }
}

// Очищаем и запускаем анимацию
element.textContent = "";
setTimeout(type, 500);

// Плавная прокрутка
document.querySelectorAll('nav a').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        if(this.getAttribute('href').startsWith('#')) {
            e.preventDefault();
            document.querySelector(this.getAttribute('href')).scrollIntoView({
                behavior: 'smooth'
            });
        }
    });
});
EOF

echo "==> 3. Упаковка релиза..."
cd ~
rm -f FOS_v0.1_source.tar.gz
tar -czvf FOS_v0.1_source.tar.gz --exclude='FOS/target' --exclude='FOS/pep-qt/build' --exclude='FOS/.git' FOS/ > /dev/null
echo "Архив создан: ~/FOS_v0.1_source.tar.gz"

echo "==> 4. Подготовка Git..."
cd ~/FOS
if [ ! -d ".git" ]; then
    git init -q
fi

cat > LICENSE << 'EOF'
FSL-Permissive (Free Software License - Permissive)
Copyright (c) 2026 FOS Project

Разрешается использование, копирование, модификация и распространение 
в исходном или бинарном виде, с изменениями или без, при условии 
сохранения данного уведомления. Код можно использовать в закрытых проектах.
EOF

git add .
git commit -m "FOS Ecosystem v0.1: X-lang compiler, PEP editor, LSP, Web landing page" -q || true
git branch -M main

echo "========================================="
echo "✅ ВСЁ ЛОКАЛЬНО ГОТОВО!"
echo "========================================="
echo "1. Твой исходный код и веб-сайт скоммичены в git."
echo "2. Твой архив готов: ~/FOS_v0.1_source.tar.gz"
echo ""
echo "👉 Теперь зайди на github.com/new, создай пустой репозиторий (например, FOS)"
echo "👉 Вставь ссылку на него и нажми Enter, чтобы я запушил код:"

read -p "Ссылка на GitHub (или нажми Enter чтобы пропустить): " REPO_URL

if [ ! -z "$REPO_URL" ]; then
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REPO_URL"
    git push -u origin main
    echo "🚀 УСПЕШНО ЗАПУШЕНО НА GITHUB!"
else
    echo "Пропущено. Ты можешь запушить позже командой: git remote add origin <URL> && git push -u origin main"
fi
