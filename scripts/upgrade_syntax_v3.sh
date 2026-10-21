#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Обновление Лексера (In, Len)..."
python3 - << 'PYEOF'
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()
content = content.replace('Switch, Case, Default, Colon,', 'Switch, Case, Default, Colon, In, Len,')
content = content.replace('"switch" => Token::Switch,', '"switch" => Token::Switch, "in" => Token::In, "len" => Token::Len,')
with open('xlang-lexer/src/lib.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Обновление AST (ForIn)..."
python3 - << 'PYEOF'
with open('xlang-parser/src/ast.rs', 'r') as f:
    content = f.read()
content = content.replace(
    'Switch { expr: Expr, cases: Vec<(Expr, Vec<Stmt>)>, default: Option<Vec<Stmt>> },',
    'Switch { expr: Expr, cases: Vec<(Expr, Vec<Stmt>)>, default: Option<Vec<Stmt>> },\n    ForIn { var: String, iterable: Expr, body: Vec<Stmt> },'
)
with open('xlang-parser/src/ast.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Обновление Парсера..."
python3 - << 'PYEOF'
with open('xlang-parser/src/parser.rs', 'r') as f:
    content = f.read()

# Добавляем ForIn в парсер (перед обычным For)
old_for = '''            Token::For => {
                self.advance();
                self.match_token(Token::LParen);
                
                // Init'''
new_for = '''            Token::For => {
                self.advance();
                self.match_token(Token::LParen);
                
                // Проверка на for-in
                if let Token::Identifier(var_name) = self.current().clone() {
                    let next_tok = self.tokens[self.pos + 1].0.clone();
                    if next_tok == Token::In {
                        self.advance(); // ident
                        self.advance(); // in
                        let iterable = self.parse_expr()?;
                        self.match_token(Token::RParen);
                        let body = self.parse_block();
                        return Some(Stmt::ForIn { var: var_name, iterable, body });
                    }
                }
                
                // Init'''
content = content.replace(old_for, new_for)
with open('xlang-parser/src/parser.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 4. Обновление Sema (Анализ ForIn)..."
python3 - << 'PYEOF'
with open('xlang-parser/src/sema.rs', 'r') as f:
    content = f.read()
old_switch = '                Stmt::Switch { expr, cases, default } => {'
new_switch = '''                Stmt::ForIn { var, iterable, body } => {
                    self.visit_expr(iterable);
                    self.declared_vars.insert(var.clone());
                    self.visit_stmts(body);
                }
                Stmt::Switch { expr, cases, default } => {'''
content = content.replace(old_switch, new_switch)
with open('xlang-parser/src/sema.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 5. Обновление Кодогенератора..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 5a. Добавляем strcmp в Libc
content = content.replace("strcat: FunctionValue<'ctx>,", "strcat: FunctionValue<'ctx>, strcmp: FunctionValue<'ctx>,")
content = content.replace("strcat: module.add_function(\"strcat\",", "strcmp: module.add_function(\"strcmp\", i32_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None),\n        strcat: module.add_function(\"strcat\",")

# 5b. Добавляем сравнение строк в BinaryOp
old_binop = "            if left_val.is_int_value() && right_val.is_int_value() {"
new_binop = '''            // Сравнение строк
            if left_val.is_pointer_value() && right_val.is_pointer_value() && (op == "==" || op == "!=") {
                let l_ptr = left_val.into_pointer_value();
                let r_ptr = right_val.into_pointer_value();
                let cmp_res = builder.build_call(libc.strcmp, &[l_ptr.into(), r_ptr.into()], "strcmp").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let zero = i32_type.const_zero();
                let bool_val = if op == "==" {
                    builder.build_int_compare(IntPredicate::EQ, cmp_res, zero, "str_eq").unwrap()
                } else {
                    builder.build_int_compare(IntPredicate::NE, cmp_res, zero, "str_ne").unwrap()
                };
                return bool_val.into();
            }
            
            if left_val.is_int_value() && right_val.is_int_value() {'''
content = content.replace(old_binop, new_binop)

# 5c. Добавляем len в gen_expr
old_call = '''            match name.as_str() {
                "con" => {'''
new_call = '''            match name.as_str() {
                "len" => {
                    if args.len() == 1 {
                        if let ast::Expr::Identifier(name) = &args[0] {
                            if let Some(VarInfo::Array(_, len)) = vars.get(name) {
                                return i64_type.const_int(*len as u64, false).into();
                            } else if let Some(VarInfo::IntArray(_, len)) = vars.get(name) {
                                return i64_type.const_int(*len as u64, false).into();
                            } else if let Some(VarInfo::String(ptr)) = vars.get(name) {
                                let s_ptr = builder.build_load(i8_ptr_type, *ptr, "s").unwrap().into_pointer_value();
                                let len = builder.build_call(libc.strlen, &[s_ptr.into()], "strlen").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                                return len.into();
                            }
                        }
                    }
                    i64_type.const_int(0, false).into()
                }
                "con" => {'''
content = content.replace(old_call, new_call)

# 5d. Добавляем ForIn в gen_stmt
old_switch = '        ast::Stmt::Switch { expr, cases, default } => {'
new_switch = '''        ast::Stmt::ForIn { var, iterable, body } => {
            let (arr_ptr, arr_len, is_int_arr) = match iterable {
                ast::Expr::Identifier(name) => {
                    match vars.get(name) {
                        Some(VarInfo::Array(ptr, len)) => (*ptr, *len, false),
                        Some(VarInfo::IntArray(ptr, len)) => (*ptr, *len, true),
                        _ => panic!("For-in ожидает переменную-массив")
                    }
                },
                _ => panic!("For-in ожидает переменную-массив")
            };
            
            let idx_alloca = builder.build_alloca(i64_type, "for_in_idx").unwrap();
            builder.build_store(idx_alloca, i64_type.const_zero()).unwrap();
            
            let cond_bb = context.append_basic_block(current_fn, "for_in_cond");
            let body_bb = context.append_basic_block(current_fn, "for_in_body");
            let after_bb = context.append_basic_block(current_fn, "for_in_after");
            
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            
            let current_idx = builder.build_load(i64_type, idx_alloca, "idx").unwrap().into_int_value();
            let len_val = i64_type.const_int(arr_len as u64, false);
            let cmp = builder.build_int_compare(IntPredicate::SLT, current_idx, len_val, "for_in_cmp").unwrap();
            builder.build_conditional_branch(cmp, body_bb, after_bb).unwrap();
            
            builder.position_at_end(body_bb);
            let idx_i32 = builder.build_int_truncate(current_idx, i32_type, "idx_i32").unwrap();
            
            let elem_val = if is_int_arr {
                let gep = unsafe { builder.build_gep(i64_type.array_type(arr_len), arr_ptr, &[i32_type.const_zero(), idx_i32], "gep").unwrap() };
                builder.build_load(i64_type, gep, "elem").unwrap()
            } else {
                let gep = unsafe { builder.build_gep(f64_type.array_type(arr_len), arr_ptr, &[i32_type.const_zero(), idx_i32], "gep").unwrap() };
                builder.build_load(f64_type, gep, "elem").unwrap()
            };
            
            let var_alloca = if let Some(info) = vars.get(var) {
                match info {
                    VarInfo::Scalar(p) => *p,
                    VarInfo::Int(p) => *p,
                    _ => panic!("Несовпадение типов переменной цикла")
                }
            } else {
                let ptr = if is_int_arr {
                    builder.build_alloca(i64_type, var).unwrap()
                } else {
                    builder.build_alloca(f64_type, var).unwrap()
                };
                if is_int_arr {
                    vars.insert(var.clone(), VarInfo::Int(ptr));
                } else {
                    vars.insert(var.clone(), VarInfo::Scalar(ptr));
                }
                ptr
            };
            builder.build_store(var_alloca, elem_val).unwrap();
            
            loop_stack.push((cond_bb, after_bb));
            for s in body {
                if builder.get_insert_block().unwrap().get_terminator().is_none() {
                    gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack);
                }
            }
            loop_stack.pop();
            
            if builder.get_insert_block().unwrap().get_terminator().is_none() {
                let next_idx = builder.build_int_add(current_idx, i64_type.const_int(1, false), "next_idx").unwrap();
                builder.build_store(idx_alloca, next_idx).unwrap();
                builder.build_unconditional_branch(cond_bb).unwrap();
            }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::Switch { expr, cases, default } => {'''
content = content.replace(old_switch, new_switch)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 6. Пересборка компилятора..."
cargo build --release -p xlang-lexer
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 7. Тестирование новых фич..."
mkdir -p /tmp/test_v3
cd /tmp/test_v3

cat > test.x << 'XLANG'
.use GOIO

func main {
    con("=== Test 1: For-in loop ===");
    numbers = [10, 20, 30, 40];
    sum = 0;
    for (num in numbers) {
        con("Number: ", num);
        sum = sum + num;
    }
    con("Sum: ", sum);

    con("\n=== Test 2: String comparison ===");
    password = "secret";
    if (password == "secret") {
        con("Access granted!");
    } else {
        con("Access denied!");
    }

    con("\n=== Test 3: len() function ===");
    name = "X-lang";
    con("Length of string: ", len(name));
    con("Length of array: ", len(numbers));
}
XLANG

xc test.x -out test_bin
./test_bin
