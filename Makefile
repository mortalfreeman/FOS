.PHONY: all build rust clean install

all: build

build: rust
	@echo "✅ Сборка FOS завершена!"

rust:
	@echo "🔨 Сборка компилятора xc и LSP-сервера..."
	cargo build --release

install: build
	@echo "📦 Установка в ~/.local/bin..."
	mkdir -p ~/.local/bin
	cp target/release/xlang-compiler ~/.local/bin/xc
	cp target/release/xlang-lsp ~/.local/bin/xlang-lsp
	@echo "✅ Установка завершена!"

clean:
	@echo "🧹 Очистка..."
	cargo clean
