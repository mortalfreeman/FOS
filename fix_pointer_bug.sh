#!/bin/bash
set -e
cd ~/FOS

echo "==> Исправление обработки указателей в кодогенераторе..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Исправляем присваивание (Stmt::Assign)
old_assign = """            } else {
                let val = gen_expr(context, builder, module, value, user_functions, xstd, vars);
                if val.is_pointer_value() {
                    let alloca = if let Some(VarInfo::String(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::String(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else {
                    let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(f64_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Scalar(ptr)); ptr };
                    builder.build_store(alloca, val.into_float_value()).unwrap();
                }
            }"""
new_assign = """            } else {
                let val = gen_expr(context, builder, module, value, user_functions, xstd, vars);
                if val.is_pointer_value() {
                    let alloca = if let Some(info) = vars.get(name) {
                        match info { VarInfo::String(ptr) => *ptr, _ => panic!("Type mismatch: variable '{}' was number, now string", name) }
                    } else {
                        let ptr = builder.build_alloca(i8_ptr_type, name).unwrap();
                        vars.insert(name.clone(), VarInfo::String(ptr));
                        ptr
                    };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else {
                    let alloca = if let Some(info) = vars.get(name) {
                        match info { VarInfo::Scalar(ptr) => *ptr, _ => panic!("Type mismatch: variable '{}' was string, now number", name) }
                    } else {
                        let ptr = builder.build_alloca(f64_type, name).unwrap();
                        vars.insert(name.clone(), VarInfo::Scalar(ptr));
                        ptr
                    };
                    builder.build_store(alloca, val.into_float_value()).unwrap();
                }
            }"""
content = content.replace(old_assign, new_assign)

# 2. Исправляем print_num и print_str в блоке con()
old_con = """                        _ => {
                                let val = gen_expr(context, builder, module, arg, user_functions, xstd, vars);
                                if val.is_pointer_value() {
                                    builder.build_call(xstd.print_str, &[val.into()], "print_str").unwrap();
                                } else {
                                    builder.build_call(xstd.print_num, &[val.into()], "print_num").unwrap();
                                }
                            }"""
new_con = """                        _ => {
                                let val = gen_expr(context, builder, module, arg, user_functions, xstd, vars);
                                if val.is_pointer_value() {
                                    builder.build_call(xstd.print_str, &[val.into()], "print_str").unwrap();
                                } else {
                                    // Если это число (FloatValue)
                                    let f_val = val.into_float_value();
                                    builder.build_call(xstd.print_num, &[f_val.into()], "print_num").unwrap();
                                }
                            }"""
content = content.replace(old_con, new_con)

# 3. Убираем вызовы into_float_value для переменных, чтобы не было паники
old_ident = """        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { 
                match info { 
                    VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), 
                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => f64_type.const_float(0.0).into() 
                } 
            } else { f64_type.const_float(0.0).into() } 
        }"""
new_ident = """        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { 
                match info { 
                    VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), 
                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => panic!("Unsupported variable type for '{}'", name)
                } 
            } else { f64_type.const_float(0.0).into() } 
        }"""
content = content.replace(old_ident, new_ident)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_zero_full
xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
