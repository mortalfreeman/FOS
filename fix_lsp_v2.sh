#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Обновление зависимостей LSP (добавлен tokio)..."
cat > xlang-lsp/Cargo.toml << 'EOF'
[package]
name = "xlang-lsp"
version = "0.1.0"
edition = "2021"

[dependencies]
tower-lsp = "0.20.0"
tokio = { version = "1", features = ["full"] }
xlang-lexer = { path = "../xlang-lexer" }
EOF

echo "==> 2. Перезапись LSP-сервера (кэш, автодополнение, диагностика)..."
cat > xlang-lsp/src/main.rs << 'EOF'
use tower_lsp::{LspService, Server, Client};
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use std::process::Command;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use xlang_lexer::{Lexer, Token};

struct Backend {
    client: Client,
    documents: Arc<RwLock<HashMap<Url, String>>>,
}

#[tower_lsp::async_trait]
impl tower_lsp::LanguageServer for Backend {
    async fn initialize(&self, _: InitializeParams) -> Result<InitializeResult> {
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Kind(TextDocumentSyncKind::FULL)),
                completion_provider: Some(CompletionOptions {
                    trigger_characters: Some(vec!["$".to_string(), ".".to_string()]),
                    ..Default::default()
                }),
                ..Default::default()
            },
            ..Default::default()
        })
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let mut docs = self.documents.write().await;
        docs.insert(params.text_document.uri, params.text_document.text);
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let mut docs = self.documents.write().await;
        if let Some(change) = params.content_changes.into_iter().next() {
            docs.insert(params.text_document.uri, change.text);
        }
    }

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let mut items = vec![
            CompletionItem::new_simple("func".to_string(), "Function declaration".to_string()),
            CompletionItem::new_simple("con".to_string(), "Print with newline".to_string()),
            CompletionItem::new_simple("if".to_string(), "If condition".to_string()),
            CompletionItem::new_simple("while".to_string(), "While loop".to_string()),
            CompletionItem::new_simple("for".to_string(), "For loop".to_string()),
            CompletionItem::new_simple("ci".to_string(), "Read from keyboard".to_string()),
            CompletionItem::new_simple("powr".to_string(), "Power function".to_string()),
        ];

        // Извлекаем пользовательские алиасы и функции из текущего документа
        let docs = self.documents.read().await;
        if let Some(text) = docs.get(&params.text_document_position.text_document.uri) {
            let mut lexer = Lexer::new(text);
            let tokens = lexer.tokenize();
            for i in 0..tokens.len() {
                if let Token::Dollar = tokens[i].0 {
                    if i + 1 < tokens.len() {
                        if let Token::Alias = tokens[i+1].0 {
                            if i + 2 < tokens.len() {
                                if let Token::Identifier(name) = &tokens[i+2].0 {
                                    items.push(CompletionItem::new_simple(name.clone(), "Alias".to_string()));
                                }
                            }
                        } else if let Token::Identifier(name) = &tokens[i+1].0 {
                            items.push(CompletionItem::new_simple(name.clone(), "Macro Call".to_string()));
                        }
                    }
                } else if let Token::Func = tokens[i].0 {
                    if i + 1 < tokens.len() {
                        if let Token::Identifier(name) = &tokens[i+1].0 {
                            items.push(CompletionItem::new_simple(name.clone(), "Function".to_string()));
                        }
                    }
                }
            }
        }
        Ok(Some(CompletionResponse::Array(items)))
    }

    async fn did_save(&self, params: DidSaveTextDocumentParams) {
        let uri = params.text_document.uri;
        if let Ok(path) = uri.to_file_path() {
            if path.exists() {
                let output = Command::new("xc").arg(&path).output();
                if let Ok(out) = output {
                    let stdout = String::from_utf8_lossy(&out.stdout);
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let mut diagnostics = Vec::new();

                    for line in stdout.lines().chain(stderr.lines()) {
                        if line.contains("error:") {
                            let parts: Vec<&str> = line.split("error:").collect();
                            if parts.len() == 2 {
                                diagnostics.push(Diagnostic {
                                    range: Range {
                                        start: Position { line: 0, character: 0 },
                                        end: Position { line: 0, character: 100 },
                                    },
                                    severity: Some(DiagnosticSeverity::ERROR),
                                    message: parts[1].trim().to_string(),
                                    source: Some("xc".to_string()),
                                    ..Default::default()
                                });
                            }
                        }
                    }
                    
                    let _ = self.client.publish_diagnostics(uri, diagnostics, None).await;
                }
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();
    
    let (service, socket) = LspService::new(|client| Backend {
        client,
        documents: Arc::new(RwLock::new(HashMap::new())),
    });
    Server::new(stdin, stdout, socket).serve(service).await;
}
EOF

echo "==> 3. Пересборка LSP..."
cargo build --release
cp target/release/xlang-lsp ~/.local/bin/

echo "========================================="
echo "🎉 LSP v2 УСПЕШНО СКОМПИЛИРОВАН!"
echo "========================================="
echo "Теперь запусти Neovim и проверь:"
echo "  nvim ~/test_lsp.x"
echo ""
echo "1. Открой файл и нажми :w (сохрани). Если есть ошибка, она подчеркнется красным."
echo "2. Нажми i и введи '$' или 'func', затем Ctrl+Space (автодополнение подтянет твои макросы)."
