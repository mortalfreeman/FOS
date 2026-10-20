mod ast;
mod parser;
mod sema;

use parser::Parser;
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

enum VarInfo<'ctx> { Scalar(PointerValue<'ctx>), Array(PointerValue<'ctx>, u32) }

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

    Target::initialize_all(&InitializationConfig::default());
    let context = Context::create();
    let module = context.create_module("xlang_bare");
    let builder = context.create_builder();

    let i32_type = context.i32_type(); let f64_type = context.f64_type(); let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());

    // Объявляем внешние функции (они будут реализованы в syscall.s)
    let sys_write_type = i64_type.fn_type(&[i64_type.into(), i8_ptr_type.into(), i64_type.into()], false);
    let sys_write_fn = module.add_function("sys_write", sys_write_type, None);
    
    let mut user_functions = std::collections::HashMap::new();
    for item in &global_program.items {
        if let ast::Item::Func(func) = item {
            let fn_type = f64_type.fn_type(&vec![f64_type.into(); func.args.len()], false);
            user_functions.insert(func.name.clone(), (module.add_function(&func.name, fn_type, None), func.clone()));
        }
    }

    // Генерируем функции
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
            gen_stmt(&context, &builder, &module, *llvm_fn, stmt, &user_functions, &sys_write_fn, &mut vars, &mut loop_stack);
        }
        if builder.get_insert_block().unwrap().get_terminator().is_none() {
            builder.build_return(Some(&f64_type.const_float(0.0))).unwrap();
        }
    }

    // Оптимизации O3
    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).unwrap();
    let target_machine = target.create_target_machine(&triple, "generic", "", OptimizationLevel::Aggressive, RelocMode::PIC, CodeModel::Default).unwrap();
    let pass_options = PassBuilderOptions::create();
    let _ = module.run_passes("default<O3>", &target_machine, pass_options);

    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();

    // Генерируем asm-файл с точкой входа и сисколлами
    let asm_code = r#"
        .global _start
        _start:
            call main
            mov $60, %rax
            xor %rdi, %rdi
            syscall

        .global sys_write
        sys_write:
            mov $1, %rax
            syscall
            ret
    "#;
    fs::write("syscall.s", asm_code).unwrap();

    let final_out = out_name.unwrap_or_else(|| "main".to_string());
    
    // Ассемблируем и линкуем через as и ld
    if process::Command::new("as").arg("syscall.s").arg("-o").arg("syscall.o").status().expect("as failed").success() {
        let link_status = process::Command::new("ld")
            .arg("-o").arg(&final_out)
            .arg("output.o")
            .arg("syscall.o")
            .status().expect("ld failed");

        if link_status.success() {
            println!("Compiled successfully (Zero-Dependency, pure asm): ./{}", final_out.green().bold());
            let _ = fs::remove_file("output.o");
            let _ = fs::remove_file("syscall.o");
            let _ = fs::remove_file("syscall.s");
        }
    }
}

fn gen_stmt<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>, current_fn: FunctionValue<'ctx>,
    stmt: &ast::Stmt, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    sys_write: &FunctionValue<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>, loop_stack: &mut Vec<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
) {
    let f64_type = context.f64_type();
    let i64_type = context.i64_type();

    match stmt {
        ast::Stmt::Break => { if let Some((_, after_bb)) = loop_stack.last() { builder.build_unconditional_branch(*after_bb).unwrap(); } }
        ast::Stmt::Continue => { if let Some((continue_bb, _)) = loop_stack.last() { builder.build_unconditional_branch(*continue_bb).unwrap(); } }
        ast::Stmt::For { init, condition, increment, body } => {
            if let Some(i) = init { gen_stmt(context, builder, module, current_fn, i, user_functions, sys_write, vars, loop_stack); }
            let cond_bb = context.append_basic_block(current_fn, "for_cond");
            let body_bb = context.append_basic_block(current_fn, "for_body");
            let inc_bb = context.append_basic_block(current_fn, "for_inc");
            let after_bb = context.append_basic_block(current_fn, "for_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            if let Some(cond) = condition {
                let left = gen_expr(context, builder, module, &cond.0, user_functions, sys_write, vars).into_float_value();
                let right = gen_expr(context, builder, module, &cond.2, user_functions, sys_write, vars).into_float_value();
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
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, user_functions, sys_write, vars, loop_stack); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(inc_bb).unwrap(); }
            builder.position_at_end(inc_bb);
            if let Some(inc) = increment { gen_stmt(context, builder, module, current_fn, inc, user_functions, sys_write, vars, loop_stack); }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::While { condition, body } => {
            let cond_bb = context.append_basic_block(current_fn, "while_cond");
            let loop_bb = context.append_basic_block(current_fn, "while_body");
            let after_bb = context.append_basic_block(current_fn, "while_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            let left = gen_expr(context, builder, module, &condition.0, user_functions, sys_write, vars).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, user_functions, sys_write, vars).into_float_value();
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
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, user_functions, sys_write, vars, loop_stack); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::Assign { name, value } => {
            let val = gen_expr(context, builder, module, value, user_functions, sys_write, vars);
            let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(name) { *ptr } 
                         else { let ptr = builder.build_alloca(f64_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Scalar(ptr)); ptr };
            builder.build_store(alloca, val.into_float_value()).unwrap();
        }
        ast::Stmt::IndexAssign { .. } | ast::Stmt::Return { .. } | ast::Stmt::MacroCall { .. } | ast::Stmt::If { .. } => { /* Упрощено для теста RTOS */ }
        ast::Stmt::Expr(expr) => { gen_expr(context, builder, module, expr, user_functions, sys_write, vars); }
    }
}

fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    sys_write: &FunctionValue<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {
    let f64_type = context.f64_type();
    let i64_type = context.i64_type();
    
    match expr {
        ast::Expr::Int(n) => f64_type.const_float(*n as f64).into(),
        ast::Expr::Float(f) => f64_type.const_float(*f).into(),
        ast::Expr::String(s) => { let str_val = builder.build_global_string_ptr(s, "str").unwrap(); str_val.as_pointer_value().into() }
        ast::Expr::Identifier(name) => { 
            if let Some(VarInfo::Scalar(ptr)) = vars.get(name) { builder.build_load(f64_type, *ptr, name).unwrap() } 
            else { f64_type.const_float(0.0).into() } 
        }
        ast::Expr::BinaryOp { left, op, right } => {
            let l = gen_expr(context, builder, module, left, user_functions, sys_write, vars).into_float_value();
            let r = gen_expr(context, builder, module, right, user_functions, sys_write, vars).into_float_value();
            match op.as_str() {
                "+" => builder.build_float_add(l, r, "add").unwrap().into(),
                "-" => builder.build_float_sub(l, r, "sub").unwrap().into(),
                "*" => builder.build_float_mul(l, r, "mul").unwrap().into(),
                "/" => builder.build_float_div(l, r, "div").unwrap().into(),
                _ => f64_type.const_float(0.0).into(),
            }
        }
        ast::Expr::Call { name, args } => {
            if name == "con" {
                // Вызов нашего sys_write
                if let Some(ast::Expr::String(s)) = args.get(0) {
                    let str_ptr = builder.build_global_string_ptr(s, "msg").unwrap();
                    let len = i64_type.const_int(s.len() as u64, false);
                    builder.build_call(*sys_write, &[i64_type.const_int(1, false).into(), str_ptr.as_pointer_value().into(), len.into()], "syscall").unwrap();
                }
                f64_type.const_float(0.0).into()
            } else if let Some((llvm_fn, _)) = user_functions.get(name) {
                let mut llvm_args = Vec::new();
                for arg in args { llvm_args.push(gen_expr(context, builder, module, arg, user_functions, sys_write, vars).into_float_value().into()); }
                builder.build_call(*llvm_fn, &llvm_args, name).unwrap().try_as_basic_value().left().unwrap_or(f64_type.const_float(0.0).into())
            } else {
                f64_type.const_float(0.0).into()
            }
        }
        _ => f64_type.const_float(0.0).into(),
    }
}

fn resolve_project_files(path: &Path) -> Vec<PathBuf> {
    if path.is_file() { vec![path.to_path_buf()] } else { vec![] }
}
