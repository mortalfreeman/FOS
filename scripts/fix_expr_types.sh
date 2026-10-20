#!/bin/bash
set -e
cd ~/FOS

echo "==> Полная перезапись gen_expr (корректная работа с типами)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# Находим начало функции gen_expr и заменяем всё до конца функции
start_marker = "fn gen_expr<'ctx>("
end_marker = "\nfn resolve_project_files"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("ERROR: Не удалось найти границы gen_expr")
    exit(1)

new_gen_expr = '''fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    xstd: &Xstd<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());
    
    match expr {
        ast::Expr::Int(n) => f64_type.const_float(*n as f64).into(),
        ast::Expr::Float(f) => f64_type.const_float(*f).into(),
        ast::Expr::String(s) => { let str_val = builder.build_global_string_ptr(s, "str").unwrap(); str_val.as_pointer_value().into() }
        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { 
                match info { 
                    VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), 
                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => panic!("Unsupported variable type for '{}'", name)
                } 
            } else { f64_type.const_float(0.0).into() } 
        }
        ast::Expr::Index { name, index } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_val = gen_expr(context, builder, module, index, user_functions, xstd, vars).into_float_value();
            let idx_int = builder.build_float_to_signed_int(idx_val, i32_type, "idx").unwrap();
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_load(f64_type, ptr, "load_arr").unwrap()
        }
        ast::Expr::Array(_) => { f64_type.const_float(0.0).into() }
        ast::Expr::BinaryOp { left, op, right } => {
            let left_val = gen_expr(context, builder, module, left, user_functions, xstd, vars);
            let right_val = gen_expr(context, builder, module, right, user_functions, xstd, vars);
            
            // Если оба указатели и это '+', то конкатенация строк
            if left_val.is_pointer_value() && right_val.is_pointer_value() && op == "+" {
                let l_ptr = left_val.into_pointer_value();
                let r_ptr = right_val.into_pointer_value();
                let l_len = builder.build_call(xstd.strlen, &[l_ptr.into()], "l_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let r_len = builder.build_call(xstd.strlen, &[r_ptr.into()], "r_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let total_len = builder.build_int_add(l_len, r_len, "total").unwrap();
                let total_len = builder.build_int_add(total_len, i64_type.const_int(1, false), "total1").unwrap();
                let new_buf = builder.build_call(xstd.malloc, &[total_len.into()], "malloc_str").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                builder.build_call(xstd.strcpy, &[new_buf.into(), l_ptr.into()], "strcpy").unwrap();
                builder.build_call(xstd.strcat, &[new_buf.into(), r_ptr.into()], "strcat").unwrap();
                return new_buf.into();
            }

            // Иначе это арифметика
            let l_f = match left_val {
                BasicValueEnum::FloatValue(f) => f,
                BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(),
                _ => panic!("Expected number for arithmetic, got pointer"),
            };
            let r_f = match right_val {
                BasicValueEnum::FloatValue(f) => f,
                BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(),
                _ => panic!("Expected number for arithmetic, got pointer"),
            };
            
            match op.as_str() {
                "+" => builder.build_float_add(l_f, r_f, "addtmp").unwrap().into(),
                "-" => builder.build_float_sub(l_f, r_f, "subtmp").unwrap().into(),
                "*" => builder.build_float_mul(l_f, r_f, "multmp").unwrap().into(),
                "/" => builder.build_float_div(l_f, r_f, "divtmp").unwrap().into(),
                _ => f64_type.const_float(0.0).into(),
            }
        }
        ast::Expr::MacroCall(_) => { f64_type.const_float(0.0).into() }
        ast::Expr::Call { name, args } => {
            if let Some((llvm_fn, _)) = user_functions.get(name) {
                let mut llvm_args = Vec::new();
                for arg in args {
                    let val = gen_expr(context, builder, module, arg, user_functions, xstd, vars);
                    let f_val = match val {
                        BasicValueEnum::FloatValue(f) => f,
                        BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(),
                        _ => f64_type.const_float(0.0),
                    };
                    llvm_args.push(f_val.into());
                }
                return builder.build_call(*llvm_fn, &llvm_args, name).unwrap().try_as_basic_value().left().unwrap_or(f64_type.const_float(0.0).into());
            }
            match name.as_str() {
                "con" => {
                    for arg in args.iter() {
                        match arg {
                            ast::Expr::String(s) => {
                                let str_ptr = builder.build_global_string_ptr(s, "msg").unwrap();
                                builder.build_call(xstd.print_str, &[str_ptr.as_pointer_value().into()], "print_str").unwrap();
                            }
                            _ => {
                                let val = gen_expr(context, builder, module, arg, user_functions, xstd, vars);
                                match val {
                                    BasicValueEnum::PointerValue(p) => {
                                        builder.build_call(xstd.print_str, &[p.into()], "print_str").unwrap();
                                    }
                                    BasicValueEnum::FloatValue(f) => {
                                        builder.build_call(xstd.print_num, &[f.into()], "print_num").unwrap();
                                    }
                                    BasicValueEnum::IntValue(i) => {
                                        let f = builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap();
                                        builder.build_call(xstd.print_num, &[f.into()], "print_num").unwrap();
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                    let nl_str = builder.build_global_string_ptr("\\n", "nl").unwrap();
                    builder.build_call(xstd.sys_write, &[i64_type.const_int(1, false).into(), nl_str.as_pointer_value().into(), i64_type.const_int(1, false).into()], "nl").unwrap();
                    f64_type.const_float(0.0).into()
                }
                _ => f64_type.const_float(0.0).into(),
            }
        }
    }
}
'''

content = content[:start_idx] + new_gen_expr + content[end_idx:]

# Убираем warning про unused mut в xstd
with open('xstd/src/lib.rs', 'r') as f:
    xstd_content = f.read()
xstd_content = xstd_content.replace("let mut current_brk = syscall3(12, 0, 0, 0);", "let current_brk = syscall3(12, 0, 0, 0);")
with open('xstd/src/lib.rs', 'w') as f:
    f.write(xstd_content)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка xstd и компилятора..."
cargo build --release -p xstd
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc
cp target/release/libxstd.a .

echo "==> Запуск теста..."
cd ~/test_zero_full
xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
