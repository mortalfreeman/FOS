use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Token {
    Func, Con, If, Else, Return, Use, Alias, Ci, Powr, While, For, Break, Continue,
    Sin, Cosin, Sin2, IsOdd, IsEven, Round, Floor, Ceil,
    Define, Header, As, Output, Input, End, Struct,
    Hash, Pipe, ShiftRight, ShiftLeft,
    Dollar, Dot, LBrace, RBrace, LParen, RParen, LBracket, RBracket, Semicolon, Comma, 
    Assign, Eq, NotEq, Minus, Plus, Star, Slash, Lt, Gt, LtEq, GtEq, Amp, Percent, Caret, Colon, In, Len,
    Identifier(String), StringLiteral(String), FloatLiteral(f64), IntLiteral(i64),
    Comment(String), Flag(String), EOF,
}

pub struct Lexer { chars: Vec<char>, pos: usize, line: usize, col: usize }

impl Lexer {
    pub fn new(input: &str) -> Self { Self { chars: input.chars().collect(), pos: 0, line: 1, col: 1 } }
    fn peek(&self) -> Option<char> { self.chars.get(self.pos).copied() }
    fn peek_next(&self) -> Option<char> { self.chars.get(self.pos + 1).copied() }
    fn advance(&mut self) -> Option<char> {
        let ch = self.peek()?;
        self.pos += 1;
        if ch == '\n' { self.line += 1; self.col = 1; } else { self.col += 1; }
        Some(ch)
    }

    pub fn tokenize(&mut self) -> Vec<(Token, usize, usize)> {
        let mut tokens = Vec::new();
        while let Some(ch) = self.peek() {
            let start_line = self.line; let start_col = self.col;
            match ch {
                ' ' | '\t' | '\n' | '\r' => { self.advance(); }
                '!' => {
                    if self.peek_next() == Some('=') { self.advance(); self.advance(); tokens.push((Token::NotEq, start_line, start_col)); }
                    else {
                        self.advance(); let mut comment = String::new();
                        while let Some(c) = self.peek() { if c == '!' { self.advance(); break; } comment.push(self.advance().unwrap()); }
                        tokens.push((Token::Comment(comment), start_line, start_col));
                    }
                }
                '#' => { self.advance(); tokens.push((Token::Hash, start_line, start_col)); }
                '|' => { self.advance(); tokens.push((Token::Pipe, start_line, start_col)); }
                '"' => {
                    self.advance(); let mut string = String::new();
                    while let Some(c) = self.peek() { 
                        if c == '"' { self.advance(); break; } 
                        if c == '\\' {
                            self.advance();
                            if let Some(esc) = self.peek() {
                                match esc {
                                    'n' => string.push('\n'),
                                    't' => string.push('\t'),
                                    _ => string.push(esc),
                                }
                                self.advance();
                            }
                        } else {
                            string.push(self.advance().unwrap()); 
                        }
                    }
                    tokens.push((Token::StringLiteral(string), start_line, start_col));
                }
                c if c.is_alphabetic() || c == '_' => {
                    let mut ident = String::new();
                    while let Some(c) = self.peek() {
                        if c.is_alphanumeric() || c == '_' || (c == '-' && ident == "is") { ident.push(self.advance().unwrap()); } else { break; }
                    }
                    let token = match ident.as_str() {
                        "func" => Token::Func, "con" => Token::Con, "if" => Token::If, "else" => Token::Else,
                        "return" => Token::Return, "use" => Token::Use, "alias" => Token::Alias,
                        "ci" => Token::Ci, "powr" => Token::Powr, "while" => Token::While,
                        "for" => Token::For, "break" => Token::Break, "continue" => Token::Continue,
                        "sin" => Token::Sin, "cosin" => Token::Cosin, "sin2" => Token::Sin2,
                        "is-odd" => Token::IsOdd, "is-even" => Token::IsEven,
                        "round" => Token::Round, "floor" => Token::Floor, "ceil" => Token::Ceil,
                        "Define" => Token::Define, "Header" => Token::Header, "as" => Token::As,
                        "Output" => Token::Output, "Input" => Token::Input, "END" => Token::End,
                        "struct" => Token::Struct, "in" => Token::In, "len" => Token::Len,
                        _ => Token::Identifier(ident),
                    };
                    tokens.push((token, start_line, start_col));
                }
                c if c.is_ascii_digit() => {
                    let mut num = String::new();
                    while let Some(c) = self.peek() {
                        if c.is_ascii_digit() || c == '.' { num.push(self.advance().unwrap()); } else { break; }
                    }
                    if num.contains('.') { tokens.push((Token::FloatLiteral(num.parse().unwrap_or(0.0)), start_line, start_col)); }
                    else { tokens.push((Token::IntLiteral(num.parse().unwrap_or(0)), start_line, start_col)); }
                }
                '-' => {
                    self.advance();
                    if self.peek().map_or(false, |c| c.is_alphabetic()) {
                        let mut flag = String::new();
                        while let Some(c) = self.peek() { if c.is_alphanumeric() || c == '-' || c == '_' { flag.push(self.advance().unwrap()); } else { break; } }
                        tokens.push((Token::Flag(flag), start_line, start_col));
                    } else {
                        tokens.push((Token::Minus, start_line, start_col));
                    }
                }
                '+' => { self.advance(); tokens.push((Token::Plus, start_line, start_col)); }
                '*' => { self.advance(); tokens.push((Token::Star, start_line, start_col)); }
                '/' => { self.advance(); tokens.push((Token::Slash, start_line, start_col)); }
                '%' => { self.advance(); tokens.push((Token::Percent, start_line, start_col)); }
                '^' => { self.advance(); tokens.push((Token::Caret, start_line, start_col)); }
                '&' => { self.advance(); tokens.push((Token::Amp, start_line, start_col)); }
                '<' => { self.advance(); if self.peek() == Some('=') { self.advance(); tokens.push((Token::LtEq, start_line, start_col)); } else { tokens.push((Token::Lt, start_line, start_col)); } }
                '>' => { self.advance(); if self.peek() == Some('=') { self.advance(); tokens.push((Token::GtEq, start_line, start_col)); } else { tokens.push((Token::Gt, start_line, start_col)); } }
                '$' => { self.advance(); tokens.push((Token::Dollar, start_line, start_col)); }
                '.' => { self.advance(); tokens.push((Token::Dot, start_line, start_col)); }
                '[' => { self.advance(); tokens.push((Token::LBracket, start_line, start_col)); }
                ']' => { self.advance(); tokens.push((Token::RBracket, start_line, start_col)); }
                '{' => { self.advance(); tokens.push((Token::LBrace, start_line, start_col)); }
                '}' => { self.advance(); tokens.push((Token::RBrace, start_line, start_col)); }
                '(' => { self.advance(); tokens.push((Token::LParen, start_line, start_col)); }
                ')' => { self.advance(); tokens.push((Token::RParen, start_line, start_col)); }
                ';' => { self.advance(); tokens.push((Token::Semicolon, start_line, start_col)); }
                ':' => { self.advance(); tokens.push((Token::Colon, start_line, start_col)); }
                ',' => { self.advance(); tokens.push((Token::Comma, start_line, start_col)); }
                '=' => { self.advance(); if self.peek() == Some('=') { self.advance(); tokens.push((Token::Eq, start_line, start_col)); } else { tokens.push((Token::Assign, start_line, start_col)); } }
                _ => { self.advance(); }
            }
        }
        tokens.push((Token::EOF, self.line, self.col));
        tokens
    }
}
