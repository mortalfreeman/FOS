#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание суверенной стандартной библиотеки xstd (no_std Rust)..."
mkdir -p xstd/src
cat > xstd/Cargo.toml << 'EOF'
[package]
name = "xstd"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]

[profile.release]
panic = "abort"
opt-level = 3
EOF

cat > xstd/src/lib.rs << 'EOF'
#![no_std]

use core::arch::asm;
use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    unsafe { sys_exit(1) }
}

unsafe fn syscall3(n: usize, a1: usize, a2: usize, a3: usize) -> usize {
    let ret: usize;
    asm!(
        "syscall",
        inlateout("rax") n => ret,
        in("rdi") a1,
        in("rsi") a2,
        in("rdx") a3,
        lateout("rcx") _,
        lateout("r11") _,
        options(nostack)
    );
    ret
}

#[no_mangle]
pub extern "C" fn sys_exit(code: usize) -> ! {
    unsafe {
        syscall3(60, code, 0, 0);
        loop {}
    }
}

#[no_mangle]
pub extern "C" fn malloc(size: usize) -> *mut u8 {
    unsafe {
        let mut current_brk = syscall3(12, 0, 0, 0);
        let new_brk = current_brk + ((size + 7) & !7);
        syscall3(12, new_brk, 0, 0);
        current_brk as *mut u8
    }
}

#[no_mangle]
pub extern "C" fn strlen(s: *const u8) -> usize {
    let mut len = 0;
    unsafe {
        while *s.add(len) != 0 { len += 1; }
    }
    len
}

#[no_mangle]
pub extern "C" fn strcpy(dest: *mut u8, src: *const u8) -> *mut u8 {
    let mut i = 0;
    unsafe {
        while *src.add(i) != 0 {
            *dest.add(i) = *src.add(i);
            i += 1;
        }
        *dest.add(i) = 0;
    }
    dest
}

#[no_mangle]
pub extern "C" fn strcat(dest: *mut u8, src: *const u8) -> *mut u8 {
    let mut i = 0;
    unsafe {
        while *dest.add(i) != 0 { i += 1; }
        let mut j = 0;
        while *src.add(j) != 0 {
            *dest.add(i) = *src.add(j);
            i += 1; j += 1;
        }
        *dest.add(i) = 0;
    }
    dest
}

#[no_mangle]
pub extern "C" fn print_str(s: *const u8) {
    let len = strlen(s);
    unsafe { syscall3(1, 1, s as usize, len); }
}

#[no_mangle]
pub extern "C" fn print_num(val: f64) {
    let mut num = val as i64;
    let mut buf = [0u8; 32];
    let mut i = 0;
    
    if num == 0 {
        unsafe { syscall3(1, 1, b"0.00\0".as_ptr() as usize, 4); }
        return;
    }
    
    let is_neg = num < 0;
    if is_neg { num = -num; }
    
    while num > 0 {
        buf[i] = (num % 10) as u8 + b'0';
        num /= 10;
        i += 1;
    }
    
    if is_neg {
        buf[i] = b'-';
        i += 1;
    }
    
    let mut j = 0;
    while j < i / 2 {
        let tmp = buf[j];
        buf[j] = buf[i - j - 1];
        buf[i - j - 1] = tmp;
        j += 1;
    }
    
    buf[i] = b'.';
    buf[i+1] = b'0';
    buf[i+2] = b'0';
    buf[i+3] = b'\0';
    i += 4;
    
    unsafe { syscall3(1, 1, buf.as_ptr() as usize, i); }
}
EOF

echo "==> 2. Сборка xstd..."
cd xstd
cargo build --release
cd ..
cp xstd/target/release/libxstd.a .

echo "==> 3. Перезапись main.rs (Возвращаем строки, массивы и if/else на суверенном уровне)..."
cat > xlang-compiler/src/main.rs << 'EOF'
mod ast;
mod parser;
mod sema;

use parser::Parser;
use sema::Sema;
use colored::*;
use std::env;
use std::fs;
use std::process;
use std::path::{Path, PathBuf};
use std::collections::HashMap;

use inkwell::context::Context;
use inkwell::module::Module;
use inkwell::builder::Builder;
use inkwell::values::{BasicValueEnum, FunctionValue, PointerValue};
use inkwell::basic_block::BasicBlock;
use inkwell::targets::{Target, InitializationConfig, TargetMachine, RelocMode, CodeModel, FileType};
use inkwell::passes::PassBuilderOptions;
use inkwell::{OptimizationLevel, FloatPredicate, AddressSpace};

enum VarInfo<'ctx> { Scalar(PointerValue<'ctx>), Array(PointerValue<'ctx>, u32), String(PointerValue<'ctx>) }

struct Xstd<'ctx> {
    malloc: FunctionValue<'ctx>, strlen: FunctionValue<'ctx>, strcpy: FunctionValue<'ctx>,
    strcat: FunctionValue<'ctx>, print_str: FunctionValue<'ctx>, print_num: FunctionValue<'ctx>,
    sys_exit: FunctionValue<'ctx>, sys_write: FunctionValue<'ctx>,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { println!("Usage: xc <file.x> [-out <name>]"); process::exit(1); }
    let target_path = PathBuf::from(&args[1]);
    let mut out_name = None;
    let mut i = 2;
    while i < args.len() {
        if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }
        else { i += 1; }
    }

    let files_to_compile = resolve_project_files(&target_path);
    let mut global_program = ast::Program { items: Vec::new() };
    let mut global_errors = Vec::new();

    for file_path in &files_to_compile {
        let code = fs::read_to_string(file_path).unwrap_or_default();
        let mut parser = Parser::new(&code, file_path.to_str().unwrap(), false, false);
        let prog = parser.parse_program();
        global_errors.extend(parser.errors);
        global_program.items.extend(prog.items);
    }

    if !global_errors.is_empty() { for err in &global_errors { println!("{}", err.red()); } process::exit(1); }
    let mut sema = Sema::new(false, false, "project"); sema.analyze(&global_program);
    if !sema.errors.is_empty() { for err in &sema.errors { println!("{}", err.red()); } process::exit(1); }

    Target::initialize_all(&InitializationConfig::default());
    let context = Context::create();
    let module = context.create_module("xlang_bare");
    let builder = context.create_builder();

    let i32_type = context.i32_type(); let f64_type = context.f64_type(); let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());

    let xstd = Xstd {
        malloc: module.add_function("malloc", i8_ptr_type.fn_type(&[i64_type.into()], false), None),
        strlen: module.add_function("strlen", i64_type.fn_type(&[i8_ptr_type.into()], false), None),
        strcpy: module.add_function("strcpy", i8_ptr_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None),
        strcat: module.add_function("strcat", i8_ptr_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None),
        print_str: module.add_function("print_str", context.void_type().fn_type(&[i8_ptr_type.into()], false), None),
        print_num: module.add_function("print_num", context.void_type().fn_type(&[f64_type.into()], false), None),
        sys_exit: module.add_function("sys_exit", context.void_type().fn_type(&[i64_type.into()], false), None),
        sys_write: module.add_function("sys_write", i64_type.fn_type(&[i64_type.into(), i8_ptr_type.into(), i64_type.into()], false), None),
    };

    let mut user_functions = std::collections::HashMap::new();
    for item in &global_program.items {
        if let ast::Item::Func(func) = item {
            let fn_type = f64_type.fn_type(&vec![f64_type.into(); func.args.len()], false);
            user_functions.insert(func.name.clone(), (module.add_function(&func.name, fn_type, None), func.clone()));
        }
    }

    for (_, (llvm_fn, func_decl)) in &user_functions {
        let bb = context.append_basic_block(*llvm_fn, "entry");
        builder.position_at_end(bb);
        let mut vars = HashMap::new();
        let mut loop_stack = Vec::new();
        for (i, arg_name) in func_decl.args.iter().enumerate() {
            let arg_val = llvm_fn.get_nth_param(i as u32).unwrap().into_float_value();
            let alloca = builder.build_alloca(f64_type, arg_name).unwrap();
            builder.build_store(alloca, arg_val).unwrap();
            vars.insert(arg_name.clone(), VarInfo::Scalar(alloca));
        }
        for stmt in &func_decl.body {
            gen_stmt(&context, &builder, &module, *llvm_fn, stmt, &user_functions, &xstd, &mut vars, &mut loop_stack);
        }
        if builder.get_insert_block().unwrap().get_terminator().is_none() {
            builder.build_return(Some(&f64_type.const_float(0.0))).unwrap();
        }
    }

    let start_fn = module.add_function("_start", context.void_type().fn_type(&[], false), None);
    builder.position_at_end(context.append_basic_block(start_fn, "entry"));
    if let Some((llvm_user_main, _)) = user_functions.get("main") {
        builder.build_call(*llvm_user_main, &[], "call_main").unwrap();
    }
    builder.build_call(xstd.sys_exit, &[i64_type.const_int(0, false).into()], "exit").unwrap();
    builder.build_unreachable().unwrap();

    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).unwrap();
    let target_machine = target.create_target_machine(&triple, "generic", "", OptimizationLevel::Aggressive, RelocMode::PIC, CodeModel::Default).unwrap();
    let pass_options = PassBuilderOptions::create();
    let _ = module.run_passes("default<O3>", &target_machine, pass_options);

    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();

    let final_out = out_name.unwrap_or_else(|| "main".to_string());
    
    let link_status = process::Command::new("ld")
        .arg("-o").arg(&final_out)
        .arg("output.o")
        .arg("libxstd.a")
        .status().expect("ld failed");

    if link_status.success() {
        println!("Compiled successfully (Zero-Dep): ./{}", final_out.green().bold());
        let _ = fs::remove_file("output.o");
    }
}

fn gen_stmt<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>, current_fn: FunctionValue<'ctx>,
    stmt: &ast::Stmt, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    xstd: &Xstd<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>, loop_stack: &mut Vec<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
) {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());

    match stmt {
        ast::Stmt::Break => { if let Some((_, after_bb)) = loop_stack.last() { builder.build_unconditional_branch(*after_bb).unwrap(); } }
        ast::Stmt::Continue => { if let Some((continue_bb, _)) = loop_stack.last() { builder.build_unconditional_branch(*continue_bb).unwrap(); } }
        ast::Stmt::For { init, condition, increment, body } => {
            if let Some(i) = init { gen_stmt(context, builder, module, current_fn, i, user_functions, xstd, vars, loop_stack); }
            let cond_bb = context.append_basic_block(current_fn, "for_cond");
            let body_bb = context.append_basic_block(current_fn, "for_body");
            let inc_bb = context.append_basic_block(current_fn, "for_inc");
            let after_bb = context.append_basic_block(current_fn, "for_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            if let Some(cond) = condition {
                let left = gen_expr(context, builder, module, &cond.0, user_functions, xstd, vars).into_float_value();
                let right = gen_expr(context, builder, module, &cond.2, user_functions, xstd, vars).into_float_value();
                let cmp = match cond.1.as_str() {
                    "==" => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
                    "!=" => builder.build_float_compare(FloatPredicate::ONE, left, right, "cmp").unwrap(),
                    "<" => builder.build_float_compare(FloatPredicate::OLT, left, right, "cmp").unwrap(),
                    ">" => builder.build_float_compare(FloatPredicate::OGT, left, right, "cmp").unwrap(),
                    "<=" => builder.build_float_compare(FloatPredicate::OLE, left, right, "cmp").unwrap(),
                    ">=" => builder.build_float_compare(FloatPredicate::OGE, left, right, "cmp").unwrap(),
                    _ => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
                };
                builder.build_conditional_branch(cmp, body_bb, after_bb).unwrap();
            } else { builder.build_unconditional_branch(body_bb).unwrap(); }
            builder.position_at_end(body_bb);
            loop_stack.push((inc_bb, after_bb));
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, user_functions, xstd, vars, loop_stack); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(inc_bb).unwrap(); }
            builder.position_at_end(inc_bb);
            if let Some(inc) = increment { gen_stmt(context, builder, module, current_fn, inc, user_functions, xstd, vars, loop_stack); }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::While { condition, body } => {
            let cond_bb = context.append_basic_block(current_fn, "while_cond");
            let loop_bb = context.append_basic_block(current_fn, "while_body");
            let after_bb = context.append_basic_block(current_fn, "while_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            let left = gen_expr(context, builder, module, &condition.0, user_functions, xstd, vars).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, user_functions, xstd, vars).into_float_value();
            let cmp = match condition.1.as_str() {
                "==" => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
                "!=" => builder.build_float_compare(FloatPredicate::ONE, left, right, "cmp").unwrap(),
                "<" => builder.build_float_compare(FloatPredicate::OLT, left, right, "cmp").unwrap(),
                ">" => builder.build_float_compare(FloatPredicate::OGT, left, right, "cmp").unwrap(),
                "<=" => builder.build_float_compare(FloatPredicate::OLE, left, right, "cmp").unwrap(),
                ">=" => builder.build_float_compare(FloatPredicate::OGE, left, right, "cmp").unwrap(),
                _ => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
            };
            builder.build_conditional_branch(cmp, loop_bb, after_bb).unwrap();
            builder.position_at_end(loop_bb);
            loop_stack.push((cond_bb, after_bb));
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, user_functions, xstd, vars, loop_stack); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::Assign { name, value } => {
            if let ast::Expr::Array(elements) = value {
                let len = elements.len() as u32; let arr_ty = f64_type.array_type(len);
                let alloca = builder.build_alloca(arr_ty, name).unwrap();
                for (i, elem) in elements.iter().enumerate() {
                    let val = gen_expr(context, builder, module, elem, user_functions, xstd, vars).into_float_value();
                    let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };
                    builder.build_store(ptr, val).unwrap();
                }
                vars.insert(name.clone(), VarInfo::Array(alloca, len));
            } else if let ast::Expr::String(s) = value {
                let global_str = builder.build_global_string_ptr(s, "str").unwrap();
                let len = builder.build_call(xstd.strlen, &[global_str.as_pointer_value().into()], "len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let one = i64_type.const_int(1, false);
                let total_len = builder.build_int_add(len, one, "total").unwrap();
                let malloc_ptr = builder.build_call(xstd.malloc, &[total_len.into()], "malloc").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                builder.build_call(xstd.strcpy, &[malloc_ptr.into(), global_str.as_pointer_value().into()], "strcpy").unwrap();
                
                let alloca = builder.build_alloca(i8_ptr_type, name).unwrap();
                builder.build_store(alloca, malloc_ptr).unwrap();
                vars.insert(name.clone(), VarInfo::String(alloca));
            } else {
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
            }
        }
        ast::Stmt::IndexAssign { name, index, value } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_val = gen_expr(context, builder, module, index, user_functions, xstd, vars).into_float_value();
            let idx_int = builder.build_float_to_signed_int(idx_val, i32_type, "idx").unwrap();
            let val = gen_expr(context, builder, module, value, user_functions, xstd, vars).into_float_value();
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_store(ptr, val).unwrap();
        }
        ast::Stmt::Return { value } => {
            let val = gen_expr(context, builder, module, value, user_functions, xstd, vars).into_float_value();
            builder.build_return(Some(&val)).unwrap();
        }
        ast::Stmt::Expr(expr) => { gen_expr(context, builder, module, expr, user_functions, xstd, vars); }
        ast::Stmt::MacroCall { .. } => { /* Пропускаем для простоты */ }
        ast::Stmt::If { condition, then_branch, else_branch } => {
            let left = gen_expr(context, builder, module, &condition.0, user_functions, xstd, vars).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, user_functions, xstd, vars).into_float_value();
            let cmp = match condition.1.as_str() {
                "==" => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
                "!=" => builder.build_float_compare(FloatPredicate::ONE, left, right, "cmp").unwrap(),
                "<" => builder.build_float_compare(FloatPredicate::OLT, left, right, "cmp").unwrap(),
                ">" => builder.build_float_compare(FloatPredicate::OGT, left, right, "cmp").unwrap(),
                "<=" => builder.build_float_compare(FloatPredicate::OLE, left, right, "cmp").unwrap(),
                ">=" => builder.build_float_compare(FloatPredicate::OGE, left, right, "cmp").unwrap(),
                _ => builder.build_float_compare(FloatPredicate::OEQ, left, right, "cmp").unwrap(),
            };
            let then_bb = context.append_basic_block(current_fn, "then");
            let merge_bb = context.append_basic_block(current_fn, "merge");
            let else_bb = if else_branch.is_some() { context.append_basic_block(current_fn, "else") } else { merge_bb };
            builder.build_conditional_branch(cmp, then_bb, else_bb).unwrap();
            builder.position_at_end(then_bb);
            for s in then_branch { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, user_functions, xstd, vars, loop_stack); } }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(merge_bb).unwrap(); }
            if let Some(else_stmts) = else_branch {
                builder.position_at_end(else_bb);
                for s in else_stmts { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, user_functions, xstd, vars, loop_stack); } }
                if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(merge_bb).unwrap(); }
            }
            builder.position_at_end(merge_bb);
        }
    }
}

fn gen_expr<'ctx>(
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
                    _ => f64_type.const_float(0.0).into() 
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

            let l_f = left_val.into_float_value();
            let r_f = right_val.into_float_value();
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
                for arg in args { llvm_args.push(gen_expr(context, builder, module, arg, user_functions, xstd, vars).into_float_value().into()); }
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
                                if val.is_pointer_value() {
                                    builder.build_call(xstd.print_str, &[val.into()], "print_str").unwrap();
                                } else {
                                    builder.build_call(xstd.print_num, &[val.into()], "print_num").unwrap();
                                }
                            }
                        }
                    }
                    let nl_str = builder.build_global_string_ptr("\n", "nl").unwrap();
                    builder.build_call(xstd.sys_write, &[i64_type.const_int(1, false).into(), nl_str.as_pointer_value().into(), i64_type.const_int(1, false).into()], "nl").unwrap();
                    f64_type.const_float(0.0).into()
                }
                _ => f64_type.const_float(0.0).into(),
            }
        }
    }
}

fn resolve_project_files(path: &Path) -> Vec<PathBuf> {
    if path.is_file() { vec![path.to_path_buf()] } else { vec![] }
}
EOF

echo "==> 4. Пересборка компилятора..."
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 5. Тест Zero-Dependency (Полный язык)..."
mkdir -p ~/test_zero_full
cd ~/test_zero_full

cat > zero.x << 'EOF'
func main {
    name = "X-lang";
    greeting = "Hello, " + name + "!";
    con(greeting);
    
    arr = [10, 20, 30];
    sum = 0;
    for (i = 0; i < 3; i = i + 1) {
        sum = sum + arr[i];
    }
    con("Sum: ", sum);
    
    if (sum > 50) {
        con("Sum is greater than 50");
    }
}
EOF

xc zero.x -out zero
./zero

echo -e "\nПроверка зависимостей (ldd):"
ldd ./zero || echo "Нет динамических зависимостей (статика)!"
