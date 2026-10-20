#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Установка корректных пакетов Qt6 (qt6-declarative содержит Quick Controls 2)..."
sudo pacman -S --needed --noconfirm qt6-base qt6-declarative qt6-tools qt6-svg qt6-wayland cmake clang

echo "==> 2. Исправление Cargo.toml..."
cat > pep/Cargo.toml << 'EOF'
[package]
name = "pep"
version = "1.0.0"
edition = "2021"

[dependencies]
qmetaobject = { version = "0.2", features = ["qtquick"] }
cstr = "1.0"
xlang-lexer = { path = "../xlang-lexer" }
EOF

echo "==> 3. Запись main.rs (чистый Rust + QML)..."
cat > pep/src/main.rs << 'EOF'
use cstr::cstr;
use qmetaobject::prelude::*;
use std::process::Command;

#[derive(QObject, Default)]
struct EditorApp {
    base: qt_base_class!(trait QObject),
    filename: qt_property!(QString; NOTIFY filename_changed),
    filename_changed: qt_signal!(),
}

impl EditorApp {
    fn compile(&self) {
        let file = self.filename.to_string();
        println!("Compiling {}", file);
        let _ = Command::new("xc").arg(&file).spawn();
    }
}

fn main() {
    qml_register_type::<EditorApp>(cstr!("PepApp"), 1, 0, cstr!("EditorApp"));

    let mut engine = QmlEngine::new();
    
    let qml = r#"
    import QtQuick 2.15
    import QtQuick.Controls 2.15
    import QtQuick.Layouts 1.15
    import PepApp 1.0

    ApplicationWindow {
        visible: true
        width: 1100
        height: 750
        title: "PEP v1.0 (Qt6) — X-lang IDE"
        color: "#1E1E24"

        EditorApp {
            id: backend
            filename: "test.x"
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                color: "#25252D"

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    Text {
                        text: "Project Files"
                        color: "#64C8FF"
                        font.bold: true
                        font.pixelSize: 14
                    }
                    ListView {
                        width: parent.width
                        height: parent.height - 40
                        model: ["test.x", "math.x", "sum_test.x", "lib.xh"]
                        delegate: Text {
                            text: modelData
                            color: "#E0E0E0"
                            font.pixelSize: 13
                            padding: 6
                            MouseArea {
                                anchors.fill: parent
                                onClicked: backend.filename = modelData
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#1E1E24"

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 12

                    TextArea {
                        id: editor
                        text: "func main {\n    x = 10;\n    con(\"Hello Qt6!\");\n}"
                        color: "#E0E0E0"
                        font.family: "Monospace"
                        font.pixelSize: 14
                        selectByMouse: true
                        wrapMode: TextArea.NoWrap
                        leftPadding: 10
                        topPadding: 10
                    }
                }
            }
        }

        footer: Rectangle {
            height: 32
            color: "#40FF40"
            Text {
                anchors.centerIn: parent
                text: " NORMAL | " + backend.filename + " | F5: Compile"
                color: "#1E1E24"
                font.bold: true
                font.pixelSize: 13
            }
        }

        Shortcut {
            sequence: "F5"
            onActivated: backend.compile()
        }
    }
    "#;

    engine.load_data(qml.into());
    engine.exec();
}
EOF

echo "==> 4. Сборка..."
cargo build --release

echo "==> 5. Установка..."
cp target/release/pep ~/.local/bin/pep

echo "========================================="
echo "🎉 PEP v1.0 (Qt6 GUI) УСПЕШНО СОБРАН!"
echo "========================================="
echo "Запускай редактор (откроется нативное окно):"
echo "  pep"
