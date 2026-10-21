#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление условий If и While (int/float)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Исправляем If
old_if = """        ast::Stmt::If { condition, then_branch, else_branch } => {
            let left = gen_expr(context, builder, module, &condition.0, aliases, user_functions, libc, vars).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, aliases, user_functions, libc, vars).into_float_value();
            
            let cmp = match condition.1.as_str() {
                "==" => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
                "!=" => builder.build_float_compare(FloatPredicate::ONE, left, right, "cmp").unwrap(),
                "<" => builder.build_float_compare(FloatPredicate::OLT, left, right, "cmp").unwrap(),
                ">" => builder.build_float_compare(FloatPredicate::OGT, left, right, "cmp").unwrap(),
                "<=" => builder.build_float_compare(FloatPredicate::OLE, left, right, "cmp").unwrap(),
                ">=" => builder.build_float_compare(FloatPredicate::OGE, left, right, "cmp").unwrap(),
                _ => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
            };"""

new_if = """        ast::Stmt::If { condition, then_branch, else_branch } => {
            let left = gen_expr(context, builder, module, &condition.0, aliases, user_functions, libc, vars);
            let right = gen_expr(context, builder, module, &condition.2, aliases, user_functions, libc, vars);
            
            let cmp = if left.is_int_value() && right.is_int_value() {
                let l = left.into_int_value(); let r = right.into_int_value();
                match condition.1.as_str() {
                    "==" => builder.build_int_compare(IntPredicate::EQ, l, r, "cmp").unwrap(),
                    "!=" => builder.build_int_compare(IntPredicate::NE, l, r, "cmp").unwrap(),
                    "<" => builder.build_int_compare(IntPredicate::SLT, l, r, "cmp").unwrap(),
                    ">" => builder.build_int_compare(IntPredicate::SGT, l, r, "cmp").unwrap(),
                    "<=" => builder.build_int_compare(IntPredicate::SLE, l, r, "cmp").unwrap(),
                    ">=" => builder.build_int_compare(IntPredicate::SGE, l, r, "cmp").unwrap(),
                    _ => builder.build_int_compare(IntPredicate::EQ, l, r, "cmp").unwrap(),
                }
            } else {
                let l = match left { BasicValueEnum::FloatValue(f) => f, BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(), _ => panic!() };
                let r = match right { BasicValueEnum::FloatValue(f) => f, BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(), _ => panic!() };
                match condition.1.as_str() {
                    "==" => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                    "!=" => builder.build_float_compare(FloatPredicate::ONE, l, r, "cmp").unwrap(),
                    "<" => builder.build_float_compare(FloatPredicate::OLT, l, r, "cmp").unwrap(),
                    ">" => builder.build_float_compare(FloatPredicate::OGT, l, r, "cmp").unwrap(),
                    "<=" => builder.build_float_compare(FloatPredicate::OLE, l, r, "cmp").unwrap(),
                    ">=" => builder.build_float_compare(FloatPredicate::OGE, l, r, "cmp").unwrap(),
                    _ => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                }
            };"""

content = content.replace(old_if, new_if)

# 2. Исправляем While
old_while = """        ast::Stmt::While { condition, body } => {
            let cond_bb = context.append_basic_block(current_fn, "while_cond");
            let loop_bb = context.append_basic_block(current_fn, "while_body");
            let after_bb = context.append_basic_block(current_fn, "while_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            let left = gen_expr(context, builder, module, &condition.0, aliases, user_functions, libc, vars).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, aliases, user_functions, libc, vars).into_float_value();
            let cmp = match condition.1.as_str() {
                "==" => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
                "!=" => builder.build_float_compare(FloatPredicate::ONE, left, right, "cmp").unwrap(),
                "<" => builder.build_float_compare(FloatPredicate::OLT, left, right, "cmp").unwrap(),
                ">" => builder.build_float_compare(FloatPredicate::OGT, left, right, "cmp").unwrap(),
                "<=" => builder.build_float_compare(FloatPredicate::OLE, left, right, "cmp").unwrap(),
                ">=" => builder.build_float_compare(FloatPredicate::OGE, left, right, "cmp").unwrap(),
                _ => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
            };"""

new_while = """        ast::Stmt::While { condition, body } => {
            let cond_bb = context.append_basic_block(current_fn, "while_cond");
            let loop_bb = context.append_basic_block(current_fn, "while_body");
            let after_bb = context.append_basic_block(current_fn, "while_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            let left = gen_expr(context, builder, module, &condition.0, aliases, user_functions, libc, vars);
            let right = gen_expr(context, builder, module, &condition.2, aliases, user_functions, libc, vars);
            let cmp = if left.is_int_value() && right.is_int_value() {
                let l = left.into_int_value(); let r = right.into_int_value();
                match condition.1.as_str() {
                    "==" => builder.build_int_compare(IntPredicate::EQ, l, r, "cmp").unwrap(),
                    "!=" => builder.build_int_compare(IntPredicate::NE, l, r, "cmp").unwrap(),
                    "<" => builder.build_int_compare(IntPredicate::SLT, l, r, "cmp").unwrap(),
                    ">" => builder.build_int_compare(IntPredicate::SGT, l, r, "cmp").unwrap(),
                    "<=" => builder.build_int_compare(IntPredicate::SLE, l, r, "cmp").unwrap(),
                    ">=" => builder.build_int_compare(IntPredicate::SGE, l, r, "cmp").unwrap(),
                    _ => builder.build_int_compare(IntPredicate::EQ, l, r, "cmp").unwrap(),
                }
            } else {
                let l = match left { BasicValueEnum::FloatValue(f) => f, BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(), _ => panic!() };
                let r = match right { BasicValueEnum::FloatValue(f) => f, BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(), _ => panic!() };
                match condition.1.as_str() {
                    "==" => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                    "!=" => builder.build_float_compare(FloatPredicate::ONE, l, r, "cmp").unwrap(),
                    "<" => builder.build_float_compare(FloatPredicate::OLT, l, r, "cmp").unwrap(),
                    ">" => builder.build_float_compare(FloatPredicate::OGT, l, r, "cmp").unwrap(),
                    "<=" => builder.build_float_compare(FloatPredicate::OLE, l, r, "cmp").unwrap(),
                    ">=" => builder.build_float_compare(FloatPredicate::OGE, l, r, "cmp").unwrap(),
                    _ => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                }
            };"""

content = content.replace(old_while, new_while)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка компилятора..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск оставшихся тестов (7-15)..."
bash /tmp/finish_all_tests.sh
