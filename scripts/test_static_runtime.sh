#!/bin/bash
set -e
cd /tmp/test_static

echo "==> Проверка запуска статического бинарника..."
echo "--- Запуск ---"
./test_static
echo "Код возврата: $?"

echo ""
echo "==> Проверка через strace (если есть)..."
if command -v strace &> /dev/null; then
    strace -e trace=write,read,exit_group ./test_static 2>&1 | head -n 20
fi

echo ""
echo "==> Проверка через ldd..."
ldd ./test_static || echo "Нет динамических зависимостей (статика)!"
