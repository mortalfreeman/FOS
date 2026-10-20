
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
use inkwell::values::{BasicValueEnum, BasicMetadataValueEnum, FunctionValue, PointerValue};
use inkwell::basic_block::BasicBlock;
use inkwell::targets::{Target, InitializationConfig, TargetMachine, RelocMode, CodeModel, FileType};
use inkwell::{OptimizationLevel, FloatPredicate};

enum VarInfo<'ctx> { Scalar(PointerValue<'ctx>), Array(PointerValue<'ctx>, u32) }

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { println!("Usage: xc <file.x | dir> [-out <name>]"); process::exit(1); }
    let target_path = PathBuf::from(&args[1]);
    let mut out_name = None; let mut no_sec = false; let mut null_sec = false;
    let mut i = 2;
    while i < args.len() {
        if args[i] == "-out" && i + 1 < args.len() { out_name = Some(args[i+1].clone()); i += 2; }
        else if args[i].starts_with("--nosec") { no_sec = true; i += 1; }
        else if args[i] == "--null-sec" { null_sec = true; i += 1; }
        else { i += 1; }
    }

    let files_to_compile = resolve_project_files(&target_path);
    let mut global_program = ast::Program { items: Vec::new() };
    let mut global_errors = Vec::new();

    for file_path in &files_to_compile {
        let code = fs::read_to_string(file_path).unwrap_or_default();
        let mut parser = Parser::new(&code, file_path.to_str().unwrap(), no_sec, null_sec);
        let prog = parser.parse_program();
        global_errors.extend(parser.errors);
        global_program.items.extend(prog.items);
    }

    if !global_errors.is_empty() && !null_sec { for err in &global_errors { println!("{}", err.red()); } process::exit(1); }
    let mut sema = Sema::new(no_sec, null_sec, "project"); sema.analyze(&global_program);
    if !sema.errors.is_empty() && !null_sec { for err in &sema.errors { println!("{}", err.red()); } process::exit(1); }

    Target::initialize_all(&InitializationConfig::default());
    let context = Context::create();
    let module = context.create_module("xlang_project");
    let builder = context.create_builder();

    let i32_type = context.i32_type(); let f64_type = context.f64_type();
    let i8_ptr_type = context.ptr_type(inkwell::AddressSpace::default());
    let printf_type = i32_type.fn_type(&[i8_ptr_type.into()], true);
    let scanf_type = i32_type.fn_type(&[i8_ptr_type.into()], true);
    let pow_type = f64_type.fn_type(&[f64_type.into(), f64_type.into()], false);
    let math_unary_type = f64_type.fn_type(&[f64_type.into()], false);

    let printf_fn = module.add_function("printf", printf_type, None);
    let scanf_fn = module.add_function("scanf", scanf_type, None);
    let pow_fn = module.add_function("pow", pow_type, None);
    let sin_fn = module.add_function("sin", math_unary_type, None);
    let cos_fn = module.add_function("cos", math_unary_type, None);
    let round_fn = module.add_function("round", math_unary_type, None);
    let floor_fn = module.add_function("floor", math_unary_type, None);
    let ceil_fn = module.add_function("ceil", math_unary_type, None);

    let mut aliases = std::collections::HashMap::new();
    let mut user_functions = std::collections::HashMap::new();

    for item in &global_program.items {
        match item {
            ast::Item::Alias(alias) => { aliases.insert(alias.name.clone(), alias.body.clone()); }
            ast::Item::Func(func) => {
                let fn_type = f64_type.fn_type(&vec![f64_type.into(); func.args.len()], false);
                user_functions.insert(func.name.clone(), (module.add_function(&func.name, fn_type, None), func.clone()));
            }
            _ => {}
        }
    }

    for (_, (llvm_fn, func_decl)) in &user_functions {
        let entry_bb = context.append_basic_block(*llvm_fn, "entry");
        builder.position_at_end(entry_bb);
        let mut vars = HashMap::new();
        let mut loop_stack: Vec<(BasicBlock, BasicBlock)> = Vec::new();
        
        for (i, arg_name) in func_decl.args.iter().enumerate() {
            let arg_val = llvm_fn.get_nth_param(i as u32).unwrap().into_float_value();
            let alloca = builder.build_alloca(f64_type, arg_name).unwrap();
            builder.build_store(alloca, arg_val).unwrap();
            vars.insert(arg_name.clone(), VarInfo::Scalar(alloca));
        }

        for stmt in &func_decl.body {
            gen_stmt(&context, &builder, &module, *llvm_fn, stmt, &aliases, &user_functions, &mut vars, &mut loop_stack, &printf_fn, &scanf_fn, &pow_fn, &sin_fn, &cos_fn, &round_fn, &floor_fn, &ceil_fn);
        }

        if builder.get_insert_block().unwrap().get_terminator().is_none() {
            builder.build_return(Some(&f64_type.const_float(0.0))).unwrap();
        }
    }

    let main_fn = module.add_function("main", i32_type.fn_type(&[], false), None);
    builder.position_at_end(context.append_basic_block(main_fn, "entry"));
    if let Some((llvm_user_main, _)) = user_functions.get("main") { builder.build_call(*llvm_user_main, &[], "call_main").unwrap(); }
    builder.build_return(Some(&i32_type.const_int(0, false))).unwrap();

    if let Err(e) = module.verify() { eprintln!("fatal: {:?}", e); process::exit(1); }
    let target = Target::from_triple(&TargetMachine::get_default_triple()).unwrap();
    let target_machine = target.create_target_machine(&TargetMachine::get_default_triple(), "generic", "", OptimizationLevel::Aggressive, RelocMode::PIC, CodeModel::Default).unwrap();
    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();

    let final_out = out_name.unwrap_or_else(|| "main".to_string());
    if process::Command::new("clang").arg("output.o").arg("-o").arg(&final_out).arg("-lm").status().expect("clang failed").success() {
        println!("Compiled successfully: ./{}", final_out.green().bold());
        let _ = fs::remove_file("output.o");
    }
}

fn gen_stmt<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>, current_fn: FunctionValue<'ctx>,
    stmt: &ast::Stmt, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    vars: &mut HashMap<String, VarInfo<'ctx>>, loop_stack: &mut Vec<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
    printf_fn: &FunctionValue<'ctx>, scanf_fn: &FunctionValue<'ctx>, pow_fn: &FunctionValue<'ctx>,
    sin_fn: &FunctionValue<'ctx>, cos_fn: &FunctionValue<'ctx>, round_fn: &FunctionValue<'ctx>, floor_fn: &FunctionValue<'ctx>, ceil_fn: &FunctionValue<'ctx>,
) {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();

    match stmt {
        ast::Stmt::Break => { if let Some((_, after_bb)) = loop_stack.last() { builder.build_unconditional_branch(*after_bb).unwrap(); } }
        ast::Stmt::Continue => { if let Some((continue_bb, _)) = loop_stack.last() { builder.build_unconditional_branch(*continue_bb).unwrap(); } }
        ast::Stmt::For { init, condition, increment, body } => {
            if let Some(i) = init { gen_stmt(context, builder, module, current_fn, i, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); }
            let cond_bb = context.append_basic_block(current_fn, "for_cond");
            let body_bb = context.append_basic_block(current_fn, "for_body");
            let inc_bb = context.append_basic_block(current_fn, "for_inc");
            let after_bb = context.append_basic_block(current_fn, "for_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            if let Some(cond) = condition {
                let left = gen_expr(context, builder, module, &cond.0, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
                let right = gen_expr(context, builder, module, &cond.2, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
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
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(inc_bb).unwrap(); }
            builder.position_at_end(inc_bb);
            if let Some(inc) = increment { gen_stmt(context, builder, module, current_fn, inc, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::While { condition, body } => {
            let cond_bb = context.append_basic_block(current_fn, "while_cond");
            let loop_bb = context.append_basic_block(current_fn, "while_body");
            let after_bb = context.append_basic_block(current_fn, "while_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            let left = gen_expr(context, builder, module, &condition.0, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
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
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::Assign { name, value } => {
            if let ast::Expr::Array(elements) = value {
                let len = elements.len() as u32; let arr_ty = f64_type.array_type(len);
                let alloca = builder.build_alloca(arr_ty, name).unwrap();
                for (i, elem) in elements.iter().enumerate() {
                    let val = gen_expr(context, builder, module, elem, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
                    let ptr = unsafe { builder.build_gep(arr_ty, alloca, &[i32_type.const_zero(), i32_type.const_int(i as u64, false)], "gep").unwrap() };
                    builder.build_store(ptr, val).unwrap();
                }
                vars.insert(name.clone(), VarInfo::Array(alloca, len));
            } else {
                let val = gen_expr(context, builder, module, value, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn);
                let alloca = if let Some(info) = vars.get(name) { match info { VarInfo::Scalar(ptr) => *ptr, _ => panic!("Cannot assign scalar to array") } } 
                             else { let ptr = builder.build_alloca(f64_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Scalar(ptr)); ptr };
                let f64_val = match val { BasicValueEnum::FloatValue(f) => f, BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "tmp").unwrap(), _ => f64_type.const_float(0.0) };
                builder.build_store(alloca, f64_val).unwrap();
            }
        }
        ast::Stmt::IndexAssign { name, index, value } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_val = gen_expr(context, builder, module, index, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            let idx_int = builder.build_float_to_signed_int(idx_val, i32_type, "idx").unwrap();
            let val = gen_expr(context, builder, module, value, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_store(ptr, val).unwrap();
        }
        ast::Stmt::Return { value } => {
            let val = gen_expr(context, builder, module, value, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            builder.build_return(Some(&val)).unwrap();
        }
        ast::Stmt::Expr(expr) => { gen_expr(context, builder, module, expr, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); }
        ast::Stmt::MacroCall { name } => {
            if let Some(body) = aliases.get(name) { for s in body { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); } }
        }
        ast::Stmt::If { condition, then_branch, else_branch } => {
            let left = gen_expr(context, builder, module, &condition.0, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            let right = gen_expr(context, builder, module, &condition.2, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
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
            for s in then_branch { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); } }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(merge_bb).unwrap(); }
            if let Some(else_stmts) = else_branch {
                builder.position_at_end(else_bb);
                for s in else_stmts { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, vars, loop_stack, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); } }
                if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(merge_bb).unwrap(); }
            }
            builder.position_at_end(merge_bb);
        }
    }
}

fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    vars: &mut HashMap<String, VarInfo<'ctx>>, printf_fn: &FunctionValue<'ctx>, scanf_fn: &FunctionValue<'ctx>, pow_fn: &FunctionValue<'ctx>,
    sin_fn: &FunctionValue<'ctx>, cos_fn: &FunctionValue<'ctx>, round_fn: &FunctionValue<'ctx>, floor_fn: &FunctionValue<'ctx>, ceil_fn: &FunctionValue<'ctx>,
) -> BasicValueEnum<'ctx> {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    match expr {
        ast::Expr::Int(n) => f64_type.const_float(*n as f64).into(),
        ast::Expr::Float(f) => f64_type.const_float(*f).into(),
        ast::Expr::String(s) => { let str_val = builder.build_global_string_ptr(s, "str").unwrap(); str_val.as_pointer_value().into() }
        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { match info { VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), _ => f64_type.const_float(0.0).into() } } 
            else { f64_type.const_float(0.0).into() } 
        }
        ast::Expr::Index { name, index } => {
            let (arr_ptr, len) = match vars.get(name).expect("Array not found") { VarInfo::Array(ptr, len) => (*ptr, *len), _ => panic!("Not an array") };
            let idx_val = gen_expr(context, builder, module, index, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            let idx_int = builder.build_float_to_signed_int(idx_val, i32_type, "idx").unwrap();
            let ptr = unsafe { builder.build_gep(f64_type.array_type(len), arr_ptr, &[i32_type.const_zero(), idx_int], "gep").unwrap() };
            builder.build_load(f64_type, ptr, "load_arr").unwrap()
        }
        ast::Expr::Array(_) => { f64_type.const_float(0.0).into() }
        ast::Expr::BinaryOp { left, op, right } => {
            let left_val = gen_expr(context, builder, module, left, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            let right_val = gen_expr(context, builder, module, right, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
            match op.as_str() {
                "+" => builder.build_float_add(left_val, right_val, "addtmp").unwrap().into(),
                "-" => builder.build_float_sub(left_val, right_val, "subtmp").unwrap().into(),
                "*" => builder.build_float_mul(left_val, right_val, "multmp").unwrap().into(),
                "/" => builder.build_float_div(left_val, right_val, "divtmp").unwrap().into(),
                _ => f64_type.const_float(0.0).into(),
            }
        }
        ast::Expr::MacroCall(name) => {
            if let Some(body) = aliases.get(name) { for s in body { gen_stmt(context, builder, module, module.get_functions().next().unwrap(), s, aliases, user_functions, vars, &mut Vec::new(), printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn); } }
            f64_type.const_float(0.0).into()
        }
        ast::Expr::Call { name, args } => {
            if let Some((llvm_fn, _)) = user_functions.get(name) {
                let mut llvm_args = Vec::new();
                for arg in args { llvm_args.push(gen_expr(context, builder, module, arg, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value().into()); }
                return builder.build_call(*llvm_fn, &llvm_args, name).unwrap().try_as_basic_value().left().unwrap_or(f64_type.const_float(0.0).into());
            }
            match name.as_str() {
                "con" => {
                    let mut fmt_str = String::new(); let mut llvm_args: Vec<BasicMetadataValueEnum> = Vec::new();
                    for arg in args.iter() {
                        match arg {
                            ast::Expr::String(s) => fmt_str.push_str(s.as_str()),
                            _ => { fmt_str.push_str("%.2f "); llvm_args.push(gen_expr(context, builder, module, arg, aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into()); }
                        }
                    }
                    fmt_str.push('\n');
                    let fmt_global = builder.build_global_string_ptr(&fmt_str, "fmt").unwrap();
                    let mut final_args: Vec<BasicMetadataValueEnum> = vec![fmt_global.as_pointer_value().into()]; final_args.extend(llvm_args);
                    builder.build_call(*printf_fn, &final_args, "call_con").unwrap(); f64_type.const_float(0.0).into()
                }
                "powr" => {
                    if args.len() >= 2 {
                        let base = gen_expr(context, builder, module, &args[0], aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
                        let exp = gen_expr(context, builder, module, &args[1], aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
                        builder.build_call(*pow_fn, &[base.into(), exp.into()], "pow_call").unwrap().try_as_basic_value().left().unwrap()
                    } else { f64_type.const_float(0.0).into() }
                }
                "sin" | "cosin" | "round" | "floor" | "ceil" => {
                    if args.len() >= 1 {
                        let val = gen_expr(context, builder, module, &args[0], aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
                        let func = match name.as_str() { "sin" => sin_fn, "cosin" => cos_fn, "round" => round_fn, "floor" => floor_fn, "ceil" => ceil_fn, _ => unreachable!() };
                        builder.build_call(*func, &[val.into()], name.as_str()).unwrap().try_as_basic_value().left().unwrap()
                    } else { f64_type.const_float(0.0).into() }
                }
                "is-odd" | "is-even" => {
                    if args.len() >= 1 {
                        let val = gen_expr(context, builder, module, &args[0], aliases, user_functions, vars, printf_fn, scanf_fn, pow_fn, sin_fn, cos_fn, round_fn, floor_fn, ceil_fn).into_float_value();
                        let i64_type = context.i64_type();
                        let val_i = builder.build_float_to_signed_int(val, i64_type, "tmp").unwrap();
                        let rem = builder.build_int_signed_rem(val_i, i64_type.const_int(2, false), "rem").unwrap();
                        let cond = if name == "is-odd" { builder.build_int_compare(inkwell::IntPredicate::NE, rem, i64_type.const_zero(), "is_odd").unwrap() } else { builder.build_int_compare(inkwell::IntPredicate::EQ, rem, i64_type.const_zero(), "is_even").unwrap() };
                        builder.build_unsigned_int_to_float(cond, f64_type, "res").unwrap().into()
                    } else { f64_type.const_float(0.0).into() }
                }
                _ => f64_type.const_float(0.0).into(),
            }
        }
    }
}

fn resolve_project_files(path: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    if path.is_file() { files.push(path.to_path_buf()); } 
    else if path.is_dir() {
        let conf_path = path.join("xcompconf");
        if conf_path.exists() {
            let conf_content = fs::read_to_string(conf_path).unwrap_or_default();
            let mut in_priority = false;
            for line in conf_content.lines() {
                let line = line.trim();
                if line.starts_with("$Priority") { in_priority = true; continue; }
                if in_priority {
                    if let Some(start) = line.find('(') { if let Some(end) = line.rfind(')') {
                        let mut p = PathBuf::from(&line[start+1..end]);
                        if p.is_relative() { p = path.join(p); }
                        if p.exists() { files.push(p); }
                    }}
                    if line.contains('}') { in_priority = false; }
                }
            }
        }
        if files.is_empty() {
            let mut xh = Vec::new(); let mut xxx = Vec::new(); let mut xx = Vec::new(); let mut x = Vec::new();
            if let Ok(entries) = fs::read_dir(path) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_file() {
                        if let Some(ext) = p.extension().and_then(|s| s.to_str()) {
                            match ext { "xh" => xh.push(p), "xxx" => xxx.push(p), "xx" => xx.push(p), "x" => x.push(p), _ => {} }
                        }
                    }
                }
            }
            xh.sort(); xxx.sort(); xx.sort(); x.sort();
            files.extend(xh); files.extend(xxx); files.extend(xx); files.extend(x);
        }
    }
    let mut std_libs = Vec::new();
    for file in &files {
        if let Ok(content) = fs::read_to_string(file) {
            for line in content.lines() {
                let line = line.trim();
                if line.starts_with(".use ") && !line.contains("-") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 { let sys_lib_path = PathBuf::from(format!("/usr/local/use/{}.xh", parts[1])); if sys_lib_path.exists() { std_libs.push(sys_lib_path); } }
                }
            }
        }
    }
    std_libs.sort(); std_libs.dedup();
    let mut final_files = std_libs; final_files.extend(files); final_files
}
