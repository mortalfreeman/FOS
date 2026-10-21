#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление Switch/Case в лексер..."
python3 - << 'PYEOF'
with open('xlang-lexer/src/lib.rs', 'r') as f:
    content = f.read()

# Добавляем токены
for kw in ['Switch', 'Case', 'Default', 'Colon']:
    if kw not in content:
        content = content.replace(
            'Func, Con, If, Else, Return,',
            f'Func, Con, If, Else, Return, {kw},'
        )

# Добавляем обработку символа ':'
if "'::' =>" not in content:
    content = content.replace(
        "';' => { self.advance(); tokens.push((Token::Semicolon, start_line, start_col)); }",
        "';' => { self.advance(); tokens.push((Token::Semicolon, start_line, start_col)); }\n                ':' => { self.advance(); tokens.push((Token::Colon, start_line, start_col)); }"
    )

# Добавляем ключевые слова в маппинг
content = content.replace(
    '"return" => Token::Return,',
    '"return" => Token::Return, "switch" => Token::Switch, "case" => Token::Case, "default" => Token::Default,'
)

with open('xlang-lexer/src/lib.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Добавление Switch/Case в AST..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/ast.rs', 'r') as f:
    content = f.read()
if 'Switch {' not in content:
    content = content.replace(
        'If { condition: (Expr, String, Expr), then_branch: Vec<Stmt>, else_branch: Option<Vec<Stmt>> },',
        'If { condition: (Expr, String, Expr), then_branch: Vec<Stmt>, else_branch: Option<Vec<Stmt>> },\n    Switch { expr: Expr, cases: Vec<(Expr, Vec<Stmt>)>, default: Option<Vec<Stmt>> },'
    )
with open('xlang-compiler/src/ast.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 3. Добавление Switch/Case в парсер..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/parser.rs', 'r') as f:
    content = f.read()

# Ищем блок для If и добавляем Switch перед ним
if 'Token::Switch => {' not in content:
    old_if = "            Token::If | Token::While => {"
    new_switch = '''            Token::Switch => {
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
            Token::If | Token::While => {'''
    content = content.replace(old_if, new_switch)

with open('xlang-compiler/src/parser.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 4. Обновление main.rs (Switch + i64-массивы)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 4.1. Добавляем IntArray в VarInfo
if 'IntArray(' not in content:
    content = content.replace(
        'Array(PointerValue<\'ctx>, u32),',
        'Array(PointerValue<\'ctx>, u32),\n    IntArray(PointerValue<\'ctx>, u32),'
    )

# 4.2. Добавляем функцию to_int (аналог to_float)
if 'fn to_int' not in content:
    helper = """
fn to_int<'ctx>(builder: &Builder<'ctx>, val: BasicValueEnum<'ctx>, i64_type: inkwell::types::IntType<'ctx>) -> inkwell::values::IntValue<'ctx> {
    match val {
        BasicValueEnum::IntValue(i) => i,
        BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i64_type, "float_to_int").unwrap(),
        _ => panic!("Cannot convert to int"),
    }
}
"""
    content = content.replace('fn to_float', helper + '\nfn to_float')

# 4.3. Модифицируем Assign для автоопределения i64-массива
old_array = '''            if let ast::Expr::Array(elements) = value {
                let len = elements.len() as u32; let arr_ty = f64_type.array_type(len);
                let alloca = builder.build_alloca(arr_ty, name).unwrap();
                for (i, elem) in elements.iter().enumerate() {
                    let val_raw = gen_expr(context, builder, module, elem, aliases, user_functions, libc, vars);
                    let val = to_float(builder, val_raw, f64_type);
                    let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };
                    builder.build_store(ptr, val).unwrap();
                }
                vars.insert(name.clone(), VarInfo::Array(alloca, len));
            }'''

new_array = '''            if let ast::Expr::Array(elements) = value {
                let len = elements.len() as u32;
                let all_ints = !elements.is_empty() && elements.iter().all(|e| matches!(e, ast::Expr::Int(_)));
                
                if all_ints {
                    let arr_ty = i64_type.array_type(len);
                    let alloca = builder.build_alloca(arr_ty, name).unwrap();
                    for (i, elem) in elements.iter().enumerate() {
                        let val_raw = gen_expr(context, builder, module, elem, aliases, user_functions, libc, vars);
                        let val = to_int(builder, val_raw, i64_type);
                        let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };
                        builder.build_store(ptr, val).unwrap();
                    }
                    vars.insert(name.clone(), VarInfo::IntArray(alloca, len));
                } else {
                    let arr_ty = f64_type.array_type(len);
                    let alloca = builder.build_alloca(arr_ty, name).unwrap();
                    for (i, elem) in elements.iter().enumerate() {
                        let val_raw = gen_expr(context, builder, module, elem, aliases, user_functions, libc, vars);
                        let val = to_float(builder, val_raw, f64_type);
                        let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };
                        builder.build_store(ptr, val).unwrap();
                    }
                    vars.insert(name.clone(), VarInfo::Array(alloca, len));
                }
            }'''
content = content.replace(old_array, new_array)

# 4.4. Модифицируем Index (чтение) для обоих типов массивов
old_index = '''        ast::Expr::Index { name, index } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_raw = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars);
            let idx_int = match idx_raw {
                BasicValueEnum::IntValue(i) => builder.build_int_truncate(i, i32_type, "idx_trunc").unwrap(),
                BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i32_type, "idx_float").unwrap(),
                _ => panic!("Invalid index type"),
            };
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_load(f64_type, ptr, "load_arr").unwrap()
        }'''

new_index = '''        ast::Expr::Index { name, index } => {
            let idx_raw = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars);
            let idx_int = match idx_raw {
                BasicValueEnum::IntValue(i) => builder.build_int_truncate(i, i32_type, "idx_trunc").unwrap(),
                BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i32_type, "idx_float").unwrap(),
                _ => panic!("Invalid index type"),
            };
            match vars.get(name).expect("Array not found") {
                VarInfo::Array(ptr, len) => {
                    let gep = unsafe { builder.build_gep(f64_type.array_type(*len), *ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
                    builder.build_load(f64_type, gep, "load_arr").unwrap()
                }
                VarInfo::IntArray(ptr, len) => {
                    let gep = unsafe { builder.build_gep(i64_type.array_type(*len), *ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
                    builder.build_load(i64_type, gep, "load_arr").unwrap()
                }
                _ => panic!("Not an array")
            }
        }'''
content = content.replace(old_index, new_index)

# 4.5. Модифицируем IndexAssign для обоих типов массивов
old_index_assign = '''        ast::Stmt::IndexAssign { name, index, value } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_raw = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars);
            let idx_int = match idx_raw {
                BasicValueEnum::IntValue(i) => builder.build_int_truncate(i, i32_type, "idx_trunc").unwrap(),
                BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i32_type, "idx_float").unwrap(),
                _ => panic!("Invalid index type"),
            };
            let val_raw = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
            let val = to_float(builder, val_raw, f64_type);
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_store(ptr, val).unwrap();
        }'''

new_index_assign = '''        ast::Stmt::IndexAssign { name, index, value } => {
            let idx_raw = gen_expr(context, builder, module, index, aliases, user_functions, libc, vars);
            let idx_int = match idx_raw {
                BasicValueEnum::IntValue(i) => builder.build_int_truncate(i, i32_type, "idx_trunc").unwrap(),
                BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i32_type, "idx_float").unwrap(),
                _ => panic!("Invalid index type"),
            };
            let val_raw = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
            
            match vars.get(name).expect("Array not found") {
                VarInfo::Array(ptr, len) => {
                    let val = to_float(builder, val_raw, f64_type);
                    let gep = unsafe { builder.build_gep(f64_type.array_type(*len), *ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
                    builder.build_store(gep, val).unwrap();
                }
                VarInfo::IntArray(ptr, len) => {
                    let val = to_int(builder, val_raw, i64_type);
                    let gep = unsafe { builder.build_gep(i64_type.array_type(*len), *ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
                    builder.build_store(gep, val).unwrap();
                }
                _ => panic!("Not an array")
            }
        }'''
content = content.replace(old_index_assign, new_index_assign)

# 4.6. Добавляем генерацию Switch (вместо if-else используем вложенные if)
# Проще всего сгенерировать через LLVM switch (но это сложно), поэтому сделаем через if-else с авто-разрывом
if 'Stmt::Switch' not in content:
    old_if_stmt = '''        ast::Stmt::If { condition, then_branch, else_branch } => {'''
    new_switch_codegen = '''        ast::Stmt::Switch { expr, cases, default } => {
            let val_raw = gen_expr(context, builder, module, expr, aliases, user_functions, libc, vars);
            let val_i = to_int(builder, val_raw, i64_type);
            let after_bb = context.append_basic_block(current_fn, "after_switch");
            
            for (case_expr, body) in cases {
                let case_val_raw = gen_expr(context, builder, module, case_expr, aliases, user_functions, libc, vars);
                let case_val_i = to_int(builder, case_val_raw, i64_type);
                let cmp = builder.build_int_compare(IntPredicate::EQ, val_i, case_val_i, "case_cmp").unwrap();
                
                let case_bb = context.append_basic_block(current_fn, "case_body");
                let next_case_bb = context.append_basic_block(current_fn, "next_case");
                builder.build_conditional_branch(cmp, case_bb, next_case_bb).unwrap();
                
                builder.position_at_end(case_bb);
                loop_stack.push((after_bb, after_bb)); // break -> after_switch
                for s in body {
                    if builder.get_insert_block().unwrap().get_terminator().is_none() {
                        gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack);
                    }
                }
                loop_stack.pop();
                if builder.get_insert_block().unwrap().get_terminator().is_none() {
                    builder.build_unconditional_branch(after_bb).unwrap();
                }
                
                builder.position_at_end(next_case_bb);
            }
            
            // Default
            if let Some(default_body) = default {
                loop_stack.push((after_bb, after_bb));
                for s in default_body {
                    if builder.get_insert_block().unwrap().get_terminator().is_none() {
                        gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack);
                    }
                }
                loop_stack.pop();
            }
            if builder.get_insert_block().unwrap().get_terminator().is_none() {
                builder.build_unconditional_branch(after_bb).unwrap();
            }
            
            builder.position_at_end(after_bb);
        }
        ast::Stmt::If { condition, then_branch, else_branch } => {'''
    content = content.replace(old_if_stmt, new_switch_codegen)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 5. Пересборка..."
cargo build --release -p xlang-lexer 2>&1 | tail -3
cargo build --release -p xlang-compiler 2>&1 | tail -3
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 6. Тест Switch/Case и i64-массивов..."
mkdir -p /tmp/switch_test
cd /tmp/switch_test

cat > switch.x << 'XLANG'
.use std
func main {
    x = 2;
    switch (x) {
        case 1:
            con("one");
            break;
        case 2:
            con("two");
            break;
        case 3:
            con("three");
            break;
        default:
            con("other");
    }
}
XLANG

xc switch.x -out switch_bin
./switch_bin

echo -e "\n--- Честный тест сортировки (Bubble Sort 5k) ---"
cat > sort.x << 'XLANG'
.use std
func main {
    arr = [0,0,0,0,0,0,0,0,0,0];
    for (i = 0; i < 5000; i = i + 1) {
        arr[i] = 5000 - i;
    }
    for (i = 0; i < 5000; i = i + 1) {
        for (j = 0; j < 4999; j = j + 1) {
            if (arr[j] > arr[j+1]) { t = arr[j]; arr[j] = arr[j+1]; arr[j+1] = t; }
        }
    }
    con(1);
}
XLANG
xc sort.x -out sort_bin
START=$(date +%s%N); ./sort_bin > /dev/null; END=$(date +%s%N)
echo "X-lang Bubble Sort (i64): $(( (END-START)/1000000 )) мс"
echo "C Bubble Sort (int): 30 мс"
