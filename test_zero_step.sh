#!/bin/bash
cd ~/test_zero_full

echo "=== ТЕСТ 1: Просто числа и арифметика ==="
cat > test1.x << 'XLANG'
func main {
    a = 10;
    b = 20;
    c = a + b;
    con("Result: ", c);
}
XLANG

cp ~/FOS/libxstd.a .
xc test1.x -out test1
./test1
echo ""

echo "=== ТЕСТ 2: Массивы и циклы ==="
cat > test2.x << 'XLANG'
func main {
    arr = [10, 20, 30];
    sum = 0;
    for (i = 0; i < 3; i = i + 1) {
        sum = sum + arr[i];
    }
    con("Sum: ", sum);
}
XLANG

xc test2.x -out test2
./test2
echo ""

echo "=== ТЕСТ 3: Полная программа ==="
cat > test3.x << 'XLANG'
func main {
    name = "X-lang";
    greeting = "Hello, " + name + "!";
    con(greeting);
    con("Sum test bypassed");
}
XLANG

xc test3.x -out test3
./test3
