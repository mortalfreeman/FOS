#!/bin/bash
set -e
cd ~/FOS

echo "==> Полное исправление логики указателей..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Исправляем Ref: если expr - это Identifier, возвращаем указатель на его alloca
old_ref = """        ast::Expr::Ref(inner) => {
            let val = gen_expr(context, builder, module, inner, aliases, user_functions, libc, vars);
            let alloca = builder.build_alloca(f64_type.ptr_type(AddressSpace::default()), "ref_tmp").unwrap();
            builder.build_store(alloca, val).unwrap();
            alloca.into()
        }"""
new_ref = """        ast::Expr::Ref(inner) => {
            if let ast::Expr::Identifier(name) = &**inner {
                // Берем адрес существующей переменной x
                if let Some(VarInfo::Scalar(ptr)) = vars.get(name) {
                    return (*ptr).into(); // Возвращаем указатель на alloca переменной
                }
            }
            panic!("Cannot take address of non-identifier");
        }"""
content = content.replace(old_ref, new_ref)

# 2. Исправляем присваивание: убираем создание временной alloca, сохраняем прямо в p
old_assign = """                if let ast::Expr::Ref(_) = value {
                    // Это взятие адреса (&x)
                    let alloca = if let Some(VarInfo::Pointer(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Pointer(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else if val.is_pointer_value() {"""
new_assign = """                if let ast::Expr::Ref(_) = value {
                    // Это взятие адреса (&x)
                    let alloca = if let Some(VarInfo::Pointer(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Pointer(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else if val.is_pointer_value() {"""
# Тут ничего не меняем, просто убеждаемся, что все ок

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Запуск теста..."
cd ~/test_pointer
xc ptr.x -out ptr
./ptr
