#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Выделение парсера в отдельный крейт (xlang-parser)..."
mkdir -p xlang-parser/src

# Копируем ast, parser, sema в новый крейт
cp xlang-compiler/src/ast.rs xlang-parser/src/ast.rs
cp xlang-compiler/src/parser.rs xlang-parser/src/parser.rs
cp xlang-compiler/src/sema.rs xlang-parser/src/sema.rs

# Создаем lib.rs
cat > xlang-parser/src/lib.rs << 'EOF'
pub mod ast;
pub mod parser;
pub mod sema;
EOF

# Создаем Cargo.toml для парсера
cat > xlang-parser/Cargo.toml << 'EOF'
[package]
name = "xlang-parser"
version = "0.1.0"
edition = "2021"

[dependencies]
xlang-lexer = { path = "../xlang-lexer" }
dialoguer = "0.11"
EOF

# Меняем импорт в parser.rs
sed -i 's/use xlang_lexer::{Lexer, Token};/use xlang_lexer::{Lexer, Token};/' xlang-parser/src/parser.rs

echo "==> 2. Обновление компилятора (xlang-compiler) для использования xlang-parser..."
# Удаляем старые файлы из компилятора
rm -f xlang-compiler/src/ast.rs xlang-compiler/src/parser.rs xlang-compiler/src/sema.rs

# Обновляем main.rs компилятора
sed -i 's/mod ast;//' xlang-compiler/src/main.rs
sed -i 's/mod parser;//' xlang-compiler/src/main.rs
sed -i 's/mod sema;//' xlang-compiler/src/main.rs

# Добавляем использование нового крейта
sed -i 's/use parser::Parser;/use xlang_parser::parser::Parser;/' xlang-compiler/src/main.rs
sed -i 's/use sema::Sema;/use xlang_parser::sema::Sema;/' xlang-compiler/src/main.rs
sed -i 's/ast::Program/xlang_parser::ast::Program/g' xlang-compiler/src/main.rs
sed -i 's/ast::Item/xlang_parser::ast::Item/g' xlang-compiler/src/main.rs
sed -i 's/ast::Stmt/xlang_parser::ast::Stmt/g' xlang-compiler/src/main.rs
sed -i 's/ast::Expr/xlang_parser::ast::Expr/g' xlang-compiler/src/main.rs
sed -i 's/ast::FuncDecl/xlang_parser::ast::FuncDecl/g' xlang-compiler/src/main.rs

# Обновляем Cargo.toml компилятора
cat > xlang-compiler/Cargo.toml << 'EOF'
[package]
name = "xlang-compiler"
version = "0.1.0"
edition = "2021"

[dependencies]
colored = "2.0"
inkwell = { version = "0.6.0", features = ["llvm18-1"] }
xlang-lexer = { path = "../xlang-lexer" }
xlang-parser = { path = "../xlang-parser" }
EOF

# Добавляем новый крейт в Workspace
if ! grep -q '"xlang-parser"' Cargo.toml; then
    sed -i 's/"xlang-lexer",/"xlang-lexer",\n    "xlang-parser",/' Cargo.toml
fi

echo "==> 3. Создание настоящего LSP-сервера..."
cat > xlang-lsp/Cargo.toml << 'EOF'
[package]
name = "xlang-lsp"
version = "0.1.0"
edition = "2021"

[dependencies]
tower-lsp = "0.20.0"
tokio = { version = "1", features = ["full"] }
xlang-lexer = { path = "../xlang-lexer" }
xlang-parser = { path = "../xlang-parser" }
regex = "1.10"
EOF

cat > xlang-lsp/src/main.rs << 'EOF'
use tower_lsp::{LspService, Server, Client};
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use xlang_lexer::Lexer;
use xlang_parser::parser::Parser;
use regex::Regex;

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
                completion_provider: Some(CompletionOptions { trigger_characters: Some(vec!["$".to_string()]), ..Default::default() }),
                code_action_provider: Some(CodeActionProviderCapability::Simple(true)),
                ..Default::default()
            },
            ..Default::default()
        })
    }

    async fn shutdown(&self) -> Result<()> { Ok(()) }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let mut docs = self.documents.write().await;
        docs.insert(params.text_document.uri.clone(), params.text_document.text);
        self.validate_doc(&params.text_document.uri).await;
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let mut docs = self.documents.write().await;
        if let Some(change) = params.content_changes.into_iter().next() {
            docs.insert(params.text_document.uri.clone(), change.text);
        }
        self.validate_doc(&params.text_document.uri).await;
    }

    async fn code_action(&self, params: CodeActionParams) -> Result<Option<CodeActionResponse>> {
        let uri = params.text_document.uri;
        let docs = self.documents.read().await;
        let text = docs.get(&uri).cloned().unwrap_or_default();
        let mut actions = Vec::new();

        // Ищем паттерн if (var = value) или while (var = value)
        let re = Regex::new(r"(if|while)\s*\([^=]*\s=\s[^=]").unwrap();
        for (idx, line) in text.lines().enumerate() {
            if re.is_match(line) {
                let edit = TextEdit {
                    range: Range {
                        start: Position { line: idx as u32, character: 0 },
                        end: Position { line: idx as u32, character: line.len() as u32 },
                    },
                    new_text: re.replace_all(line, |caps: &regex::Captures| {
                        let orig = &caps[0];
                        orig.replace(" = ", " == ")
                    }).to_string(),
                };
                let mut changes = HashMap::new();
                changes.insert(uri.clone(), vec![edit]);

                actions.push(CodeActionOrCommand::CodeAction(CodeAction {
                    title: "Fix '=' to '=='".to_string(),
                    kind: Some(CodeActionKind::QUICKFIX),
                    edit: Some(WorkspaceEdit { changes: Some(changes), ..Default::default() }),
                    ..Default::default()
                }));
            }
        }

        Ok(Some(actions))
    }

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let uri = params.text_document_position.text_document.uri;
        let docs = self.documents.read().await;
        let text = docs.get(&uri).cloned().unwrap_or_default();
        
        let mut items = vec![
            CompletionItem::new_simple("func".to_string(), "Function".to_string()),
            CompletionItem::new_simple("con".to_string(), "Print".to_string()),
            CompletionItem::new_simple("ci".to_string(), "Read input".to_string()),
            CompletionItem::new_simple("if".to_string(), "If condition".to_string()),
            CompletionItem::new_simple("while".to_string(), "While loop".to_string()),
            CompletionItem::new_simple("switch".to_string(), "Switch statement".to_string()),
        ];

        // Парсим документ и ищем алиасы и функции
        let mut lexer = Lexer::new(&text);
        let tokens = lexer.tokenize();
        for i in 0..tokens.len() {
            if let xlang_lexer::Token::Dollar = tokens[i].0 {
                if i + 2 < tokens.len() {
                    if let xlang_lexer::Token::Alias = tokens[i+1].0 {
                        if let xlang_lexer::Token::Identifier(name) = &tokens[i+2].0 {
                            items.push(CompletionItem::new_simple(name.clone(), "Alias".to_string()));
                        }
                    }
                }
            }
            if let xlang_lexer::Token::Func = tokens[i].0 {
                if i + 1 < tokens.len() {
                    if let xlang_lexer::Token::Identifier(name) = &tokens[i+1].0 {
                        items.push(CompletionItem::new_simple(name.clone(), "Function".to_string()));
                    }
                }
            }
        }
        Ok(Some(CompletionResponse::Array(items)))
    }
}

impl Backend {
    async fn validate_doc(&self, uri: &Url) {
        let docs = self.documents.read().await;
        let text = match docs.get(uri) { Some(t) => t, None => return };
        
        let mut lexer = Lexer::new(text);
        let tokens = lexer.tokenize();
        let mut parser = Parser::new(text, uri.as_str(), false, false);
        let _ = parser.parse_program();

        let mut diagnostics = Vec::new();
        for err in parser.errors {
            // Формат ошибки: "file:line:col: error: message"
            // Пытаемся распарсить строку
            let re = Regex::new(r".*:(\d+):(\d+): error: (.*)").unwrap();
            if let Some(caps) = re.captures(&err) {
                let line = caps[1].parse::<u32>().unwrap_or(0).saturating_sub(1);
                let col = caps[2].parse::<u32>().unwrap_or(0).saturating_sub(1);
                let msg = caps[3].to_string();
                
                diagnostics.push(Diagnostic {
                    range: Range {
                        start: Position { line, character: col },
                        end: Position { line, character: col + 1 },
                    },
                    severity: Some(DiagnosticSeverity::ERROR),
                    message: msg,
                    source: Some("xc".to_string()),
                    ..Default::default()
                });
            }
        }
        
        let _ = self.client.publish_diagnostics(uri.clone(), diagnostics, None).await;
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

echo "==> 4. Обновление init.lua для Neovim..."
mkdir -p ~/.config/nvim
cat > ~/.config/nvim/init.lua << 'EOF'
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.signcolumn = "yes"

vim.filetype.add({
  extension = { x = "xlang", xx = "xlang", xxx = "xlang", xh = "xlang" },
})

local function start_lsp()
    vim.lsp.start({
        name = 'xlang_lsp',
        cmd = { 'xlang-lsp' },
        root_dir = vim.fn.getcwd(),
        capabilities = vim.lsp.protocol.make_client_capabilities(),
    })
    print("LSP: xlang-lsp started!")
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'xlang',
    callback = start_lsp,
})

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('i', '<C-Space>', vim.lsp.buf.completion, opts)
  end,
})

vim.diagnostic.config({ virtual_text = true, signs = true, underline = true })
EOF

echo "==> 5. Пересборка всего проекта..."
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc
cp target/release/xlang-lsp ~/.local/bin/xlang-lsp

echo "========================================="
echo "🎉 LSP СЕРВЕР ГОТОВ!"
echo "========================================="
echo "Теперь открой Neovim:"
echo "  nvim /tmp/test_cli/main.x"
echo ""
echo "1. Ошибки будут подсвечиваться прямо при наборе."
echo "2. Напиши 'if (x = 5)' и нажми ':lua vim.lsp.buf.code_action()' для автоисправления."
echo "3. Автодополнение работает по Ctrl+Space."
