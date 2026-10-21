#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Добавление флага is_lsp в Parser..."
python3 - << 'PYEOF'
# xlang-parser/src/parser.rs
with open('xlang-parser/src/parser.rs', 'r') as f:
    content = f.read()

# Добавляем поле is_lsp
content = content.replace(
    "    pub no_sec: bool,\n    pub null_sec: bool,",
    "    pub no_sec: bool,\n    pub null_sec: bool,\n    pub is_lsp: bool,"
)

# Обновляем new()
content = content.replace(
    "    pub fn new(input: &str, filename: &str, no_sec: bool, null_sec: bool) -> Self {",
    "    pub fn new(input: &str, filename: &str, no_sec: bool, null_sec: bool, is_lsp: bool) -> Self {"
)
content = content.replace(
    "Self { tokens: lexer.tokenize(), pos: 0, errors: Vec::new(), no_sec, null_sec, filename: filename.to_string() }",
    "Self { tokens: lexer.tokenize(), pos: 0, errors: Vec::new(), no_sec, null_sec, is_lsp, filename: filename.to_string() }"
)

# В блоке If/While отключаем dialoguer для LSP
content = content.replace(
    "                    if !self.no_sec && !self.null_sec {",
    "                    if !self.no_sec && !self.null_sec && !self.is_lsp {"
)

with open('xlang-parser/src/parser.rs', 'w') as f:
    f.write(content)

# xlang-compiler/src/main.rs
with open('xlang-compiler/src/main.rs', 'r') as f:
    comp = f.read()
comp = comp.replace(
    "Parser::new(&code, file_path.to_str().unwrap(), false, false)",
    "Parser::new(&code, file_path.to_str().unwrap(), false, false, false)"
)
with open('xlang-compiler/src/main.rs', 'w') as f:
    f.write(comp)

# xlang-lsp/src/main.rs
with open('xlang-lsp/src/main.rs', 'r') as f:
    lsp = f.read()
lsp = lsp.replace(
    "let mut parser = Parser::new(text, uri.as_str(), false, false);",
    "let mut parser = Parser::new(text, uri.as_str(), false, false, true);"
)
with open('xlang-lsp/src/main.rs', 'w') as f:
    f.write(lsp)
PYEOF

echo "==> 2. Пересборка LSP..."
cargo build --release -p xlang-parser
cargo build --release -p xlang-compiler
cargo build --release -p xlang-lsp
cp target/release/xlang-lsp ~/.local/bin/
cp target/release/xlang-compiler ~/.local/bin/xc

echo "==> 3. Обновление Neovim для отладки..."
cat > ~/.config/nvim/init.lua << 'EOF'
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.signcolumn = "yes"

vim.filetype.add({
  extension = { x = "xlang", xx = "xlang", xxx = "xlang", xh = "xlang" },
})

local function start_lsp()
    vim.lsp.start({
        name = 'xlang_lsp',
        cmd = { 'xlang-lsp' },
        root_dir = vim.fn.getcwd(),
        capabilities = vim.lsp.protocol.make_client_capabilities(),
    })
    print("LSP: xlang-lsp started!")
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'xlang',
    callback = start_lsp,
})

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('i', '<C-Space>', vim.lsp.buf.completion, opts)
  end,
})

vim.diagnostic.config({ virtual_text = true, signs = true, underline = true })
EOF

echo "========================================="
echo "🎉 LSP ИСПРАВЛЕН!"
echo "========================================="
echo "1. Открой Neovim: nvim /tmp/test_cli/main.x"
echo "2. Введи 'i' и напиши: if (x = 1) { }"
echo "3. Нажми Esc. Ошибка должна появиться СРАЗУ."
echo "4. Нажми :LspInfo (чтобы проверить, что xlang_lsp работает)."
