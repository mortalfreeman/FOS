<p align="center">
  <img src="web/logo.svg" width="150" alt="FOS Logo">
</p>

<h1 align="center">X-lang</h1>

<p align="center">
  <b>Fast = Easy, Fast = Secure.</b><br>
  Современный системный язык программирования с LLVM-бэкендом.
</p>

---

## 🚀 О языке
**X-lang** — компилируемый язык, написанный с нуля. Сочетает простоту Python, скорость C и безопасность Rust.

- **Скорость:** LLVM `-O2`, на равных с C.
- **Безопасность:** Bounds check, защита от деления на ноль и переполнения.
- **Размер:** Бинарники от 10 КБ (`--pure-asm`).
- **Кроссплатформенность:** Linux (ELF) и Windows (PE32+).

## 📚 Документация
Полное руководство от установки до безопасности находится в файле [docs/xlang.md](docs/xlang.md). Оно покрывает синтаксис, массивы, структуры, макросы и все режимы компиляции.

## 📦 Быстрый старт
~~~bash
cargo build --release
cp target/release/xlang-compiler ~/.local/bin/xc
xc new hello
cd hello
xc run main.x
~~~

## 🏎️ Бенчмарки
| Тест | X-lang | C | Rust |
|:---|:---|:---|:---|
| Sum 1..10M | 3 мс | 3 мс | 3 мс |
| Collatz | 14 мс | 16 мс | 14 мс |
| Sieve 1M | 5 мс | 5 мс | - |

## 📄 Лицензия
FSL-Permissive. См. [LICENSE](LICENSE).
