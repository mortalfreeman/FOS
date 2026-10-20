#!/bin/bash
set -e

echo "==> 1. Установка системных зависимостей (Qt6, CMake, Clang)..."
if command -v pacman &> /dev/null; then
    sudo pacman -S --needed --noconfirm qt6-base qt6-tools cmake clang pkg-config
elif command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y qt6-base-dev qt6-tools-dev cmake clang libclang-dev
fi

cd ~/FOS

echo "==> 2. Создание C++ подсветчика синтаксиса (XHighlighter)..."
mkdir -p pep/cpp
cat > pep/cpp/highlighter.h << 'EOF'
#pragma once
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QRegularExpression>

class XHighlighter : public QSyntaxHighlighter {
    Q_OBJECT
public:
    explicit XHighlighter(QTextDocument *parent = nullptr);
protected:
    void highlightBlock(const QString &text) override;
private:
    struct Rule { QRegularExpression pattern; QTextCharFormat format; };
    QVector<Rule> rules;
    QTextCharFormat commentFormat;
};
EOF

cat > pep/cpp/highlighter.cpp << 'EOF'
#include "highlighter.h"

XHighlighter::XHighlighter(QTextDocument *parent) : QSyntaxHighlighter(parent) {
    // Ключевые слова (func, con, if, else, while, for, return)
    QTextCharFormat keywordFormat;
    keywordFormat.setForeground(QColor(100, 200, 255));
    keywordFormat.setFontWeight(QFont::Bold);
    QStringList keywords = {"\\bfunc\\b", "\\bcon\\b", "\\bif\\b", "\\belse\\b", "\\bwhile\\b", "\\bfor\\b", "\\breturn\\b"};
    for (const QString &pattern : keywords) {
        rules.append({QRegularExpression(pattern), keywordFormat});
    }

    // Строки
    QTextCharFormat stringFormat;
    stringFormat.setForeground(QColor(150, 255, 150));
    rules.append({QRegularExpression("\"[^\"]*\""), stringFormat});

    // Макросы ($alias, $ping)
    QTextCharFormat macroFormat;
    macroFormat.setForeground(QColor(255, 150, 255));
    rules.append({QRegularExpression("\\$[a-zA-Z_][a-zA-Z0-9_]*"), macroFormat});

    // Числа
    QTextCharFormat numberFormat;
    numberFormat.setForeground(QColor(255, 200, 100));
    rules.append({QRegularExpression("\\b[0-9]+(\\.[0-9]+)?\\b"), numberFormat});

    // Комментарии ! ... !
    commentFormat.setForeground(QColor(120, 120, 140));
    commentFormat.setFontItalic(true);
}

void XHighlighter::highlightBlock(const QString &text) {
    for (const Rule &rule : qAsConst(rules)) {
        QRegularExpressionMatchIterator matchIterator = rule.pattern.globalMatch(text);
        while (matchIterator.hasNext()) {
            QRegularExpressionMatch match = matchIterator.next();
            setFormat(match.capturedStart(), match.capturedLength(), rule.format);
        }
    }

    // Инлайновые комментарии
    QRegularExpression commentStart("!");
    QRegularExpressionMatchIterator startIt = commentStart.globalMatch(text);
    while (startIt.hasNext()) {
        QRegularExpressionMatch startMatch = startIt.next();
        int start = startMatch.capturedStart();
        int end = text.indexOf("!", start + 1);
        if (end != -1) {
            setFormat(start, end - start + 1, commentFormat);
        }
    }
}
EOF

echo "==> 3. Настройка Cargo.toml для PEP (Qt6)..."
cat > pep/Cargo.toml << 'EOF'
[package]
name = "pep"
version = "1.0.0"
edition = "2021"
build = "build.rs"

[dependencies]
cxx = "1.0"
cxx-qt = "0.6"
cxx-qt-lib = { version = "0.6", features = ["qt6"] }
qtrs = "0.5"
xlang-lexer = { path = "../xlang-lexer" }
EOF

echo "==> 4. Настройка build.rs для сборки C++...";
cat > pep/build.rs << 'EOF'
fn main() {
    cxx_build::bridge("src/main.rs")
        .file("cpp/highlighter.cpp")
        .include("cpp")
        .flag_if_supported("-std=c++17")
        .compile("pep_cpp");

    println!("cargo:rerun-if-changed=src/main.rs");
    println!("cargo:rerun-if-changed=cpp/highlighter.cpp");
    println!("cargo:rerun-if-changed=cpp/highlighter.h");
}
EOF

echo "==> 5. Написание main.rs (GUI-редактор)..."
cat > pep/src/main.rs << 'EOF'
use cxx_qt_lib::{QString, QVector};
use qtrs::*;
use std::fs;
use std::path::Path;

#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("pep/cpp/highlighter.h");
        type XHighlighter;
        fn new_highlighter(doc: *mut c_void) -> *mut XHighlighter;
        fn attach_highlighter(highlighter: *mut XHighlighter, doc: *mut c_void);
    }
}

struct PepApp {
    lines: Vec<String>,
}

fn main() {
    // Инициализация Qt
    qtrs::init();

    let app = QApplication::new();

    // Главное окно
    let mut window = QMainWindow::new();
    window.set_window_title("PEP v1.0 — X-lang IDE");
    window.resize(1200, 800);

    // Центральный виджет — редактор
    let mut editor = QPlainTextEdit::new();
    editor.set_font(&QFont::new("Monospace", 12));
    
    // Загрузка файла (пример)
    let args: Vec<String> = std::env::args().collect();
    let filename = if args.len() > 1 { &args[1] } else { "main.x" };
    if let Ok(content) = fs::read_to_string(filename) {
        editor.set_plain_text(&QString::from(&content));
    }

    // Применяем подсветку синтаксиса
    unsafe {
        let doc_ptr = editor.document() as *mut c_void;
        let highlighter = ffi::new_highlighter(doc_ptr);
        ffi::attach_highlighter(highlighter, doc_ptr);
    }

    // Боковая панель (простой список файлов)
    let mut sidebar = QListWidget::new();
    if let Some(parent) = Path::new(filename).parent() {
        if let Ok(entries) = fs::read_dir(parent) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                    if matches!(ext, "x" | "xx" | "xxx" | "xh") {
                        sidebar.add_item(&QString::from(path.file_name().unwrap().to_str().unwrap()));
                    }
                }
            }
        }
    }

    let mut splitter = QSplitter::new(Qt::Horizontal);
    splitter.add_widget(&sidebar);
    splitter.add_widget(&editor);
    splitter.set_sizes(&[200, 1000]);
    window.set_central_widget(&splitter);

    // Меню
    let menubar = window.menu_bar();
    let file_menu = menubar.add_menu(&QString::from("File"));
    let save_action = file_menu.add_action(&QString::from("Save (Ctrl+S)"));
    let compile_action = file_menu.add_action(&QString::from("Compile (F5)"));

    // Обработка Ctrl+S
    let editor_ptr = editor.clone();
    let filename_str = filename.to_string();
    save_action.on_triggered(move || {
        let text = editor_ptr.to_plain_text().to_string();
        let _ = fs::write(&filename_str, text);
    });

    // Обработка F5 (компиляция)
    let editor_ptr2 = editor.clone();
    let filename_str2 = filename.to_string();
    compile_action.on_triggered(move || {
        let text = editor_ptr2.to_plain_text().to_string();
        let _ = fs::write(&filename_str2, text);
        let _ = std::process::Command::new("xc").arg(&filename_str2).spawn();
    });

    window.show();
    app.exec();
}
EOF

echo "==> 6. Сборка..."
cd pep
cargo build --release
cd ..

echo "==> 7. Установка..."
mkdir -p ~/.local/bin
cp target/release/pep ~/.local/bin/pep

echo "========================================="
echo "🎉 PEP v1.0 (Qt6 NATIVE) УСПЕШНО СОБРАН!"
echo "========================================="
echo "Запускай редактор:"
echo "  pep ~/test_ipc.x"
