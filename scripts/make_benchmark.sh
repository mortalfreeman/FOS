#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Создание библиотеки sorted.xh..."
sudo bash -c 'cat > /usr/local/use/sorted.xh << "EOF"
#Define Header=sorted

! Библиотека сортировки (Bubble Sort) !
! Примечание: В будущем X-lang получит поддержку указателей и generics, !
! пока мы сортируем жестко заданные имена переменных. !
$alias sort_array {
    ! Сортировка массива arr размером size !
    for (i = 0; i < 5; i = i + 1) {
        for (j = 0; j < 4; j = j + 1) {
            if (arr[j] > arr[j + 1]) {
                temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
}
#END
EOF'

echo "==> 2. Создание папки для бенчмарков..."
mkdir -p ~/FOS/benchmarks
cd ~/FOS/benchmarks

# 1. C
cat > test.c << 'EOF'
#include <stdio.h>
int main() {
    double sum = 0;
    for(int i = 0; i < 50000000; i++) {
        sum += i * i;
    }
    printf("%.2f\n", sum);
    return 0;
}
EOF

# 2. C++
cat > test.cpp << 'EOF'
#include <iostream>
int main() {
    double sum = 0;
    for(int i = 0; i < 50000000; i++) {
        sum += i * i;
    }
    std::cout << sum << std::endl;
    return 0;
}
EOF

# 3. Rust
cat > test.rs << 'EOF'
fn main() {
    let mut sum: f64 = 0.0;
    for i in 0..50000000 {
        sum += (i * i) as f64;
    }
    println!("{:.2}", sum);
}
EOF

# 4. Python
cat > test.py << 'EOF'
sum = 0
for i in range(50000000):
    sum += i * i
print(f"{sum:.2f}")
EOF

# 5. X-lang
cat > test.x << 'EOF'
.use GOIO

func main {
    sum = 0;
    for (i = 0; i < 50000000; i = i + 1) {
        sum = sum + i * i;
    }
    con(sum);
}
EOF

echo "==> 3. Компиляция и запуск бенчмарков..."
echo "Пожалуйста, подождите, Python может занять 5-10 секунд..."

echo -e "\n--- 1. C (gcc -O3) ---"
gcc -O3 test.c -o test_c
time ./test_c

echo -e "\n--- 2. C++ (g++ -O3) ---"
g++ -O3 test.cpp -o test_cpp
time ./test_cpp

echo -e "\n--- 3. Rust (rustc -O) ---"
rustc -O test.rs -o test_rust
time ./test_rust

echo -e "\n--- 4. Python 3 (CPython) ---"
time python3 test.py

echo -e "\n--- 5. X-lang (LLVM -O3) ---"
xc test.x -out test_x
time ./test_x

echo -e "\n========================================="
echo "🎉 БЕНЧМАРК ЗАВЕРШЕН!"
echo "========================================="
