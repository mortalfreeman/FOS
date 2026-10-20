all:
	cargo build --release
	cd pep-qt && cmake -B build -S . && cmake --build build
install:
	mkdir -p ~/.local/bin
	cp target/release/xlang-compiler ~/.local/bin/xc
