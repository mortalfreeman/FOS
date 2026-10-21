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
use inkwell::{OptimizationLevel, FloatPredicate, IntPredicate, AddressSpace};

enum VarInfo<'ctx> { 
    Scalar(PointerValue<'ctx>), 
    Int(PointerValue<'ctx>), 
    String(PointerValue<'ctx>), 
    Array(PointerValue<'ctx>, u32),
    IntArray(PointerValue<'ctx>, u32), 
    Pointer(PointerValue<'ctx>) 
}

struct Libc<'ctx> {
    printf: FunctionValue<'ctx>, scanf: FunctionValue<'ctx>, sprintf: FunctionValue<'ctx>,
    pow: FunctionValue<'ctx>, sin: FunctionValue<'ctx>, cos: FunctionValue<'ctx>, round: FunctionValue<'ctx>, floor: FunctionValue<'ctx>, ceil: FunctionValue<'ctx>,
    malloc: FunctionValue<'ctx>, strlen: FunctionValue<'ctx>, strcpy: FunctionValue<'ctx>, strcat: FunctionValue<'ctx>,
    write: FunctionValue<'ctx>, std_flush: FunctionValue<'ctx>,
    std_print_str: FunctionValue<'ctx>, std_print_num: FunctionValue<'ctx>, std_print_int: FunctionValue<'ctx>,
    std_read_line: FunctionValue<'ctx>, std_in_buf: PointerValue<'ctx>, getchar: FunctionValue<'ctx>, strtoll: FunctionValue<'ctx>, strtod: FunctionValue<'ctx>,
}


fn to_int<'ctx>(builder: &Builder<'ctx>, val: BasicValueEnum<'ctx>, i64_type: inkwell::types::IntType<'ctx>) -> inkwell::values::IntValue<'ctx> {
    match val {
        BasicValueEnum::IntValue(i) => i,
        BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i64_type, "float_to_int").unwrap(),
        _ => panic!("Cannot convert to int"),
    }
}

fn to_float<'ctx>(builder: &Builder<'ctx>, val: BasicValueEnum<'ctx>, f64_type: inkwell::types::FloatType<'ctx>) -> inkwell::values::FloatValue<'ctx> {
    match val {
        BasicValueEnum::FloatValue(f) => f,
        BasicValueEnum::IntValue(i) => builder.build_signed_int_to_float(i, f64_type, "int_to_float").unwrap(),
        _ => panic!("Cannot convert to float"),
    }
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
    let module = context.create_module("xlang_libc");
    let builder = context.create_builder();

    let i32_type = context.i32_type(); let i64_type = context.i64_type(); let f64_type = context.f64_type(); let i8_type = context.i8_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());

    let printf = module.add_function("printf", i32_type.fn_type(&[i8_ptr_type.into()], true), None);
    let scanf = module.add_function("scanf", i32_type.fn_type(&[i8_ptr_type.into()], true), None);
    let sprintf = module.add_function("sprintf", i32_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], true), None);
    let pow = module.add_function("pow", f64_type.fn_type(&[f64_type.into(), f64_type.into()], false), None);
    let sin = module.add_function("sin", f64_type.fn_type(&[f64_type.into()], false), None);
    let cos = module.add_function("cos", f64_type.fn_type(&[f64_type.into()], false), None);
    let round = module.add_function("round", f64_type.fn_type(&[f64_type.into()], false), None);
    let floor = module.add_function("floor", f64_type.fn_type(&[f64_type.into()], false), None);
    let ceil = module.add_function("ceil", f64_type.fn_type(&[f64_type.into()], false), None);
    let malloc = module.add_function("malloc", i8_ptr_type.fn_type(&[i64_type.into()], false), None);
    let strlen = module.add_function("strlen", i64_type.fn_type(&[i8_ptr_type.into()], false), None);
    let strcpy = module.add_function("strcpy", i8_ptr_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None);
    let strcat = module.add_function("strcat", i8_ptr_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None);
    let write_fn = module.add_function("write", i64_type.fn_type(&[i32_type.into(), i8_ptr_type.into(), i64_type.into()], false), None);
    let getchar = module.add_function("getchar", i32_type.fn_type(&[], false), None);
    let strtoll = module.add_function("strtoll", i64_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into(), i32_type.into()], false), None);
    let strtod = module.add_function("strtod", f64_type.fn_type(&[i8_ptr_type.into(), i8_ptr_type.into()], false), None);

    let std_buf = module.add_global(i8_type.array_type(4096), None, "std_buf");
    std_buf.set_initializer(&i8_type.const_array(&[i8_type.const_zero(); 4096]));
    let std_len = module.add_global(i64_type, None, "std_len");
    std_len.set_initializer(&i64_type.const_zero());

    let std_in_buf = module.add_global(i8_type.array_type(4096), None, "std_in_buf");
    std_in_buf.set_initializer(&i8_type.const_array(&[i8_type.const_zero(); 4096]));

    let std_flush = module.add_function("std_flush", context.void_type().fn_type(&[], false), None);
    let std_print_str = module.add_function("std_print_str", context.void_type().fn_type(&[i8_ptr_type.into()], false), None);
    let std_print_num = module.add_function("std_print_num", context.void_type().fn_type(&[f64_type.into()], false), None);
    let std_print_int = module.add_function("std_print_int", context.void_type().fn_type(&[i64_type.into()], false), None);
    let std_read_line = module.add_function("std_read_line", i64_type.fn_type(&[], false), None);

    // std_flush
    let bb = context.append_basic_block(std_flush, "entry");
    builder.position_at_end(bb);
    let len_val = builder.build_load(i64_type, std_len.as_pointer_value(), "len").unwrap().into_int_value();
    let is_zero = builder.build_int_compare(IntPredicate::EQ, len_val, i64_type.const_zero(), "is_zero").unwrap();
    let ret_bb = context.append_basic_block(std_flush, "ret");
    let write_bb = context.append_basic_block(std_flush, "write");
    builder.build_conditional_branch(is_zero, ret_bb, write_bb).unwrap();
    builder.position_at_end(write_bb);
    let buf_ptr = builder.build_pointer_cast(std_buf.as_pointer_value(), i8_ptr_type, "buf_ptr").unwrap();
    builder.build_call(write_fn, &[i32_type.const_int(1, false).into(), buf_ptr.into(), len_val.into()], "write_call").unwrap();
    builder.build_store(std_len.as_pointer_value(), i64_type.const_zero()).unwrap();
    builder.build_unconditional_branch(ret_bb).unwrap();
    builder.position_at_end(ret_bb);
    builder.build_return(None).unwrap();

    // std_print_str
    let bb = context.append_basic_block(std_print_str, "entry");
    builder.position_at_end(bb);
    let s_ptr_alloca = builder.build_alloca(i8_ptr_type, "s_ptr").unwrap();
    builder.build_store(s_ptr_alloca, std_print_str.get_nth_param(0).unwrap()).unwrap();
    let loop_bb = context.append_basic_block(std_print_str, "loop");
    let end_bb = context.append_basic_block(std_print_str, "end");
    builder.build_unconditional_branch(loop_bb).unwrap();
    builder.position_at_end(loop_bb);
    let s_ptr = builder.build_load(i8_ptr_type, s_ptr_alloca, "s").unwrap().into_pointer_value();
    let c = builder.build_load(i8_type, s_ptr, "c").unwrap().into_int_value();
    let is_null = builder.build_int_compare(IntPredicate::EQ, c, i8_type.const_zero(), "is_null").unwrap();
    let body_bb = context.append_basic_block(std_print_str, "body");
    builder.build_conditional_branch(is_null, end_bb, body_bb).unwrap();
    builder.position_at_end(body_bb);
    let cur_len = builder.build_load(i64_type, std_len.as_pointer_value(), "len").unwrap().into_int_value();
    let gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_buf.as_pointer_value(), &[i64_type.const_zero(), cur_len], "gep").unwrap() };
    builder.build_store(gep, c).unwrap();
    let new_len = builder.build_int_add(cur_len, i64_type.const_int(1, false), "new_len").unwrap();
    builder.build_store(std_len.as_pointer_value(), new_len).unwrap();
    let is_full = builder.build_int_compare(IntPredicate::EQ, new_len, i64_type.const_int(4096, false), "is_full").unwrap();
    let flush_bb = context.append_basic_block(std_print_str, "flush");
    let next_bb = context.append_basic_block(std_print_str, "next");
    builder.build_conditional_branch(is_full, flush_bb, next_bb).unwrap();
    builder.position_at_end(flush_bb);
    builder.build_call(std_flush, &[], "flush").unwrap();
    builder.build_unconditional_branch(next_bb).unwrap();
    builder.position_at_end(next_bb);
    let next_s = unsafe { builder.build_gep(i8_type, s_ptr, &[i64_type.const_int(1, false)], "next_s").unwrap() };
    builder.build_store(s_ptr_alloca, next_s).unwrap();
    builder.build_unconditional_branch(loop_bb).unwrap();
    builder.position_at_end(end_bb);
    builder.build_return(None).unwrap();

    // std_print_num
    let bb = context.append_basic_block(std_print_num, "entry");
    builder.position_at_end(bb);
    let num_val = std_print_num.get_nth_param(0).unwrap().into_float_value();
    let temp_buf = builder.build_alloca(i8_type.array_type(64), "tmp_buf").unwrap();
    let fmt = builder.build_global_string_ptr("%.2f", "fmt").unwrap();
    let buf_cast = builder.build_pointer_cast(temp_buf, i8_ptr_type, "buf_cast").unwrap();
    builder.build_call(sprintf, &[buf_cast.into(), fmt.as_pointer_value().into(), num_val.into()], "sprintf").unwrap();
    builder.build_call(std_print_str, &[buf_cast.into()], "print_str").unwrap();
    builder.build_return(None).unwrap();

    // std_print_int
    let bb = context.append_basic_block(std_print_int, "entry");
    builder.position_at_end(bb);
    let num_val = std_print_int.get_nth_param(0).unwrap().into_int_value();
    let temp_buf = builder.build_alloca(i8_type.array_type(64), "tmp_buf").unwrap();
    let fmt = builder.build_global_string_ptr("%lld", "fmt_int").unwrap();
    let buf_cast = builder.build_pointer_cast(temp_buf, i8_ptr_type, "buf_cast").unwrap();
    builder.build_call(sprintf, &[buf_cast.into(), fmt.as_pointer_value().into(), num_val.into()], "sprintf").unwrap();
    builder.build_call(std_print_str, &[buf_cast.into()], "print_str").unwrap();
    builder.build_return(None).unwrap();

    // std_read_line
    let bb = context.append_basic_block(std_read_line, "entry");
    builder.position_at_end(bb);
    let i_alloca = builder.build_alloca(i64_type, "i").unwrap();
    builder.build_store(i_alloca, i64_type.const_zero()).unwrap();
    let loop_bb = context.append_basic_block(std_read_line, "loop");
    let end_bb = context.append_basic_block(std_read_line, "end");
    builder.build_unconditional_branch(loop_bb).unwrap();
    builder.position_at_end(loop_bb);
    let i_val = builder.build_load(i64_type, i_alloca, "i_val").unwrap().into_int_value();
    let is_max = builder.build_int_compare(IntPredicate::SGE, i_val, i64_type.const_int(4095, false), "is_max").unwrap();
    let read_bb = context.append_basic_block(std_read_line, "read");
    builder.build_conditional_branch(is_max, end_bb, read_bb).unwrap();
    builder.position_at_end(read_bb);
    let c_int = builder.build_call(getchar, &[], "getchar").unwrap().try_as_basic_value().left().unwrap().into_int_value();
    let is_eof = builder.build_int_compare(IntPredicate::SLT, c_int, i32_type.const_int(0, false), "is_eof").unwrap();
    let check_nl_bb = context.append_basic_block(std_read_line, "check_nl");
    builder.build_conditional_branch(is_eof, end_bb, check_nl_bb).unwrap();
    builder.position_at_end(check_nl_bb);
    let is_nl = builder.build_int_compare(IntPredicate::EQ, c_int, i32_type.const_int(10, false), "is_nl").unwrap();
    let store_bb = context.append_basic_block(std_read_line, "store");
    builder.build_conditional_branch(is_nl, end_bb, store_bb).unwrap();
    builder.position_at_end(store_bb);
    let c_byte = builder.build_int_truncate(c_int, i8_type, "c_byte").unwrap();
    let gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_in_buf.as_pointer_value(), &[i64_type.const_zero(), i_val], "gep").unwrap() };
    builder.build_store(gep, c_byte).unwrap();
    let new_i = builder.build_int_add(i_val, i64_type.const_int(1, false), "new_i").unwrap();
    builder.build_store(i_alloca, new_i).unwrap();
    builder.build_unconditional_branch(loop_bb).unwrap();
    builder.position_at_end(end_bb);
    let final_i = builder.build_load(i64_type, i_alloca, "final_i").unwrap().into_int_value();
    let final_gep = unsafe { builder.build_gep(i8_type.array_type(4096), std_in_buf.as_pointer_value(), &[i64_type.const_zero(), final_i], "final_gep").unwrap() };
    builder.build_store(final_gep, i8_type.const_zero()).unwrap();
    builder.build_return(Some(&final_i)).unwrap();

    let libc = Libc {
        printf, scanf, sprintf, pow, sin, cos, round, floor, ceil, malloc, strlen, strcpy, strcat,
        write: write_fn, std_flush, std_print_str, std_print_num, std_print_int,
        std_read_line, std_in_buf: std_in_buf.as_pointer_value(), getchar, strtoll, strtod,
    };

    let mut aliases = std::collections::HashMap::new();
    for item in &global_program.items {
        if let ast::Item::Alias(alias) = item { aliases.insert(alias.name.clone(), alias.body.clone()); }
    }

    let mut user_functions = std::collections::HashMap::new();
    for item in &global_program.items {
        if let ast::Item::Func(func) = item {
            let fn_type = f64_type.fn_type(&vec![f64_type.into(); func.args.len()], false);
            let llvm_name = if func.name == "main" { "xlang_main" } else { &func.name };
            user_functions.insert(func.name.clone(), (module.add_function(llvm_name, fn_type, None), func.clone()));
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
            gen_stmt(&context, &builder, &module, *llvm_fn, stmt, &aliases, &user_functions, &libc, &mut vars, &mut loop_stack);
        }
        if builder.get_insert_block().unwrap().get_terminator().is_none() {
            builder.build_return(Some(&f64_type.const_float(0.0))).unwrap();
        }
    }

    let main_fn = module.add_function("main", i32_type.fn_type(&[], false), None);
    builder.position_at_end(context.append_basic_block(main_fn, "entry"));
    if let Some((llvm_user_main, _)) = user_functions.get("main") {
        builder.build_call(*llvm_user_main, &[], "call_xlang_main").unwrap();
    }
    builder.build_call(libc.std_flush, &[], "final_flush").unwrap();
    builder.build_return(Some(&i32_type.const_int(0, false))).unwrap();

    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).unwrap();
    let target_machine = target.create_target_machine(&triple, "generic", "", OptimizationLevel::Aggressive, RelocMode::PIC, CodeModel::Default).unwrap();
    let pass_options = PassBuilderOptions::create();
    let _ = module.run_passes("default<O3>", &target_machine, pass_options);
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
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>, loop_stack: &mut Vec<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
) {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());

    match stmt {
        ast::Stmt::Break => { if let Some((_, after_bb)) = loop_stack.last() { builder.build_unconditional_branch(*after_bb).unwrap(); } }
        ast::Stmt::Continue => { if let Some((continue_bb, _)) = loop_stack.last() { builder.build_unconditional_branch(*continue_bb).unwrap(); } }
        ast::Stmt::For { init, condition, increment, body } => {
            if let Some(i) = init { gen_stmt(context, builder, module, current_fn, i, aliases, user_functions, libc, vars, loop_stack); }
            let cond_bb = context.append_basic_block(current_fn, "for_cond");
            let body_bb = context.append_basic_block(current_fn, "for_body");
            let inc_bb = context.append_basic_block(current_fn, "for_inc");
            let after_bb = context.append_basic_block(current_fn, "for_after");
            builder.build_unconditional_branch(cond_bb).unwrap();
            builder.position_at_end(cond_bb);
            if let Some(cond) = condition {
                let left = gen_expr(context, builder, module, &cond.0, aliases, user_functions, libc, vars);
                let right = gen_expr(context, builder, module, &cond.2, aliases, user_functions, libc, vars);
                let cmp = if left.is_int_value() && right.is_int_value() {
                    let l = left.into_int_value(); let r = right.into_int_value();
                    match cond.1.as_str() {
                        "==" => builder.build_int_compare(IntPredicate::EQ, l, r, "cmp").unwrap(),
                        "!=" => builder.build_int_compare(IntPredicate::NE, l, r, "cmp").unwrap(),
                        "<" => builder.build_int_compare(IntPredicate::SLT, l, r, "cmp").unwrap(),
                        ">" => builder.build_int_compare(IntPredicate::SGT, l, r, "cmp").unwrap(),
                        "<=" => builder.build_int_compare(IntPredicate::SLE, l, r, "cmp").unwrap(),
                        ">=" => builder.build_int_compare(IntPredicate::SGE, l, r, "cmp").unwrap(),
                        _ => builder.build_int_compare(IntPredicate::EQ, l, r, "cmp").unwrap(),
                    }
                } else {
                    let l = to_float(builder, left, f64_type);
                    let r = to_float(builder, right, f64_type);
                    match cond.1.as_str() {
                        "==" => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                        "!=" => builder.build_float_compare(FloatPredicate::ONE, l, r, "cmp").unwrap(),
                        "<" => builder.build_float_compare(FloatPredicate::OLT, l, r, "cmp").unwrap(),
                        ">" => builder.build_float_compare(FloatPredicate::OGT, l, r, "cmp").unwrap(),
                        "<=" => builder.build_float_compare(FloatPredicate::OLE, l, r, "cmp").unwrap(),
                        ">=" => builder.build_float_compare(FloatPredicate::OGE, l, r, "cmp").unwrap(),
                        _ => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                    }
                };
                builder.build_conditional_branch(cmp, body_bb, after_bb).unwrap();
            } else { builder.build_unconditional_branch(body_bb).unwrap(); }
            builder.position_at_end(body_bb);
            loop_stack.push((inc_bb, after_bb));
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(inc_bb).unwrap(); }
            builder.position_at_end(inc_bb);
            if let Some(inc) = increment { gen_stmt(context, builder, module, current_fn, inc, aliases, user_functions, libc, vars, loop_stack); }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::While { condition, body } => {
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
                let l = to_float(builder, left, f64_type);
                let r = to_float(builder, right, f64_type);
                match condition.1.as_str() {
                    "==" => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                    "!=" => builder.build_float_compare(FloatPredicate::ONE, l, r, "cmp").unwrap(),
                    "<" => builder.build_float_compare(FloatPredicate::OLT, l, r, "cmp").unwrap(),
                    ">" => builder.build_float_compare(FloatPredicate::OGT, l, r, "cmp").unwrap(),
                    "<=" => builder.build_float_compare(FloatPredicate::OLE, l, r, "cmp").unwrap(),
                    ">=" => builder.build_float_compare(FloatPredicate::OGE, l, r, "cmp").unwrap(),
                    _ => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                }
            };
            builder.build_conditional_branch(cmp, loop_bb, after_bb).unwrap();
            builder.position_at_end(loop_bb);
            loop_stack.push((cond_bb, after_bb));
            for s in body { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack); } }
            loop_stack.pop();
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(cond_bb).unwrap(); }
            builder.position_at_end(after_bb);
        }
        ast::Stmt::Assign { name, value } => {
            if name.starts_with('*') {
                let ptr_name = &name[1..];
                let ptr = if let Some(VarInfo::Pointer(p)) = vars.get(ptr_name) { *p }
                          else if let Some(VarInfo::Scalar(p)) = vars.get(ptr_name) { *p }
                          else { panic!("Pointer '{}' not found", ptr_name); };
                let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
                let ptr_val_bv = builder.build_load(i8_ptr_type, ptr, "ptr_load").unwrap();
                let ptr_val = match ptr_val_bv { BasicValueEnum::PointerValue(p) => p, _ => panic!("Expected pointer") };
                builder.build_store(ptr_val, val).unwrap();
                return;
            }

            if let ast::Expr::Array(elements) = value {
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
            } else if let ast::Expr::String(s) = value {
                let global_str = builder.build_global_string_ptr(s, "str").unwrap();
                let len = builder.build_call(libc.strlen, &[global_str.as_pointer_value().into()], "len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let total_len = builder.build_int_add(len, i64_type.const_int(1, false), "total").unwrap();
                let malloc_ptr = builder.build_call(libc.malloc, &[total_len.into()], "malloc").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                builder.build_call(libc.strcpy, &[malloc_ptr.into(), global_str.as_pointer_value().into()], "strcpy").unwrap();
                
                let alloca = builder.build_alloca(i8_ptr_type, name).unwrap();
                builder.build_store(alloca, malloc_ptr).unwrap();
                vars.insert(name.clone(), VarInfo::String(alloca));
            } else {
                let val = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
                if val.is_int_value() {
                    let alloca = if let Some(VarInfo::Int(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i64_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Int(ptr)); ptr };
                    builder.build_store(alloca, val).unwrap();
                } else if let ast::Expr::Ref(_) = value {
                    let alloca = if let Some(VarInfo::Pointer(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Pointer(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else if val.is_pointer_value() {
                    let alloca = if let Some(VarInfo::String(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(i8_ptr_type, name).unwrap(); vars.insert(name.clone(), VarInfo::String(ptr)); ptr };
                    builder.build_store(alloca, val.into_pointer_value()).unwrap();
                } else {
                    let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(name) { *ptr } 
                                 else { let ptr = builder.build_alloca(f64_type, name).unwrap(); vars.insert(name.clone(), VarInfo::Scalar(ptr)); ptr };
                    let f = to_float(builder, val, f64_type);
                    builder.build_store(alloca, f).unwrap();
                }
            }
        }
        ast::Stmt::IndexAssign { name, index, value } => {
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
        }
        ast::Stmt::Return { value } => {
            let val_raw = gen_expr(context, builder, module, value, aliases, user_functions, libc, vars);
            let val = to_float(builder, val_raw, f64_type);
            builder.build_return(Some(&val)).unwrap();
        }
        ast::Stmt::Expr(expr) => { gen_expr(context, builder, module, expr, aliases, user_functions, libc, vars); }
        ast::Stmt::MacroCall { name } => {
            if let Some(body) = aliases.get(name) { for s in body { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack); } }
        }
        ast::Stmt::Switch { expr, cases, default } => {
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
        ast::Stmt::If { condition, then_branch, else_branch } => {
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
                let l = to_float(builder, left, f64_type);
                let r = to_float(builder, right, f64_type);
                match condition.1.as_str() {
                    "==" => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                    "!=" => builder.build_float_compare(FloatPredicate::ONE, l, r, "cmp").unwrap(),
                    "<" => builder.build_float_compare(FloatPredicate::OLT, l, r, "cmp").unwrap(),
                    ">" => builder.build_float_compare(FloatPredicate::OGT, l, r, "cmp").unwrap(),
                    "<=" => builder.build_float_compare(FloatPredicate::OLE, l, r, "cmp").unwrap(),
                    ">=" => builder.build_float_compare(FloatPredicate::OGE, l, r, "cmp").unwrap(),
                    _ => builder.build_float_compare(FloatPredicate::OEQ, l, r, "cmp").unwrap(),
                }
            };
            let then_bb = context.append_basic_block(current_fn, "then");
            let merge_bb = context.append_basic_block(current_fn, "merge");
            let else_bb = if else_branch.is_some() { context.append_basic_block(current_fn, "else") } else { merge_bb };
            builder.build_conditional_branch(cmp, then_bb, else_bb).unwrap();
            builder.position_at_end(then_bb);
            for s in then_branch { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack); } }
            if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(merge_bb).unwrap(); }
            if let Some(else_stmts) = else_branch {
                builder.position_at_end(else_bb);
                for s in else_stmts { if builder.get_insert_block().unwrap().get_terminator().is_none() { gen_stmt(context, builder, module, current_fn, s, aliases, user_functions, libc, vars, loop_stack); } }
                if builder.get_insert_block().unwrap().get_terminator().is_none() { builder.build_unconditional_branch(merge_bb).unwrap(); }
            }
            builder.position_at_end(merge_bb);
        }
    }
}

fn gen_expr<'ctx>(
    context: &'ctx Context, builder: &Builder<'ctx>, module: &Module<'ctx>,
    expr: &ast::Expr, aliases: &HashMap<String, Vec<ast::Stmt>>, user_functions: &HashMap<String, (FunctionValue<'ctx>, ast::FuncDecl)>,
    libc: &Libc<'ctx>, vars: &mut HashMap<String, VarInfo<'ctx>>,
) -> BasicValueEnum<'ctx> {
    let f64_type = context.f64_type();
    let i32_type = context.i32_type();
    let i64_type = context.i64_type();
    let i8_ptr_type = context.ptr_type(AddressSpace::default());
    
    match expr {
        ast::Expr::Int(n) => i64_type.const_int(*n as u64, false).into(),
        ast::Expr::Float(f) => f64_type.const_float(*f).into(),
        ast::Expr::String(s) => { let str_val = builder.build_global_string_ptr(s, "str").unwrap(); str_val.as_pointer_value().into() }
        ast::Expr::Ref(inner) => {
            if let ast::Expr::Identifier(name) = &**inner {
                if let Some(VarInfo::Scalar(ptr)) = vars.get(name) { return (*ptr).into(); }
                if let Some(VarInfo::Int(ptr)) = vars.get(name) { return (*ptr).into(); }
            }
            panic!("Cannot take address of non-identifier");
        }
        ast::Expr::Deref(inner) => {
            let val = gen_expr(context, builder, module, inner, aliases, user_functions, libc, vars);
            if let BasicValueEnum::PointerValue(ptr) = val {
                builder.build_load(f64_type, ptr, "deref_load").unwrap().into()
            } else { panic!("Dereference of non-pointer"); }
        }
        ast::Expr::Identifier(name) => { 
            if let Some(info) = vars.get(name) { 
                match info { 
                    VarInfo::Scalar(ptr) => builder.build_load(f64_type, *ptr, name).unwrap(), 
                    VarInfo::Int(ptr) => builder.build_load(i64_type, *ptr, name).unwrap(),
                    VarInfo::String(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    VarInfo::Pointer(ptr) => builder.build_load(i8_ptr_type, *ptr, name).unwrap(),
                    _ => panic!("Unsupported variable type for '{}'", name)
                } 
            } else { f64_type.const_float(0.0).into() } 
        }
        ast::Expr::Index { name, index } => {
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
        }
        ast::Expr::Array(_) => { f64_type.const_float(0.0).into() }
        ast::Expr::BinaryOp { left, op, right } => {
            let left_val = gen_expr(context, builder, module, left, aliases, user_functions, libc, vars);
            let right_val = gen_expr(context, builder, module, right, aliases, user_functions, libc, vars);
            
            if left_val.is_pointer_value() && right_val.is_pointer_value() && op == "+" {
                let l_ptr = left_val.into_pointer_value();
                let r_ptr = right_val.into_pointer_value();
                let l_len = builder.build_call(libc.strlen, &[l_ptr.into()], "l_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let r_len = builder.build_call(libc.strlen, &[r_ptr.into()], "r_len").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                let total_len = builder.build_int_add(l_len, r_len, "total").unwrap();
                let total_len = builder.build_int_add(total_len, i64_type.const_int(1, false), "total1").unwrap();
                let new_buf = builder.build_call(libc.malloc, &[total_len.into()], "malloc_str").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                builder.build_call(libc.strcpy, &[new_buf.into(), l_ptr.into()], "strcpy").unwrap();
                builder.build_call(libc.strcat, &[new_buf.into(), r_ptr.into()], "strcat").unwrap();
                return new_buf.into();
            }

            if left_val.is_int_value() && right_val.is_int_value() {
                let l = left_val.into_int_value();
                let r = right_val.into_int_value();
                match op.as_str() {
                    "+" => builder.build_int_add(l, r, "addtmp").unwrap().into(),
                    "-" => builder.build_int_sub(l, r, "subtmp").unwrap().into(),
                    "*" => builder.build_int_mul(l, r, "multmp").unwrap().into(),
                    "/" => builder.build_int_signed_div(l, r, "divtmp").unwrap().into(),
                    "%" => builder.build_int_signed_rem(l, r, "remtmp").unwrap().into(),
                    "^" => builder.build_xor(l, r, "xortmp").unwrap().into(),
                    _ => i64_type.const_int(0, false).into(),
                }
            } else {
                let l_f = to_float(builder, left_val, f64_type);
                let r_f = to_float(builder, right_val, f64_type);
                
                match op.as_str() {
                    "+" => builder.build_float_add(l_f, r_f, "addtmp").unwrap().into(),
                    "-" => builder.build_float_sub(l_f, r_f, "subtmp").unwrap().into(),
                    "*" => builder.build_float_mul(l_f, r_f, "multmp").unwrap().into(),
                    "/" => builder.build_float_div(l_f, r_f, "divtmp").unwrap().into(),
                    "%" => builder.build_float_rem(l_f, r_f, "remtmp").unwrap().into(),
                    _ => f64_type.const_float(0.0).into(),
                }
            }
        }
        ast::Expr::MacroCall(name) => {
            if let Some(body) = aliases.get(name) { for s in body { gen_stmt(context, builder, module, module.get_functions().next().unwrap(), s, aliases, user_functions, libc, vars, &mut Vec::new()); } }
            f64_type.const_float(0.0).into()
        }
        ast::Expr::Call { name, args } => {
            if let Some((llvm_fn, _)) = user_functions.get(name) {
                let mut llvm_args = Vec::new();
                for arg in args {
                    let val = gen_expr(context, builder, module, arg, aliases, user_functions, libc, vars);
                    let f_val = to_float(builder, val, f64_type);
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
                                builder.build_call(libc.std_print_str, &[str_ptr.as_pointer_value().into()], "print_str").unwrap();
                            }
                            _ => {
                                let val = gen_expr(context, builder, module, arg, aliases, user_functions, libc, vars);
                                if val.is_pointer_value() {
                                    builder.build_call(libc.std_print_str, &[val.into()], "print_str").unwrap();
                                } else if val.is_int_value() {
                                    builder.build_call(libc.std_print_int, &[val.into()], "print_int").unwrap();
                                } else {
                                    builder.build_call(libc.std_print_num, &[val.into()], "print_num").unwrap();
                                }
                            }
                        }
                    }
                    let nl_str = builder.build_global_string_ptr("\n", "nl").unwrap();
                    builder.build_call(libc.std_print_str, &[nl_str.as_pointer_value().into()], "nl").unwrap();
                    f64_type.const_float(0.0).into()
                }
                "ci" => {
                    if args.len() >= 2 {
                        if let ast::Expr::String(prompt) = &args[0] {
                            let fmt_global = builder.build_global_string_ptr(prompt.as_str(), "prompt").unwrap();
                            builder.build_call(libc.std_print_str, &[fmt_global.as_pointer_value().into()], "print_prompt").unwrap();
                            builder.build_call(libc.std_flush, &[], "flush_prompt").unwrap();
                        }
                        if let ast::Expr::Identifier(var_name) = &args[1] {
                            let len = builder.build_call(libc.std_read_line, &[], "read_line").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                            
                            let is_string = if let Some(VarInfo::String(_)) = vars.get(var_name.as_str()) { true } else { false };
                            let is_int = if let Some(VarInfo::Int(_)) = vars.get(var_name.as_str()) { true } else { false };
                            
                            let in_buf_ptr = builder.build_pointer_cast(libc.std_in_buf, i8_ptr_type, "in_buf_ptr").unwrap();
                            
                            if is_string || (!vars.contains_key(var_name.as_str())) {
                                let total_len = builder.build_int_add(len, i64_type.const_int(1, false), "total").unwrap();
                                let malloc_ptr = builder.build_call(libc.malloc, &[total_len.into()], "malloc").unwrap().try_as_basic_value().left().unwrap().into_pointer_value();
                                builder.build_call(libc.strcpy, &[malloc_ptr.into(), in_buf_ptr.into()], "strcpy").unwrap();
                                let alloca = builder.build_alloca(i8_ptr_type, var_name).unwrap();
                                builder.build_store(alloca, malloc_ptr).unwrap();
                                vars.insert(var_name.clone(), VarInfo::String(alloca));
                            } else if is_int {
                                let null_ptr = i8_ptr_type.const_null();
                                let int_val = builder.build_call(libc.strtoll, &[in_buf_ptr.into(), null_ptr.into(), i32_type.const_int(10, false).into()], "strtoll").unwrap().try_as_basic_value().left().unwrap().into_int_value();
                                let alloca = if let Some(VarInfo::Int(ptr)) = vars.get(var_name.as_str()) { *ptr } 
                                             else { let ptr = builder.build_alloca(i64_type, var_name).unwrap(); vars.insert(var_name.clone(), VarInfo::Int(ptr)); ptr };
                                builder.build_store(alloca, int_val).unwrap();
                            } else {
                                let null_ptr = i8_ptr_type.const_null();
                                let f_val = builder.build_call(libc.strtod, &[in_buf_ptr.into(), null_ptr.into()], "strtod").unwrap().try_as_basic_value().left().unwrap().into_float_value();
                                let alloca = if let Some(VarInfo::Scalar(ptr)) = vars.get(var_name.as_str()) { *ptr } 
                                             else { let ptr = builder.build_alloca(f64_type, var_name).unwrap(); vars.insert(var_name.clone(), VarInfo::Scalar(ptr)); ptr };
                                builder.build_store(alloca, f_val).unwrap();
                            }
                        }
                    }
                    f64_type.const_float(0.0).into()
                }
                "powr" => {
                    if args.len() >= 2 {
                        let base = to_float(builder, gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars), f64_type);
                        let exp = to_float(builder, gen_expr(context, builder, module, &args[1], aliases, user_functions, libc, vars), f64_type);
                        builder.build_call(libc.pow, &[base.into(), exp.into()], "pow_call").unwrap().try_as_basic_value().left().unwrap()
                    } else { f64_type.const_float(0.0).into() }
                }
                "sin" | "cosin" | "round" | "floor" | "ceil" => {
                    if args.len() >= 1 {
                        let val = to_float(builder, gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars), f64_type);
                        let func = match name.as_str() { "sin" => libc.sin, "cosin" => libc.cos, "round" => libc.round, "floor" => libc.floor, "ceil" => libc.ceil, _ => unreachable!() };
                        builder.build_call(func, &[val.into()], name.as_str()).unwrap().try_as_basic_value().left().unwrap()
                    } else { f64_type.const_float(0.0).into() }
                }
                "is-odd" | "is-even" => {
                    if args.len() >= 1 {
                        let val_i = match gen_expr(context, builder, module, &args[0], aliases, user_functions, libc, vars) {
                            BasicValueEnum::IntValue(i) => i,
                            BasicValueEnum::FloatValue(f) => builder.build_float_to_signed_int(f, i64_type, "tmp").unwrap(),
                            _ => panic!()
                        };
                        let rem = builder.build_int_signed_rem(val_i, i64_type.const_int(2, false), "rem").unwrap();
                        let cond = if name == "is-odd" { builder.build_int_compare(IntPredicate::NE, rem, i64_type.const_zero(), "is_odd").unwrap() } else { builder.build_int_compare(IntPredicate::EQ, rem, i64_type.const_zero(), "is_even").unwrap() };
                        builder.build_unsigned_int_to_float(cond, f64_type, "res").unwrap().into()
                    } else { f64_type.const_float(0.0).into() }
                }
                _ => f64_type.const_float(0.0).into(),
            }
        }
    }
}

fn resolve_project_files(path: &Path) -> Vec<PathBuf> {
    if path.is_file() { vec![path.to_path_buf()] } else { vec![] }
}
