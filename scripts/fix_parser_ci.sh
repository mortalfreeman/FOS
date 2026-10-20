#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление обработки Token::Ci в парсер..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/parser.rs', 'r') as f:
    content = f.read()

# Ищем блок обработки токенов Con/Ci/Powr в parse_primary
old_primary = """            Token::Con | Token::Ci | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil => {
                let name = match self.advance() {
                    Token::Con => "con", Token::Ci => "ci", Token::Powr => "powr",
                    Token::Sin => "sin", Token::Cosin => "cosin", Token::Sin2 => "sin2",
                    Token::IsOdd => "is-odd", Token::IsEven => "is-even",
                    Token::Round => "round", Token::Floor => "floor", Token::Ceil => "ceil",
                    _ => unreachable!(),
                }.to_string();
                self.match_token(Token::LParen);
                let mut args = Vec::new();
                while self.current() != &Token::RParen && self.current() != &Token::EOF {
                    if self.current() == &Token::Comma { self.advance(); continue; }
                    if let Some(expr) = self.parse_expr() { args.push(expr); } else { self.advance(); }
                }
                self.match_token(Token::RParen);
                Some(Expr::Call { name, args })
            }"""

new_primary = """            Token::Ci => {
                self.advance();
                self.match_token(Token::LParen);
                let mut args = Vec::new();
                while self.current() != &Token::RParen && self.current() != &Token::EOF {
                    if self.current() == &Token::Comma { self.advance(); continue; }
                    if let Some(expr) = self.parse_expr() { args.push(expr); } else { self.advance(); }
                }
                self.match_token(Token::RParen);
                Some(Expr::Call { name: "ci".to_string(), args })
            }
            Token::Con | Token::Powr | Token::Sin | Token::Cosin | Token::Sin2 | Token::IsOdd | Token::IsEven | Token::Round | Token::Floor | Token::Ceil => {
                let name = match self.advance() {
                    Token::Con => "con", Token::Powr => "powr",
                    Token::Sin => "sin", Token::Cosin => "cosin", Token::Sin2 => "sin2",
                    Token::IsOdd => "is-odd", Token::IsEven => "is-even",
                    Token::Round => "round", Token::Floor => "floor", Token::Ceil => "ceil",
                    _ => unreachable!(),
                }.to_string();
                self.match_token(Token::LParen);
                let mut args = Vec::new();
                while self.current() != &Token::RParen && self.current() != &Token::EOF {
                    if self.current() == &Token::Comma { self.advance(); continue; }
                    if let Some(expr) = self.parse_expr() { args.push(expr); } else { self.advance(); }
                }
                self.match_token(Token::RParen);
                Some(Expr::Call { name, args })
            }"""

content = content.replace(old_primary, new_primary)
with open('xlang-compiler/src/parser.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_ci
xc input_test.x -out input_test
./input_test
