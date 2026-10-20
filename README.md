<p align="center">
  <img src="web/logo.svg" width="150" alt="FOS Logo">
</p>

# FOS (Free Open Source Software)

Экосистема FOS включает в себя:
- **X-lang** (компилятор `xc` на Rust + LLVM)
- **PEP** (редактор на C++ Qt6)
- **xlang-lsp** (сервер для Neovim)

## Сборка

    cargo build --release
    cp target/release/xlang-compiler ~/.local/bin/xc
    cp target/release/xlang-lsp ~/.local/bin/xlang-lsp

## Лицензия
FSL-Permissive
