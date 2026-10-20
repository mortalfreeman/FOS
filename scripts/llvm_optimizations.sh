#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление LLVM Optimization Passes (default<O3>)..."
python3 - << 'PYEOF'
with open('xlang-compiler/src/main.rs', 'r') as f:
    content = f.read()

# 1. Добавляем импорт PassBuilderOptions
if 'use inkwell::passes::PassBuilderOptions;' not in content:
    content = content.replace(
        'use inkwell::targets::{Target, InitializationConfig, TargetMachine, RelocMode, CodeModel, FileType};',
        'use inkwell::targets::{Target, InitializationConfig, TargetMachine, RelocMode, CodeModel, FileType};\nuse inkwell::passes::PassBuilderOptions;'
    )

# 2. Включаем Fast Math для модуля (позволяет векторизацию)
if 'set_flags' not in content:
    content = content.replace(
        'let module = context.create_module("xlang_project");',
        'let module = context.create_module("xlang_project");\n    if let Err(e) = module.set_flags(inkwell::module::Flag::UnsafeFpMath) { eprintln!("Flag error: {:?}", e); }'
    )

# 3. Запускаем O3 пассы перед write_to_file
old_codegen = """    if let Err(e) = module.verify() { eprintln!("fatal: {:?}", e); process::exit(1); }
    let target = Target::from_triple(&TargetMachine::get_default_triple()).unwrap();
    let target_machine = target.create_target_machine(&TargetMachine::get_default_triple(), "generic", "", OptimizationLevel::Aggressive, RelocMode::PIC, CodeModel::Default).unwrap();
    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();"""

new_codegen = """    if let Err(e) = module.verify() { eprintln!("fatal: {:?}", e); process::exit(1); }
    
    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).unwrap();
    let target_machine = target.create_target_machine(&triple, "generic", "", OptimizationLevel::Aggressive, RelocMode::PIC, CodeModel::Default).unwrap();

    // ВОТ ОНО: Запускаем пассы оптимизации LLVM (mem2reg, loop-vectorize, etc.)
    let pass_options = PassBuilderOptions::create();
    if let Err(e) = module.run_passes("default<O3>", &target_machine, pass_options) {
        eprintln!("Optimization failed: {:?}", e);
    }

    target_machine.write_to_file(&module, FileType::Object, Path::new("output.o")).unwrap();"""

content = content.replace(old_codegen, new_codegen)

with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Пересборка компилятора..."
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Пересборка C++ бенчмарка (с честными i64, как в X-lang)..."
cd ~/FOS/benchmarks
cat > test_fair.cpp << 'EOF'
#include <iostream>
#include <cstdint>
int main() {
    double sum = 0;
    // Используем int64_t, чтобы избежать переполнения
    for(int64_t i = 0; i < 50000000; i++) {
        sum += (double)(i * i);
    }
    std::cout << sum << std::endl;
    return 0;
}
EOF

g++ -O3 test_fair.cpp -o test_cpp_fair
echo "Скомпилировано."

echo "==> 4. Запуск бенчмарка X-lang (с O3 пассами)..."
# Перекомпилируем X-lang тест
xc test.x -out test_x_opt

echo -e "\n--- C++ (Fair, int64) ---"
time ./test_cpp_fair

echo -e "\n--- X-lang (LLVM default<O3>) ---"
time ./test_x_opt
