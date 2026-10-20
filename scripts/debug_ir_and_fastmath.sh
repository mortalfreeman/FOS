#!/bin/bash
cd ~/FOS

echo "==> Добавление флага --dump-ir и fast-math для инструкций..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем --dump-ir в парсинг
content = content.replace(
    'let mut out_name = None;',
    'let mut out_name = None;\n    let mut dump_ir = false;'
)
content = content.replace(
    'else if args[i] == "--fast-math" { fast_math = true; i += 1; }',
    'else if args[i] == "--fast-math" { fast_math = true; i += 1; }\n        else if args[i] == "--dump-ir" { dump_ir = true; i += 1; }'
)

# 2. Применяем fast-math ко всем инструкциям
old_pass = """    let pass_options = PassBuilderOptions::create();"""
new_pass = """    if fast_math {
        let mut func = module.get_first_function();
        while let Some(f) = func {
            let mut bb = f.get_first_basic_block();
            while let Some(b) = bb {
                let mut inst = b.get_first_instruction();
                while let Some(i) = inst {
                    let opcode = i.get_opcode();
                    if opcode == inkwell::values::InstructionOpcode::FAdd 
                        || opcode == inkwell::values::InstructionOpcode::FSub
                        || opcode == inkwell::values::InstructionOpcode::FMul
                        || opcode == inkwell::values::InstructionOpcode::FDiv {
                        unsafe { i.set_fast_math_flags(true, true, true, true, true); }
                    }
                    inst = i.get_next_instruction();
                }
                bb = b.get_next_basic_block();
            }
            func = f.get_next_function();
        }
    }

    let pass_options = PassBuilderOptions::create();"""
content = content.replace(old_pass, new_pass)

# 3. Вывод IR
old_write = """    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();"""
new_write = """    if dump_ir {
        println!("{}", module.print_to_string().to_string());
    }

    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();"""
content = content.replace(old_write, new_write)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> Пересборка..."
cargo build --release -p xlang-compiler
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> Вывод LLVM IR для t_con.x..."
cd ~/test_crash
xc t_con.x --dump-ir -out t_con_bin
echo "--- Запуск ---"
./t_con_bin
echo "Код возврата: $?"
