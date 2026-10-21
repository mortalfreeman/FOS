<p align="center">
  <img src="web/logo.svg" width="150" alt="FOS Logo">
</p>

# FOS (Free Open Source Software)

Экосистема FOS включает:
- **X-lang** (компилятор `xc` на Rust + LLVM)
- **xlang-lsp** (сервер для Neovim)

## Сборка
```bash
git clone https://github.com/mortalfreeman/FOS.git
cd FOS
make install
```

---

## 🛡️ Безопасность (Security)
X-lang безопасен по умолчанию (Safe by default):
- **Bounds Checking:** выход за границы массива вызывает `Runtime Error`.
- **Division by Zero:** деление на ноль перехватывается до краха программы.
- **Integer Overflow:** переполнение `i64` вызывает `Runtime Error`.
Отключается флагом `--nosec` для максимальной скорости.
