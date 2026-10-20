#!/bin/bash
set -e

BENCH=~/benchmark_xlang
rm -rf "$BENCH"
mkdir -p "$BENCH"
cd "$BENCH"

# Функция для замеров (возвращает миллисекунды)
now_ms() { echo $(($(date +%s%N) / 1000000)); }

echo "=== ПОДГОТОВКА БЕНЧМАРКА ==="
echo "Генерация исходников для 8 языков и 5 тестов..."

# ==========================================
# ТЕСТ 1: Hello World
# ==========================================
mkdir -p t1
cd t1
cat > main.c << 'EOF'
#include <stdio.h>
int main(){printf("Hello, World!\n");return 0;}
EOF
cat > main.cpp << 'EOF'
#include <iostream>
int main(){std::cout<<"Hello, World!"<<std::endl;return 0;}
EOF
cat > main.py << 'EOF'
print("Hello, World!")
EOF
cat > main.sh << 'EOF'
#!/bin/bash
echo "Hello, World!"
EOF
cat > Main.java << 'EOF'
public class Main{public static void main(String[]a){System.out.println("Hello, World!");}}
EOF
cat > main.x << 'EOF'
.use GOIO
func main {
    con("Hello, World!");
}
EOF
cat > main.asm << 'EOF'
section .data
msg db "Hello, World!",10
len equ $ - msg
section .text
global _start
_start:
mov rax,1
mov rdi,1
mov rsi,msg
mov rdx,len
syscall
mov rax,60
xor rdi,rdi
syscall
EOF
cd ..

# ==========================================
# ТЕСТ 2: Сумма 0..10 000 000 (Цикл)
# ==========================================
mkdir -p t2
cd t2
cat > main.c << 'EOF'
#include <stdio.h>
int main(){long long s=0;for(long long i=0;i<10000000;i++)s+=i;printf("%lld\n",s);return 0;}
EOF
cat > main.cpp << 'EOF'
#include <iostream>
int main(){long long s=0;for(long long i=0;i<10000000;i++)s+=i;std::cout<<s<<std::endl;return 0;}
EOF
cat > main.py << 'EOF'
s=0
for i in range(10000000): s+=i
print(s)
EOF
cat > main.sh << 'EOF'
#!/bin/bash
s=0
for ((i=0;i<10000000;i++)); do s=$((s+i)); done
echo $s
EOF
cat > Main.java << 'EOF'
public class Main{public static void main(String[]a){long s=0;for(long i=0;i<10000000;i++)s+=i;System.out.println(s);}}
EOF
cat > main.x << 'EOF'
.use GOIO
func main {
    sum = 0;
    for (i = 0; i < 10000000; i = i + 1) {
        sum = sum + i;
    }
    con(sum);
}
EOF
cat > main.asm << 'EOF'
extern printf
section .data
fmt db "%ld",10,0
section .text
global _start
_start:
xor rax,rax
xor rcx,rcx
mov rbx,10000000
.l:
add rax,rcx
inc rcx
cmp rcx,rbx
jl .l
mov rsi,rax
lea rdi,[rel fmt]
xor eax,eax
call printf wrt ..plt
mov rax,60
xor rdi,rdi
syscall
EOF
cd ..

# ==========================================
# ТЕСТ 3: Фибоначчи (итеративный, n=40)
# ==========================================
mkdir -p t3
cd t3
cat > main.c << 'EOF'
#include <stdio.h>
int main(){long long a=0,b=1,t;for(int i=0;i<40;i++){t=a+b;a=b;b=t;}printf("%lld\n",a);return 0;}
EOF
cat > main.cpp << 'EOF'
#include <iostream>
int main(){long long a=0,b=1,t;for(int i=0;i<40;i++){t=a+b;a=b;b=t;}std::cout<<a<<std::endl;return 0;}
EOF
cat > main.py << 'EOF'
a,b=0,1
for i in range(40): a,b=b,a+b
print(a)
EOF
cat > main.sh << 'EOF'
#!/bin/bash
a=0; b=1
for ((i=0;i<40;i++)); do t=$((a+b)); a=$b; b=$t; done
echo $a
EOF
cat > Main.java << 'EOF'
public class Main{public static void main(String[]a){long x=0,y=1,t;for(int i=0;i<40;i++){t=x+y;x=y;y=t;}System.out.println(x);}}
EOF
cat > main.x << 'EOF'
.use GOIO
func fib(n) {
    a = 0;
    b = 1;
    for (i = 0; i < n; i = i + 1) {
        t = a + b;
        a = b;
        b = t;
    }
    return a;
}
func main {
    con(fib(40));
}
EOF
cat > main.asm << 'EOF'
extern printf
section .data
fmt db "%ld",10,0
section .text
global _start
_start:
xor rax,rax
mov rbx,1
xor rcx,rcx
.l:
cmp rcx,40
jge .d
mov rdx,rax
add rdx,rbx
mov rax,rbx
mov rbx,rdx
inc rcx
jmp .l
.d:
mov rsi,rax
lea rdi,[rel fmt]
xor eax,eax
call printf wrt ..plt
mov rax,60
xor rdi,rdi
syscall
EOF
cd ..

# ==========================================
# ТЕСТ 4: Сортировка массива (100 элементов)
# ==========================================
mkdir -p t4
cd t4
cat > main.c << 'EOF'
#include <stdio.h>
int main(){int a[100];for(int i=0;i<100;i++)a[i]=100-i;for(int i=0;i<100;i++)for(int j=0;j<99;j++)if(a[j]>a[j+1]){int t=a[j];a[j]=a[j+1];a[j+1]=t;}long s=0;for(int i=0;i<100;i++)s+=a[i];printf("%ld\n",s);return 0;}
EOF
cat > main.cpp << 'EOF'
#include <iostream>
int main(){int a[100];for(int i=0;i<100;i++)a[i]=100-i;for(int i=0;i<100;i++)for(int j=0;j<99;j++)if(a[j]>a[j+1]){int t=a[j];a[j]=a[j+1];a[j+1]=t;}long s=0;for(int i=0;i<100;i++)s+=a[i];std::cout<<s<<std::endl;return 0;}
EOF
cat > main.py << 'EOF'
a=list(range(100,0,-1))
for i in range(100):
  for j in range(99):
    if a[j]>a[j+1]: a[j],a[j+1]=a[j+1],a[j]
print(sum(a))
EOF
cat > main.sh << 'EOF'
#!/bin/bash
for ((i=0;i<100;i++)); do a[$i]=$((100-i)); done
for ((i=0;i<100;i++)); do
  for ((j=0;j<99;j++)); do
    if [ ${a[$j]} -gt ${a[$((j+1))]} ]; then
      t=${a[$j]}; a[$j]=${a[$((j+1))]}; a[$((j+1))]=$t
    fi
  done
done
s=0
for ((i=0;i<100;i++)); do s=$((s+${a[$i]})); done
echo $s
EOF
cat > Main.java << 'EOF'
public class Main{public static void main(String[]a){int[]x=new int[100];for(int i=0;i<100;i++)x[i]=100-i;for(int i=0;i<100;i++)for(int j=0;j<99;j++)if(x[j]>x[j+1]){int t=x[j];x[j]=x[j+1];x[j+1]=t;}long s=0;for(int i=0;i<100;i++)s+=x[i];System.out.println(s);}}
EOF
cat > main.x << 'EOF'
.use GOIO
func main {
    arr = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    for (i = 0; i < 100; i = i + 1) {
        arr[i] = 100 - i;
    }
    for (i = 0; i < 100; i = i + 1) {
        for (j = 0; j < 99; j = j + 1) {
            if (arr[j] > arr[j+1]) {
                t = arr[j];
                arr[j] = arr[j+1];
                arr[j+1] = t;
            }
        }
    }
    sum = 0;
    for (i = 0; i < 100; i = i + 1) {
        sum = sum + arr[i];
    }
    con(sum);
}
EOF
cd ..

# ==========================================
# ТЕСТ 5: Вложенные циклы (1000 x 1000)
# ==========================================
mkdir -p t5
cd t5
cat > main.c << 'EOF'
#include <stdio.h>
int main(){long long s=0;for(long long i=0;i<1000;i++)for(long long j=0;j<1000;j++)s+=i*j;printf("%lld\n",s);return 0;}
EOF
cat > main.cpp << 'EOF'
#include <iostream>
int main(){long long s=0;for(long long i=0;i<1000;i++)for(long long j=0;j<1000;j++)s+=i*j;std::cout<<s<<std::endl;return 0;}
EOF
cat > main.py << 'EOF'
s=0
for i in range(1000):
  for j in range(1000): s+=i*j
print(s)
EOF
cat > main.sh << 'EOF'
#!/bin/bash
s=0
for ((i=0;i<1000;i++)); do
  for ((j=0;j<1000;j++)); do s=$((s+i*j)); done
done
echo $s
EOF
cat > Main.java << 'EOF'
public class Main{public static void main(String[]a){long s=0;for(int i=0;i<1000;i++)for(int j=0;j<1000;j++)s+=(long)i*j;System.out.println(s);}}
EOF
cat > main.x << 'EOF'
.use GOIO
func main {
    sum = 0;
    for (i = 0; i < 1000; i = i + 1) {
        for (j = 0; j < 1000; j = j + 1) {
            sum = sum + i * j;
        }
    }
    con(sum);
}
EOF
cd ..

echo "=== СБОРКА И ТЕСТИРОВАНИЕ ==="
echo ""

# Массив для сбора результатов
declare -A COMPILE_TIME
declare -A BINARY_SIZE
declare -A EXEC_TIME

run_test() {
    local test=$1
    local name=$2
    local dir="t$test"
    cd "$BENCH/$dir"

    # C
    local t_start=$(date +%s%N)
    gcc -O3 main.c -o main_c 2>/dev/null
    local t_end=$(date +%s%N)
    COMPILE_TIME["$test,C"]=$(( (t_end-t_start)/1000000 ))
    BINARY_SIZE["$test,C"]=$(stat -c%s main_c)

    # C++
    t_start=$(date +%s%N)
    g++ -O3 main.cpp -o main_cpp 2>/dev/null
    t_end=$(date +%s%N)
    COMPILE_TIME["$test,C++"]=$(( (t_end-t_start)/1000000 ))
    BINARY_SIZE["$test,C++"]=$(stat -c%s main_cpp)

    # Java
    t_start=$(date +%s%N)
    javac Main.java 2>/dev/null
    t_end=$(date +%s%N)
    COMPILE_TIME["$test,Java"]=$(( (t_end-t_start)/1000000 ))
    BINARY_SIZE["$test,Java"]=$(stat -c%s Main.class)

    # Python (без компиляции)
    COMPILE_TIME["$test,Python"]=0
    BINARY_SIZE["$test,Python"]=$(stat -c%s main.py)

    # Shell (без компиляции)
    COMPILE_TIME["$test,Shell"]=0
    BINARY_SIZE["$test,Shell"]=$(stat -c%s main.sh)

    # X-lang
    t_start=$(date +%s%N)
    xc main.x -out main_x 2>/dev/null >/dev/null
    t_end=$(date +%s%N)
    COMPILE_TIME["$test,X-lang"]=$(( (t_end-t_start)/1000000 ))
    BINARY_SIZE["$test,X-lang"]=$(stat -c%s main_x)

    # NASM (только для тестов, где нет сложных структур данных)
    if [ "$test" != "4" ]; then
        t_start=$(date +%s%N)
        nasm -f elf64 main.asm -o main_nasm.o 2>/dev/null
        ld main_nasm.o -o main_nasm -lc -dynamic-linker /lib64/ld-linux-x86-64.so.2 2>/dev/null || ld main_nasm.o -o main_nasm 2>/dev/null
        t_end=$(date +%s%N)
        COMPILE_TIME["$test,NASM"]=$(( (t_end-t_start)/1000000 ))
        BINARY_SIZE["$test,NASM"]=$(stat -c%s main_nasm 2>/dev/null || echo 0)
    fi

    # Замер выполнения (3 раза, берем минимум)
    measure_exec() {
        local cmd=$1
        local min=999999
        for r in 1 2 3; do
            local s=$(date +%s%N)
            eval "$cmd" > /dev/null 2>&1
            local e=$(date +%s%N)
            local ms=$(( (e-s)/1000000 ))
            if [ $ms -lt $min ]; then min=$ms; fi
        done
        echo $min
    }

    EXEC_TIME["$test,C"]=$(measure_exec "./main_c")
    EXEC_TIME["$test,C++"]=$(measure_exec "./main_cpp")
    EXEC_TIME["$test,Java"]=$(measure_exec "java Main")
    EXEC_TIME["$test,Python"]=$(measure_exec "python3 main.py")
    EXEC_TIME["$test,Shell"]=$(measure_exec "bash main.sh")
    EXEC_TIME["$test,X-lang"]=$(measure_exec "./main_x")
    if [ "$test" != "4" ]; then
        EXEC_TIME["$test,NASM"]=$(measure_exec "./main_nasm")
    fi

    cd "$BENCH"
}

for t in 1 2 3 4 5; do
    case $t in
        1) NAME="Hello World" ;;
        2) NAME="Sum 0..10M" ;;
        3) NAME="Fibonacci(40)" ;;
        4) NAME="Bubble Sort (100)" ;;
        5) NAME="Nested 1000x1000" ;;
    esac
    echo "Тестируем: $NAME..."
    run_test $t "$NAME"
done

echo ""
echo "========================================"
echo "📊 РЕЗУЛЬТАТЫ БЕНЧМАРКА"
echo "========================================"
echo ""

printf "%-10s | %-12s | %-14s | %-10s\n" "Язык" "Компиляция(мс)" "Размер(байт)" "Время(мс)"
printf "%-10s-+-%-12s-+-%-14s-+-%-10s\n" "----------" "------------" "--------------" "----------"

for t in 1 2 3 4 5; do
    case $t in
        1) NAME="ТЕСТ 1: Hello World" ;;
        2) NAME="ТЕСТ 2: Sum 0..10M" ;;
        3) NAME="ТЕСТ 3: Fib(40)" ;;
        4) NAME="ТЕСТ 4: Bubble Sort" ;;
        5) NAME="ТЕСТ 5: Nested 1000x1000" ;;
    esac
    echo ""
    echo "▶ $NAME"
    printf "%-10s | %-12s | %-14s | %-10s\n" "----------" "------------" "--------------" "----------"

    for lang in "C" "C++" "X-lang" "Python" "Java" "Shell" "NASM"; do
        if [ ! -z "${COMPILE_TIME["$t,$lang"]}" ]; then
            printf "%-10s | %-12s | %-14s | %-10s\n" \
                "$lang" \
                "${COMPILE_TIME["$t,$lang"]}" \
                "${BINARY_SIZE["$t,$lang"]}" \
                "${EXEC_TIME["$t,$lang"]}"
        fi
    done
done

echo ""
echo "========================================"
echo "🎉 БЕНЧМАРК ЗАВЕРШЕН!"
echo "========================================"
