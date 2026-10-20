#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание SVG-логотипа (P с E внутри и P внизу)..."
cat > web/logo.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 150" width="120" height="150">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#64C8FF" />
      <stop offset="100%" stop-color="#FF96FF" />
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="3" result="blur" />
      <feMerge>
        <feMergeNode in="blur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
  
  <!-- Темный фон со скруглениями -->
  <rect width="120" height="150" fill="#1E1E24" rx="20"/>
  
  <!-- Большая P -->
  <text x="20" y="85" font-family="'Fira Code', monospace" font-size="90" font-weight="bold" fill="url(#grad)" filter="url(#glow)">P</text>
  
  <!-- Буква E внутри -->
  <text x="55" y="75" font-family="'Fira Code', monospace" font-size="40" font-weight="bold" fill="#E0E0E0">E</text>
  
  <!-- Маленькая P внизу -->
  <text x="45" y="130" font-family="'Fira Code', monospace" font-size="40" font-weight="bold" fill="url(#grad)">P</text>
</svg>
EOF

# Копируем логотип для PEP (Qt) и README
cp web/logo.svg pep-qt/logo.svg
cp web/logo.svg logo.svg

echo "==> 2. Обновление веб-сайта (внедрение логотипа)..."
python3 - << 'PYEOF'
with open('web/index.html', 'r') as f:
    html = f.read()

# Заменяем текстовый логотип на картинку
html = html.replace(
    '<div class="logo">FOS<span>.</span></div>',
    '<div class="logo" style="display: flex; align-items: center; gap: 10px;"><img src="logo.svg" alt="FOS Logo" style="width: 40px; height: 40px;"> FOS<span>.</span></div>'
)
with open('web/index.html', 'w') as f:
    f.write(html)
PYEOF

echo "==> 3. Обновление C++ PEP (установка иконки окна)..."
python3 - << 'PYEOF'
with open('pep-qt/main.cpp', 'r') as f:
    cpp = f.read()

# Добавляем иконку окна
if '#include <QIcon>' not in cpp:
    cpp = cpp.replace('#include <QApplication>', '#include <QApplication>\n#include <QIcon>')

cpp = cpp.replace(
    'setWindowTitle("PEP v1.1 (C++ Qt6) — X-lang IDE");',
    'setWindowTitle("PEP v1.1 (C++ Qt6) — X-lang IDE");\n        setWindowIcon(QIcon("logo.svg"));'
)
with open('pep-qt/main.cpp', 'w') as f:
    f.write(cpp)
PYEOF

echo "==> 4. Обновление README.md..."
python3 - << 'PYEOF'
with open('README.md', 'r') as f:
    md = f.read()

logo_md = """<p align="center">
  <img src="web/logo.svg" width="150" alt="FOS Logo">
</p>

# FOS (Free Open Source Software)
"""
# Заменяем первый заголовок на красивый логотип
md = md.replace("# FOS (Free Open Source Software)\n", logo_md)

with open('README.md', 'w') as f:
    f.write(md)
PYEOF

echo "==> 5. Пересборка PEP с новой иконкой (если Qt установлен)..."
if [ -d "pep-qt" ]; then
    cd pep-qt
    cmake -B build -S . -DCMAKE_BUILD_TYPE=Release > /dev/null
    cmake --build build > /dev/null
    cp build/pep ~/.local/bin/pep 2>/dev/null || true
    cd ..
fi

echo "==> 6. Коммит и пуш на GitHub..."
git add .
git commit -m "Release v0.2: Added SVG Logo (P-E-P), updated Web, README and PEP icon" || true
git push origin main

echo "========================================="
echo "🎉 ОБНОВЛЕНИЕ v0.2 УСПЕШНО ЗАГРУЖЕНО!"
echo "========================================="
echo "1. Логотип добавлен в веб-интерфейс и README."
echo "2. Иконка окна PEP обновлена."
echo "3. Все изменения на GitHub: https://github.com/mortalfreeman/FOS"
