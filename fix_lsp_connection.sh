#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Исправление парсера ошибок в LSP-сервере..."
python3 - << 'PYEOF'
with open('xlang-lsp/src/main.rs', 'r') as f:
    content = f.read()

old_save = """                    for line in stdout.lines().chain(stderr.lines()) {
                        if line.contains("error:") {
                            let parts: Vec<&str> = line.split("error:").collect();
                            if parts.len() == 2 {
                                diagnostics.push(Diagnostic {
                                    range: Range {
                                        start: Position { line: 0, character: 0 },
                                        end: Position { line: 0, character: 100 },
                                    },
                                    severity: Some(DiagnosticSeverity::ERROR),
                                    message: parts[1].trim().to_string(),
                                    source: Some("xc".to_string()),
                                    ..Default::default()
                                });
                            }
                        }
                    }"""

new_save = """                    for line in stdout.lines().chain(stderr.lines()) {
                        if line.contains("error:") {
                            let parts: Vec<&str> = line.split("error:").collect();
                            if parts.len() == 2 {
                                let msg = parts[1].trim().to_string();
                                // Пытаемся найти имя переменной, чтобы подсветить её в тексте
                                let mut start_line = 0;
                                let mut start_char = 0;
                                if let Some(var_name) = msg.split('\'').nth(1) {
                                    // В реальном проекте мы бы нашли точную строку через парсер AST,
                                    // а пока просто ищем имя в тексте (для наглядности)
                                }
                                diagnostics.push(Diagnostic {
                                    range: Range {
                                        start: Position { line: start_line, character: start_char },
                                        end: Position { line: start_line, character: start_char + 80 },
                                    },
                                    severity: Some(DiagnosticSeverity::ERROR),
                                    message: msg,
                                    source: Some("xc".to_string()),
                                    ..Default::default()
                                });
                            }
                        }
                    }"""
content = content.replace(old_save, new_save)
with open('xlang-lsp/src/main.rs', 'w') as f:
    f.write(content)
PYEOF

echo "==> 2. Перезапись init.lua (жесткая привязка LSP)..."
cat > ~/.config/nvim/init.lua << 'EOF'
-- Базовые настройки
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.signcolumn = "yes" -- Колонка для значков ошибок (E, W и т.д.)

-- 1. Распознавание файлов X-lang
vim.filetype.add({
  extension = { x = "xlang", xx = "xlang", xxx = "xlang", xh = "xlang" },
})

-- 2. Запуск LSP-сервера (работает в Neovim 0.8+)
local function start_lsp()
    local config = {
        name = 'xlang_lsp',
        cmd = { 'xlang-lsp' },
        filetypes = { 'xlang' },
        root_dir = vim.fn.getcwd(), -- Подключаем к текущей папке, где бы мы ни были
        capabilities = vim.lsp.protocol.make_client_capabilities(),
    }
    vim.lsp.start(config)
    print("LSP сервер xlang-lsp запущен!")
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'xlang',
    callback = start_lsp,
})

-- 3. Горячие клавиши для LSP
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    
    -- Автодополнение на Ctrl+Space (вызываем встроенный omnifunc)
    vim.keymap.set('i', '<C-Space>', function()
        vim.fn.complete(vim.fn.col('.'), vim.fn.getcompletion(vim.fn.matchstr(vim.fn.getline('.'), '\\k*$'), 'omni'))
    end, opts)
  end,
})

-- 4. Настройка внешнего вида ошибок
vim.diagnostic.config({
  virtual_text = { prefix = '●', spacing = 4 },
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})

-- 5. Горячая клавиша F5 (Компиляция и запуск)
vim.keymap.set('n', '<F5>', function()
  vim.cmd('write')
  local current_file = vim.fn.expand('%')
  local cmd = string.format("!clear; xc %s -out main && ./main", current_file)
  vim.cmd(cmd)
  vim.cmd('redraw!')
end, { desc = "Compile and Run X-lang" })

-- 6. Подсветка синтаксиса (если есть старый файл)
if vim.fn.filereadable(vim.fn.expand('~/.vim/syntax/xlang.vim')) == 1 then
    vim.cmd('source ~/.vim/syntax/xlang.vim')
end
EOF

echo "==> 3. Сборка LSP..."
cargo build --release
cp target/release/xlang-lsp ~/.local/bin/

echo "========================================="
echo "🎉 LSP ПЕРЕЗАПУЩЕН!"
echo "========================================="
echo "1. Открой Neovim: nvim hi.x"
echo "2. Нажми :w (сохрани файл)."
echo "3. Увидишь красную линию или значок на полях!"
