#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Обновление Лексера (добавление & и *)..."
python3 - << 'PYEOF'
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()

# Добавляем токены & и * (у нас уже есть Star, но нужен Amp)
if 'Amp' not in content:
    content = content.replace(
        'Assign, Eq, NotEq, Minus, Plus, Star, Slash, Lt, Gt, LtEq, GtEq,',
        'Assign, Eq, NotEq, Minus, Plus, Star, Slash, Lt, Gt, LtEq, GtEq, Amp,'
    )
    # Добавляем обработку '&'
    content = content.replace(
        "'*' => { self.advance(); tokens.push((Token::Star, start_line, start_col)); }",
        "'*' => { self.advance(); tokens.push((Token::Star, start_line, start_col)); }\n                '&' => { self.advance(); tokens.push((Token::Amp, start_line, start_col)); }"
    )

with open('xlang-lexer/src/lib.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Обновление AST (добавление Ref и Deref)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/ast.rs', 'r') as f:
    content = f.read()

if 'Ref(Box<Expr>)' not in content:
    content = content.replace(
        'BinaryOp { left: Box<Expr>, op: String, right: Box<Expr> },',
        'BinaryOp { left: Box<Expr>, op: String, right: Box<Expr> },\n    Ref(Box<Expr>),\n    Deref(Box<Expr>),'
    )

with open('xlang-compiler/src/ast.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Обновление Парсера (чтение & и *)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/parser.rs', 'r') as f:
    content = f.read()

# В parse_primary добавляем обработку &
old_primary = """            Token::Identifier(s) => {
                self.advance();
                if self.match_token(Token::LBracket) {"""
new_primary = """            Token::Amp => {
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
                if self.match_token(Token::LBracket) {"""
content = content.replace(old_primary, new_primary)

with open('xlang-compiler/src/parser.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 4. Обновление Кодогенератора (указатели)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем обработку Ref и Deref в gen_expr
old_binaryop = """        ast::Expr::BinaryOp { left, op, right } => {"""
new_binaryop = """        ast::Expr::Ref(inner) => {
            let val = gen_expr(context, builder, module, inner, aliases, user_functions, libc, vars);
            let alloca = builder.build_alloca(val.get_type(), "ref_tmp").unwrap();
            builder.build_store(alloca, val).unwrap();
            alloca.into()
        }
        ast::Expr::Deref(inner) => {
            let val = gen_expr(context, builder, module, inner, aliases, user_functions, libc, vars);
            if let BasicValueEnum::PointerValue(ptr) = val {
                let load = builder.build_load(f64_type, ptr, "deref_load").unwrap();
                load.into()
            } else {
                panic!("Dereference of non-pointer");
            }
        }
        ast::Expr::BinaryOp { left, op, right } => {"""
content = content.replace(old_binaryop, new_binaryop)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 5. Пересборка..."
cargo build --release -p xlang-lexer
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 6. Создание теста с указателями..."
mkdir -p ~/test_pointer
cd ~/test_pointer

cat > ptr.x << 'EOF'
.use GOIO

func main {
    x = 42;
    con("x = ", x);

    ! Берем адрес переменной x !
    p = &x;
    con("Pointer created");

    ! Меняем значение по указателю !
    *p = 100;

    ! Проверяем, что x изменился !
    con("x after deref = ", x);
}
EOF

echo "==> Компиляция..."
xc ptr.x -out ptr
./ptr
