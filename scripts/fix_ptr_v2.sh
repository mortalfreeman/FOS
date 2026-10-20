#!/bin/bash
set -e
cd ~/FOS

echo "==> Добавление VarInfo::Pointer и исправление присваивания..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем Pointer в VarInfo
content = content.replace(
    "enum VarInfo<'ctx> { \n    Scalar(PointerValue<'ctx>), \n    String(PointerValue<'ctx>), \n    Array(PointerValue<'ctx>, u32) \n}",
    "enum VarInfo<'ctx> { \n    Scalar(PointerValue<'ctx>), \n    String(PointerValue<'ctx>), \n    Array(PointerValue<'ctx>, u32), \n    Pointer(PointerValue<'ctx>) \n}"
)

# 2. В Stmt::Assign проверяем, является ли значение Ref(указателем)
old_assign = """            } else {
                let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
                if val.is_pointer_value() {"""
new_assign = """            } else {
                let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
                if let ast::Expr::Ref(_) = value {
                    // Это взятие адреса (&x)
                    let alloca = if let Some(VarInfo::Pointer(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Pointer(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else if val.is_pointer_value() {"""
content = content.replace(old_assign, new_assign)

# 3. В обработке `*p = val;` меняем поиск с Scalar на Pointer
old_ptr = """                let ptr = if let Some(VarInfo::Scalar(p)) = vars.get(ptr_name) {
                    *p // копируем сам PointerValue, а не ссылку на него
                } else {
                    panic!("Pointer '{}' not found", ptr_name);
                };"""
new_ptr = """                let ptr = if let Some(VarInfo::Pointer(p)) = vars.get(ptr_name) {
                    *p
                } else if let Some(VarInfo::Scalar(p)) = vars.get(ptr_name) {
                    *p
                } else {
                    panic!("Pointer '{}' not found", ptr_name);
                };"""
content = content.replace(old_ptr, new_ptr)

# 4. В gen_expr для Identifier добавляем поддержку Pointer
old_ident = """        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { 
                match info { 
                    VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), 
                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => panic!("Unsupported variable type for '{}'", name)
                } 
            } else { f64_type.const_float(0.0).into() } 
        }"""
new_ident = """        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { 
                match info { 
                    VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), 
                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    VarInfo::Pointer(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
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

echo "==> Запуск теста с указателями..."
cd ~/test_pointer
xc ptr.x -out ptr
./ptr
