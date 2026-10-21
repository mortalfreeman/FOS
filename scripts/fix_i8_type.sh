#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление i8_type в gen_expr..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Находим начало функции gen_expr и добавляем i8_type
old_start = """fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());"""

new_start = """fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_type = context.i8_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());"""

content = content.replace(old_start, new_start)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Тест FILEMAN..."
mkdir -p /tmp/fileman_test
cd /tmp/fileman_test

cat > test_file.x << 'XLANG'
.use std
.use fileman

func main {
    con("=== FILEMAN TEST ===");
    
    file-new("test", "txt", "Hello, FILEMAN!\nThis is a new line.");
    con("File 'test.txt' created.");
    
    content = file-read("./", "test.txt");
    con("Content read from file:");
    con(content);
    
    f = file-open("test.txt");
    file-write(f, "\nAppended line.");
    file-close(f);
    con("Appended text.");
    
    content2 = file-read("./", "test.txt");
    con("Updated content:");
    con(content2);
}
XLANG

xc test_file.x -out test_file
./test_file

echo ""
echo "=== Содержимое test.txt ==="
cat test.txt
