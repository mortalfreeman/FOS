#include <QApplication>
#include <QIcon>
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
        setWindowIcon(QIcon("logo.svg"));
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
