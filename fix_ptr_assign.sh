#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление присваивания по указателю (*p = 100)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Ищем блок Assign и добавляем проверку на Expr::Deref в левой части
old_assign = """        ast::Stmt::Assign { name, value } => {
            if let ast::Expr::Array(elements) = value {"""
new_assign = """        ast::Stmt::Assign { name, value } => {
            // Если имя начинается с '*' (это разыменование), это присваивание по указателю
            if name.starts_with('*') {
                let ptr_name = &name[1..];
                // Получаем указатель из переменной
                if let Some(VarInfo::Scalar(ptr)) = vars.get(ptr_name) {
                    // Генерируем новое значение
                    let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars).into_float_value();
                    // Загружаем указатель из alloca и сохраняем по нему
                    let ptr_val = builder.build_load(i8_ptr_type, *ptr, "ptr_load").unwrap();
                    builder.build_store(ptr_val, val).unwrap();
                    return;
                } else {
                    panic!("Pointer '{}' not found", ptr_name);
                }
            }
            
            if let ast::Expr::Array(elements) = value {"""
content = content.replace(old_assign, new_assign)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

# Нам нужно, чтобы парсер в левой части от `Stmt::Assign` сохранял `*p` как имя (с звездочкой).
# Но сейчас парсер не поддерживает `*` в левой части. Давай это тоже добавим.

echo "==> Обновление парсера для *p = ...;"
python3 - << 'PYEOF'
with open('xlang-compiler/src/parser.rs', 'r') as f:
    content = f.read()

# В parse_stmt ищем обработку Token::Star и добавляем присваивание
old_stmt_star = """            Token::Identifier(name_ref) => {"""
new_stmt_star = """            Token::Star => {
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
            Token::Identifier(name_ref) => {"""
content = content.replace(old_stmt_star, new_stmt_star)

with open('xlang-compiler/src/parser.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста с указателями..."
cd ~/test_pointer
xc ptr.x -out ptr
./ptr
