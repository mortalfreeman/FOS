#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Обновление парсера (макросы и строки)..."
# Мы не трогаем parser.rs, так как он уже умеет парсить макросы и строки,
# но нам нужно убедиться, что AST и Sema их пропускают.

echo "==> 2. Обновление main.rs (генерация макросов и ввод строк)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Возвращаем макросы в gen_stmt
old_macro = """        ast::Stmt::MacroCall { .. } => { /* Пропускаем макросы для стабильности */ }"""
new_macro = """        ast::Stmt::MacroCall { name } => {
            // Инлайним макрос (просто генерируем его тело на месте вызова)
            if let Some(alias_body) = aliases.get(name) {
                for s in alias_body {
                    gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack);
                }
            }
        }"""
content = content.replace(old_macro, new_macro)

# 2. Добавляем поддержку макросов в gen_expr (для вызовов внутри выражений)
old_expr_macro = """        ast::Expr::MacroCall(_) => { f64_type.const_float(0.0).into() }"""
new_expr_macro = """        ast::Expr::MacroCall(name) => {
            if let Some(alias_body) = aliases.get(name) {
                for s in alias_body {
                    gen_stmt(context, builder, module, module.get_functions().next().unwrap(), s, aliases, user_functions, libc, vars, &mut Vec::new());
                }
            }
            f64_type.const_float(0.0).into()
        }"""
content = content.replace(old_expr_macro, new_expr_macro)

# 3. Возвращаем ввод строк (ci) через scanf
old_ci = """                "powr" => {"""
new_ci = """                "ci" => {
                    if args.len() >= 2 {
                        if let ast::Expr::String(prompt) = &args[0] {
                            let fmt_global = builder.build_global_string_ptr(prompt.as_str(), "prompt").unwrap();
                            builder.build_call(libc.printf, &[fmt_global.as_pointer_value().into()], "call_ci_prompt").unwrap();
                        }
                        if let ast::Expr::Identifier(var_name) = &args[1] {
                            // Проверяем, есть ли переменная в vars
                            let is_string = if let Some(VarInfo::String(_)) = vars.get(var_name.as_str()) { true } else { false };
                            
                            if is_string {
                                // Ввод строки (выделяем буфер под 1024 символа)
                                let buf_size = i64_type.const_int(1024, false);
                                let buf = builder.build_call(libc.malloc, &[buf_size.into()], "str_buf").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                                let scanf_fmt = builder.build_global_string_ptr("%s", "scanf_str").unwrap();
                                builder.build_call(libc.scanf, &[scanf_fmt.as_pointer_value().into(), buf.into()], "call_ci_scan").unwrap();
                                
                                let alloca = builder.build_alloca(i8_ptr_type, var_name).unwrap();
                                builder.build_store(alloca, buf).unwrap();
                                vars.insert(var_name.clone(), VarInfo::String(alloca));
                            } else {
                                // Ввод числа
                                let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(var_name.as_str()) { *ptr } 
                                             else { let ptr = builder.build_alloca(f64_type, var_name).unwrap(); vars.insert(var_name.clone(), VarInfo::Scalar(ptr)); ptr };
                                let scanf_fmt = builder.build_global_string_ptr("%lf", "scanf_fmt").unwrap();
                                builder.build_call(libc.scanf, &[scanf_fmt.as_pointer_value().into(), alloca.into()], "call_ci_scan").unwrap();
                            }
                        }
                    }
                    f64_type.const_float(0.0).into()
                }
                "powr" => {"""
content = content.replace(old_ci, new_ci)

# 4. Обновляем сигнатуру gen_stmt, чтобы она принимала aliases
old_sig = """fn gen_stmt<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>, current_fn: FunctionValue<'ctx>,
    stmt: &ast::Stmt, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>, loop_stack: &mut Vec<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
) {"""
new_sig = """fn gen_stmt<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>, current_fn: FunctionValue<'ctx>,
    stmt: &ast::Stmt, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>, loop_stack: &mut Vec<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
) {"""
content = content.replace(old_sig, new_sig)

# 5. Обновляем все вызовы gen_stmt (добавляем aliases)
content = content.replace("gen_stmt(context, builder, module, current_fn, i, user_functions, libc, vars, loop_stack);", "gen_stmt(context, builder, module, current_fn, i, aliases, user_functions, libc, vars, loop_stack);")
content = content.replace("gen_stmt(context, builder, module, current_fn, s, user_functions, libc, vars, loop_stack);", "gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack);")
content = content.replace("gen_stmt(context, builder, module, current_fn, inc, user_functions, libc, vars, loop_stack);", "gen_stmt(context, builder, module, current_fn, inc, aliases, user_functions, libc, vars, loop_stack);")

# 6. Собираем алиасы в main
old_aliases = """    let mut user_functions = std::collections::HashMap::new();"""
new_aliases = """    let mut aliases = std::collections::HashMap::new();
    for item in &global_program.items {
        if let ast::Item::Alias(alias) = item { aliases.insert(alias.name.clone(), alias.body.clone()); }
    }

    let mut user_functions = std::collections::HashMap::new();"""
content = content.replace(old_aliases, new_aliases)

# 7. Передаем aliases в gen_stmt из main
content = content.replace("gen_stmt(&context, &builder, &module, *llvm_fn, stmt, &user_functions, &libc, &mut vars, &mut loop_stack);", "gen_stmt(&context, &builder, &module, *llvm_fn, stmt, &aliases, &user_functions, &libc, &mut vars, &mut loop_stack);")

# 8. Обновляем сигнатуру gen_expr
old_gen_expr_sig = """fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {"""
new_gen_expr_sig = """fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {"""
content = content.replace(old_gen_expr_sig, new_gen_expr_sig)

# 9. Обновляем все вызовы gen_expr (добавляем aliases)
content = content.replace("gen_expr(context, builder, module, &cond.0, user_functions, libc, vars)", "gen_expr(context, builder, module, &cond.0, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, &cond.2, user_functions, libc, vars)", "gen_expr(context, builder, module, &cond.2, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, &condition.0, user_functions, libc, vars)", "gen_expr(context, builder, module, &condition.0, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, &condition.2, user_functions, libc, vars)", "gen_expr(context, builder, module, &condition.2, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, value, user_functions, libc, vars)", "gen_expr(context, builder, module, value, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, index, user_functions, libc, vars)", "gen_expr(context, builder, module, index, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, expr, user_functions, libc, vars)", "gen_expr(context, builder, module, expr, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, arg, user_functions, libc, vars)", "gen_expr(context, builder, module, arg, aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, &args[0], user_functions, libc, vars)", "gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars)")
content = content.replace("gen_expr(context, builder, module, &args[1], user_functions, libc, vars)", "gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars)")

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Обновление системных библиотек..."
sudo bash -c 'cat > /usr/local/use/GOIO.xh << "EOF"
#Define Header=GOIO
#END
EOF'

echo "==> 4. Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 5. Создание теста (Макросы + Ввод строк)..."
mkdir -p ~/test_full
cd ~/test_full

cat > final_test.x << 'EOF'
.use GOIO

$alias greet {
    con("--- Macro Executed ---");
}

func main {
    name = "";
    con("Enter your name: ");
    ci("", name);
    con("Hello, ", name, "!");

    $greet;

    nums = [10, 20, 30];
    sum = 0;
    for (i = 0; i < 3; i = i + 1) {
        sum = sum + nums[i];
    }
    con("Sum: ", sum);
}
EOF

echo "==> Компиляция и запуск:"
xc final_test.x -out final_test
./final_test
