#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Удаление старого PEP из Cargo Workspace..."
sed -i '/"pep",/d' Cargo.toml

echo "==> 2. Создание структуры C++ Qt6 проекта..."
mkdir -p pep-qt

cat > pep-qt/CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.16)
project(pep LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

add_executable(pep
    main.cpp
    xhighlighter.cpp
)

target_link_libraries(pep PRIVATE Qt6::Widgets)
EOF

cat > pep-qt/xhighlighter.h << 'EOF'
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
    struct HighlightingRule { QRegularExpression pattern; QTextCharFormat format; };
    QVector<HighlightingRule> highlightingRules;
    QTextCharFormat commentFormat;
};
EOF

cat > pep-qt/xhighlighter.cpp << 'EOF'
#include "xhighlighter.h"

XHighlighter::XHighlighter(QTextDocument *parent) : QSyntaxHighlighter(parent) {
    HighlightingRule rule;
    
    // Ключевые слова
    QTextCharFormat keywordFormat;
    keywordFormat.setForeground(QColor(100, 200, 255));
    keywordFormat.setFontWeight(QFont::Bold);
    QStringList keywordPatterns = {"\\bfunc\\b", "\\bcon\\b", "\\bif\\b", "\\belse\\b", "\\bwhile\\b", "\\bfor\\b", "\\breturn\\b", "\\buse\\b", "\\balias\\b"};
    for (const QString &pattern : keywordPatterns) {
        rule.pattern = QRegularExpression(pattern);
        rule.format = keywordFormat;
        highlightingRules.append(rule);
    }

    // Строки
    QTextCharFormat stringFormat;
    stringFormat.setForeground(QColor(150, 255, 150));
    rule.pattern = QRegularExpression("\"[^\"]*\"");
    rule.format = stringFormat;
    highlightingRules.append(rule);

    // Макросы $alias, $ping
    QTextCharFormat macroFormat;
    macroFormat.setForeground(QColor(255, 150, 255));
    rule.pattern = QRegularExpression("\\$[a-zA-Z_][a-zA-Z0-9_]*");
    rule.format = macroFormat;
    highlightingRules.append(rule);

    // Числа
    QTextCharFormat numberFormat;
    numberFormat.setForeground(QColor(255, 200, 100));
    rule.pattern = QRegularExpression("\\b[0-9]+(\\.[0-9]+)?\\b");
    rule.format = numberFormat;
    highlightingRules.append(rule);

    // Комментарии !...!
    commentFormat.setForeground(QColor(120, 120, 140));
    commentFormat.setFontItalic(true);
}

void XHighlighter::highlightBlock(const QString &text) {
    for (const HighlightingRule &rule : qAsConst(highlightingRules)) {
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

cat > pep-qt/main.cpp << 'EOF'
#include <QApplication>
#include <QMainWindow>
#include <QSplitter>
#include <QListWidget>
#include <QPlainTextEdit>
#include <QVBoxLayout>
#include <QLabel>
#include <QMenuBar>
#include <QAction>
#include <QFile>
#include <QTextStream>
#include <QProcess>
#include <QFileDialog>
#include <QDir>
#include <QFontDatabase>
#include <QStatusBar>
#include "xhighlighter.h"

class PepWindow : public QMainWindow {
public:
    PepWindow() {
        setWindowTitle("PEP v1.1 (C++ Qt6) — X-lang IDE");
        resize(1100, 750);

        // Боковая панель
        sidebar = new QListWidget(this);
        sidebar->setFixedWidth(220);
        sidebar->setStyleSheet("background-color: #25252D; color: #E0E0E0; border: none;");
        loadProjectFiles();

        // Редактор
        editor = new QPlainTextEdit(this);
        editor->setStyleSheet("background-color: #1E1E24; color: #E0E0E0; selection-background-color: #44475A;");
        QFont font = QFontDatabase::systemFont(QFontDatabase::FixedFont);
        font.setPointSize(12);
        editor->setFont(font);
        editor->setTabStopDistance(40);
        highlighter = new XHighlighter(editor->document());

        // Сплиттер
        QSplitter *splitter = new QSplitter(Qt::Horizontal, this);
        splitter->addWidget(sidebar);
        splitter->addWidget(editor);
        splitter->setSizes({220, 880});
        setCentralWidget(splitter);

        // Меню
        QMenu *fileMenu = menuBar()->addMenu("File");
        QAction *saveAct = fileMenu->addAction("Save (Ctrl+S)");
        QAction *compileAct = fileMenu->addAction("Compile (F5)");

        connect(saveAct, &QAction::triggered, this, &PepWindow::saveFile);
        connect(compileAct, &QAction::triggered, this, &PepWindow::compileFile);
        saveAct->setShortcut(QKeySequence::Save);
        compileAct->setShortcut(QKeySequence(Qt::Key_F5));

        // Статус-бар
        statusLabel = new QLabel("Ready");
        statusBar()->addWidget(statusLabel);
        statusBar()->setStyleSheet("background-color: #40FF40; color: #1E1E24; font-weight: bold;");

        connect(sidebar, &QListWidget::itemClicked, this, &PepWindow::openFile);
    }

private:
    QListWidget *sidebar;
    QPlainTextEdit *editor;
    XHighlighter *highlighter;
    QLabel *statusLabel;
    QString currentFile;

    void loadProjectFiles() {
        sidebar->clear();
        QDir dir(".");
        QStringList filters;
        filters << "*.x" << "*.xx" << "*.xxx" << "*.xh";
        dir.setNameFilters(filters);
        QFileInfoList files = dir.entryInfoList(QDir::Files, QDir::Name);
        for (const QFileInfo &file : files) {
            sidebar->addItem(file.fileName());
        }
    }

    void openFile(QListWidgetItem *item) {
        QString filename = item->text();
        QFile file(filename);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&file);
            editor->setPlainText(in.readAll());
            currentFile = filename;
            statusLabel->setText("Opened: " + filename);
        }
    }

    void saveFile() {
        if (currentFile.isEmpty()) {
            currentFile = QFileDialog::getSaveFileName(this, "Save File", "", "X-lang Files (*.x *.xx *.xxx *.xh)");
            if (currentFile.isEmpty()) return;
        }
        QFile file(currentFile);
        if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&file);
            out << editor->toPlainText();
            statusLabel->setText("Saved: " + currentFile);
        }
    }

    void compileFile() {
        if (currentFile.isEmpty()) {
            statusLabel->setText("No file selected");
            return;
        }
        saveFile();
        statusLabel->setText("Compiling...");
        
        QProcess *process = new QProcess(this);
        
        // Перехват IPC
        connect(process, &QProcess::readyRead, [this, process]() {
            QString output = process->readAllStandardOutput();
            if (output.contains("XQLANG_QUERY:")) {
                statusLabel->setText("Compiler asks: fix '=' to '=='. Auto-yes.");
                process->write("y\n");
            } else {
                statusLabel->setText(output.trimmed());
            }
        });

        connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), [this, process](int exitCode, QProcess::ExitStatus) {
            if (exitCode == 0) statusLabel->setText("Compiled successfully!");
            else statusLabel->setText("Compilation failed.");
            process->deleteLater();
        });
        
        process->start("xc", QStringList() << currentFile);
    }
};

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    app.setStyle("Fusion"); // Нейтральный стиль для темной темы
    
    PepWindow window;
    window.show();
    return app.exec();
}
EOF

echo "==> 3. Сборка C++ приложения через CMake..."
cd pep-qt
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel $(nproc)
cd ..

echo "==> 4. Установка..."
mkdir -p ~/.local/bin
cp pep-qt/build/pep ~/.local/bin/pep

echo "==> 5. Пересборка компилятора xc (на случай, если Cargo Workspace сломался)..."
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc

echo "========================================="
echo "🎉 PEP v1.1 (C++ Qt6) УСПЕШНО УСТАНОВЛЕН!"
echo "========================================="
echo "Запускай редактор (откроется GUI-окно):"
echo "  pep"
