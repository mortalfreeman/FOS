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
        eprintln!("LSP DEBUG: did_open called for {}", params.text_document.uri);
        let mut docs = self.documents.write().await;
        docs.insert(params.text_document.uri.clone(), params.text_document.text);
        self.validate_doc(&params.text_document.uri).await;
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        eprintln!("LSP DEBUG: did_change called");
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
        let mut parser = Parser::new(text, uri.as_str(), false, false, true);
        eprintln!("LSP DEBUG: Parsing document...");
        let _ = parser.parse_program();

        let mut diagnostics = Vec::new();
        eprintln!("LSP DEBUG: Found {} errors", parser.errors.len());
        for err in parser.errors {
            eprintln!("LSP DEBUG: Error -> {}", err);
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
        
        eprintln!("LSP DEBUG: Sending {} diagnostics", diagnostics.len());
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
