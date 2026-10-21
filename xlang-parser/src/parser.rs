use xlang_lexer::{Lexer, Token};
use crate::ast::*;
use std::io::{self, Write};

pub struct Parser {
    tokens: Vec<(Token, usize, usize)>,
    pos: usize,
    pub errors: Vec<String>,
    pub no_sec: bool,
    pub null_sec: bool,
    pub is_lsp: bool,
    filename: String,
}

impl Parser {
    pub fn new(input: &str, filename: &str, no_sec: bool, null_sec: bool, is_lsp: bool) -> Self {
        let mut lexer = Lexer::new(input);
        Self { tokens: lexer.tokenize(), pos: 0, errors: Vec::new(), no_sec, null_sec, is_lsp, filename: filename.to_string() }
    }

    fn current(&self) -> &Token { &self.tokens[self.pos].0 }
    fn advance(&mut self) -> Token {
        let tok = self.tokens[self.pos].0.clone();
        if self.pos < self.tokens.len() - 1 { self.pos += 1; }
        tok
    }
    fn match_token(&mut self, expected: Token) -> bool {
        if self.current() == &expected { self.advance(); true } else { false }
    }
    fn error_and_sync(&mut self, msg: String) {
        if self.null_sec { self.advance(); return; }
        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
        self.errors.push(format!("{}:{}:{}: error: {}", self.filename, line, col, msg));
        while self.current() != &Token::EOF {
            if self.current() == &Token::Semicolon { self.advance(); break; }
            if self.current() == &Token::RBrace || self.current() == &Token::Func || self.current() == &Token::Alias { 
                if self.current() == &Token::RBrace { self.advance(); }
                break; 
            }
            self.advance();
        }
    }

    pub fn parse_program(&mut self) -> Program {
        let mut items = Vec::new();
        while self.current() != &Token::EOF {
            match self.current() {
                Token::Hash => {
                    self.advance();
                    if self.match_token(Token::Define) {
                        if self.match_token(Token::Header) {
                            self.match_token(Token::Assign);
                            if let Token::Identifier(name) = self.current().clone() {
                                self.advance(); items.push(Item::HeaderName(name));
                            } else if let Token::StringLiteral(name) = self.current().clone() {
                                self.advance(); items.push(Item::HeaderName(name));
                            }
                        } else if let Token::Identifier(name) = self.current().clone() {
                            self.advance(); self.match_token(Token::As);
                            if let Token::Identifier(_) = self.current().clone() {
                                self.advance(); let body = self.parse_block();
                                items.push(Item::Alias(AliasDecl { name, body }));
                            } else { self.error_and_sync("expected block name".into()); }
                        } else { self.error_and_sync("expected identifier".into()); }
                    } else if self.match_token(Token::End) { break; }
                }
                Token::Dot => {
                    self.advance();
                    if self.match_token(Token::Use) {
                        if let Token::Identifier(name) = self.current().clone() { self.advance(); items.push(Item::Use(name)); }
                    }
                }
                Token::Dollar => {
                    self.advance();
                    if self.match_token(Token::Alias) {
                        if let Token::Identifier(name) = self.current().clone() {
                            self.advance(); let body = self.parse_block();
                            items.push(Item::Alias(AliasDecl { name, body }));
                        }
                    } else if let Token::Identifier(name) = self.current().clone() {
                        self.advance(); self.match_token(Token::Semicolon);
                        items.push(Item::Func(FuncDecl { name: format!("macro_call_{}", name), args: vec![], body: vec![Stmt::MacroCall { name }] }));
                    }
                }
                Token::Func => {
                    self.advance();
                    if let Token::Identifier(name) = self.current().clone() {
                        self.advance(); let mut args = Vec::new();
                        if self.match_token(Token::LParen) {
                            while self.current() != &Token::RParen && self.current() != &Token::EOF {
                                if let Token::Identifier(arg) = self.current().clone() { args.push(arg); self.advance(); }
                                if !self.match_token(Token::Comma) { break; }
                            }
                            self.match_token(Token::RParen);
                        }
                        let body = self.parse_block();
                        items.push(Item::Func(FuncDecl { name, args, body }));
                    }
                }
                Token::Comment(_) => { self.advance(); }
                _ => { self.error_and_sync(format!("unexpected token: {:?}", self.current())); }
            }
        }
        Program { items }
    }

    fn parse_block(&mut self) -> Vec<Stmt> {
        let mut stmts = Vec::new();
        if !self.match_token(Token::LBrace) { return stmts; }
        while self.current() != &Token::RBrace && self.current() != &Token::EOF {
            if let Some(stmt) = self.parse_stmt() { stmts.push(stmt); } else { self.advance(); }
        }
        self.match_token(Token::RBrace);
        stmts
    }

    fn parse_stmt(&mut self) -> Option<Stmt> {
        match self.current() {
            Token::Comment(_) => { self.advance(); self.parse_stmt() }
            Token::Break => { self.advance(); self.match_token(Token::Semicolon); Some(Stmt::Break) }
            Token::Continue => { self.advance(); self.match_token(Token::Semicolon); Some(Stmt::Continue) }
            Token::Return => { self.advance(); let val = self.parse_expr()?; self.match_token(Token::Semicolon); Some(Stmt::Return { value: val }) }
            Token::For => {
                self.advance(); // 'for'
                self.match_token(Token::LParen); // '('

                // Проверяем: это for-in или обычный for?
                let is_for_in = matches!(self.current(), Token::Identifier(_))
                    && self.pos + 1 < self.tokens.len()
                    && self.tokens[self.pos + 1].0 == Token::In;

                if is_for_in {
                    let var_name = if let Token::Identifier(n) = self.current().clone() {
                        self.advance();
                        n
                    } else { unreachable!() };
                    self.advance(); // 'in'
                    let iterable = self.parse_expr()?;
                    self.match_token(Token::RParen); // ')'
                    let body = self.parse_block(); // '{ ... }'
                    return Some(Stmt::ForIn { var: var_name, iterable, body });
                }

                // Обычный C-like for
                let init = if self.current() != &Token::Semicolon {
                    if let Token::Identifier(name) = self.current().clone() {
                        self.advance();
                        self.match_token(Token::Assign);
                        Some(Box::new(Stmt::Assign { name, value: self.parse_expr()? }))
                    } else { None }
                } else { None };
                self.match_token(Token::Semicolon);
                let condition = if self.current() != &Token::Semicolon {
                    let left = self.parse_expr()?;
                    let mut op = "==".to_string();
                    if self.match_token(Token::Eq) { op = "==".to_string(); }
                    else if self.match_token(Token::NotEq) { op = "!=".to_string(); }
                    else if self.match_token(Token::Lt) { op = "<".to_string(); }
                    else if self.match_token(Token::Gt) { op = ">".to_string(); }
                    else if self.match_token(Token::LtEq) { op = "<=".to_string(); }
                    else if self.match_token(Token::GtEq) { op = ">=".to_string(); }
                    Some((left, op, self.parse_expr()?))
                } else { None };
                self.match_token(Token::Semicolon);
                let increment = if self.current() != &Token::RParen {
                    if let Token::Identifier(name) = self.current().clone() {
                        self.advance();
                        self.match_token(Token::Assign);
                        Some(Box::new(Stmt::Assign { name, value: self.parse_expr()? }))
                    } else { None }
                } else { None };
                self.match_token(Token::RParen);
                Some(Stmt::For { init, condition, increment, body: self.parse_block() })
            }
            Token::Switch => {
                self.advance();
                self.match_token(Token::LParen);
                let expr = self.parse_expr()?;
                self.match_token(Token::RParen);
                self.match_token(Token::LBrace);
                let mut cases = vec![];
                let mut default = None;
                while self.current() != &Token::RBrace && self.current() != &Token::EOF {
                    if self.match_token(Token::Case) {
                        let case_expr = self.parse_expr()?;
                        self.match_token(Token::Colon);
                        let mut body = vec![];
                        while self.current() != &Token::Case && self.current() != &Token::Default && self.current() != &Token::RBrace && self.current() != &Token::EOF {
                            if let Some(stmt) = self.parse_stmt() { body.push(stmt); } else { self.advance(); }
                        }
                        cases.push((case_expr, body));
                    } else if self.match_token(Token::Default) {
                        self.match_token(Token::Colon);
                        let mut body = vec![];
                        while self.current() != &Token::Case && self.current() != &Token::RBrace && self.current() != &Token::EOF {
                            if let Some(stmt) = self.parse_stmt() { body.push(stmt); } else { self.advance(); }
                        }
                        default = Some(body);
                    } else {
                        self.advance();
                    }
                }
                self.match_token(Token::RBrace);
                Some(Stmt::Switch { expr, cases, default })
            }
            Token::If | Token::While => {
                let is_while = self.current() == &Token::While;
                self.advance(); self.match_token(Token::LParen);
                let left = self.parse_expr()?;
                let mut op = "!=".to_string(); let mut right = Expr::Float(0.0); let mut has_op = false;
                if self.match_token(Token::Assign) {
                    if self.is_lsp {
                        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
                        self.errors.push(format!("{}:{}:{}: error: '=' used instead of '=='", self.filename, line, col));
                        op = "==".to_string();
                    } else if !self.no_sec && !self.null_sec {
                        let (line, col) = (self.tokens[self.pos].1, self.tokens[self.pos].2);
                        // IPC CALL
                        print!("XQLANG_QUERY: Do you want to insert another = in {} (...) ? (Line {}:{}) [y/N] ", if is_while {"while"} else {"if"}, line, col);
                        io::stdout().flush().unwrap();
                        let mut input = String::new();
                        io::stdin().read_line(&mut input).unwrap();
                        if input.trim().to_lowercase() == "y" { op = "==".to_string(); } 
                        else { self.errors.push(format!("{}:{}:{}: error: '=' used instead of '=='", self.filename, line, col)); return None; }
                    } else { op = "==".to_string(); }
                    has_op = true;
                } else if self.match_token(Token::Eq) { op = "==".to_string(); has_op = true; }
                else if self.match_token(Token::NotEq) { op = "!=".to_string(); has_op = true; }
                else if self.match_token(Token::Lt) { op = "<".to_string(); has_op = true; }
                else if self.match_token(Token::Gt) { op = ">".to_string(); has_op = true; }
                else if self.match_token(Token::LtEq) { op = "<=".to_string(); has_op = true; }
                else if self.match_token(Token::GtEq) { op = ">=".to_string(); has_op = true; }
                if has_op { right = self.parse_expr()?; }
                self.match_token(Token::RParen);
                let body = self.parse_block();
                if is_while { Some(Stmt::While { condition: (left, op, right), body }) }
                else {
                    let mut else_branch = None;
                    if self.match_token(Token::Else) {
                        if self.current() == &Token::If { if let Some(ei) = self.parse_stmt() { else_branch = Some(vec![ei]); } }
                        else { else_branch = Some(self.parse_block()); }
                    }
                    Some(Stmt::If { condition: (left, op, right), then_branch: body, else_branch })
                }
            }
            Token::Star => {
                self.advance(); // '*'
                if let Token::Identifier(name) = self.current().clone() {
                    self.advance(); // 'name'
                    if self.match_token(Token::Assign) {
                        let val = self.parse_expr()?;
                        self.match_token(Token::Semicolon);
                        return Some(Stmt::Assign { name: format!("*{}", name), value: val });
                    }
                }
                self.error_and_sync("expected identifier after *".into());
                None
            }
            Token::Identifier(name_ref) => {
                let name = name_ref.clone();
                let next_tok = self.tokens[self.pos + 1].0.clone();
                if next_tok == Token::Assign {
                    self.advance(); self.advance();
                    Some(Stmt::Assign { name, value: self.parse_expr()? })
                } else if next_tok == Token::LBracket {
                    self.advance(); self.advance();
                    let idx = self.parse_expr()?; self.match_token(Token::RBracket);
                    if self.match_token(Token::Assign) { Some(Stmt::IndexAssign { name, index: Box::new(idx), value: self.parse_expr()? }) } else { None }
                } else if next_tok == Token::LParen {
                    let expr = self.parse_expr()?; self.match_token(Token::Semicolon);
                    Some(Stmt::Expr(expr))
                } else { self.advance(); None }
            }
            Token::Con | Token::Ci | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil | Token::Len => {
                let expr = self.parse_expr()?; self.match_token(Token::Semicolon);
                Some(Stmt::Expr(expr))
            }
            Token::Dollar => {
                self.advance();
                if let Token::Identifier(name) = self.current().clone() {
                    self.advance(); self.match_token(Token::Semicolon);
                    Some(Stmt::MacroCall { name })
                } else { None }
            }
            _ => None,
        }
    }

    fn parse_expr(&mut self) -> Option<Expr> { self.parse_term() }
    fn parse_term(&mut self) -> Option<Expr> {
        let mut left = self.parse_factor()?;
        while self.current() == &Token::Plus || self.current() == &Token::Minus {
            let op = if self.current() == &Token::Plus { "+" } else { "-" };
            self.advance(); left = Expr::BinaryOp { left: Box::new(left), op: op.to_string(), right: Box::new(self.parse_factor()?) };
        }
        Some(left)
    }
    fn parse_factor(&mut self) -> Option<Expr> {
        let mut left = self.parse_primary()?;
        while self.current() == &Token::Star || self.current() == &Token::Slash || self.current() == &Token::Percent || self.current() == &Token::Caret {
            let op = if self.current() == &Token::Star { "*" } else if self.current() == &Token::Slash { "/" } else if self.current() == &Token::Percent { "%" } else { "^" };
            self.advance(); left = Expr::BinaryOp { left: Box::new(left), op: op.to_string(), right: Box::new(self.parse_primary()?) };
        }
        Some(left)
    }
    fn parse_primary(&mut self) -> Option<Expr> {
        match self.current().clone() {
            Token::Minus => {
                self.advance();
                if let Some(expr) = self.parse_primary() {
                    match expr {
                        Expr::Int(n) => Some(Expr::Int(-n)),
                        Expr::Float(f) => Some(Expr::Float(-f)),
                        _ => Some(Expr::BinaryOp { left: Box::new(Expr::Int(0)), op: "-".to_string(), right: Box::new(expr) }),
                    }
                } else { None }
            }
            Token::IntLiteral(n) => { self.advance(); Some(Expr::Int(n)) }
            Token::FloatLiteral(f) => { self.advance(); Some(Expr::Float(f)) }
            Token::StringLiteral(s) => { self.advance(); Some(Expr::String(s)) }
            Token::LBracket => {
                self.advance();
                let first = self.parse_expr()?;
                if self.match_token(Token::Semicolon) {
                    let count = self.parse_expr()?;
                    self.match_token(Token::RBracket);
                    return Some(Expr::ArrayFill { value: Box::new(first), count: Box::new(count) });
                }
                let mut elements = vec![first];
                while self.current() == &Token::Comma {
                    self.advance();
                    if let Some(expr) = self.parse_expr() { elements.push(expr); }
                }
                self.match_token(Token::RBracket);
                Some(Expr::Array(elements))
            }
            Token::LParen => { self.advance(); let e = self.parse_expr()?; self.match_token(Token::RParen); Some(e) }
            Token::Amp => {
                self.advance();
                let expr = self.parse_expr()?;
                Some(Expr::Ref(Box::new(expr)))
            }
            Token::Star => {
                self.advance();
                let expr = self.parse_expr()?;
                Some(Expr::Deref(Box::new(expr)))
            }
            Token::Identifier(s) => {
                self.advance();
                if self.match_token(Token::LBracket) {
                    let idx = self.parse_expr()?; self.match_token(Token::RBracket);
                    Some(Expr::Index { name: s, index: Box::new(idx) })
                } else if self.current() == &Token::LParen {
                    self.match_token(Token::LParen); let mut args = Vec::new();
                    while self.current() != &Token::RParen && self.current() != &Token::EOF {
                        if self.current() == &Token::Comma || self.current() == &Token::Pipe || self.current() == &Token::RBrace || self.current() == &Token::LBrace { self.advance(); continue; }
                        if let Some(e) = self.parse_expr() { args.push(e); } else { self.advance(); }
                    }
                    self.match_token(Token::RParen); Some(Expr::Call { name: s, args })
                } else { Some(Expr::Identifier(s)) }
            }
            Token::Con | Token::Ci | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil | Token::Len => {
                let name = match self.advance() {
                    Token::Con => "con", Token::Ci => "ci", Token::Powr => "powr", Token::Sin => "sin", Token::Cosin => "cosin",
                    Token::Sin2 => "sin2", Token::IsOdd => "is-odd", Token::IsEven => "is-even", Token::Round => "round", Token::Floor => "floor", Token::Ceil => "ceil",
                    Token::Len => "len",
                    _ => unreachable!(),
                }.to_string();
                self.match_token(Token::LParen); let mut args = Vec::new();
                while self.current() != &Token::RParen && self.current() != &Token::EOF {
                    if self.current() == &Token::Comma || self.current() == &Token::Pipe || self.current() == &Token::RBrace || self.current() == &Token::LBrace { self.advance(); continue; }
                    if let Some(e) = self.parse_expr() { args.push(e); } else { self.advance(); }
                }
                self.match_token(Token::RParen); Some(Expr::Call { name, args })
            }
            _ => None,
        }
    }
}
