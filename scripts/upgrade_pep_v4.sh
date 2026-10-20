#!/bin/bash
set -e
cd ~/FOS

echo "==> 1. Обновление тем (добавляем TrueColor RGB для Glass Effect)..."
# Создаем тему glass-effect (использует RGB цвета)
cat > ~/.config/pep/themes/glass-effect.theme << 'EOF'
bg=RGB(20,20,30)
fg=RGB(220,220,220)
keyword=RGB(100,200,255)
string=RGB(150,255,150)
comment=RGB(120,120,140)
status_bg=RGB(40,40,60)
status_fg=RGB(200,200,255)
linenum=RGB(100,100,120)
EOF

# Создаем темную тему в стиле Kate (Breeze Dark)
cat > ~/.config/pep/themes/kate-dark.theme << 'EOF'
bg=RGB(35,38,41)
fg=RGB(239,240,241)
keyword=RGB(61,174,233)
string=RGB(166,226,46)
comment=RGB(128,128,128)
status_bg=RGB(49,54,59)
status_fg=RGB(239,240,241)
linenum=RGB(112,120,128)
EOF

cp ~/.config/pep/themes/glass-effect.theme ~/.config/pep/current.theme

echo "==> 2. Перезапись PEP v0.4 (Kate-like UI, Sidebar, TrueColor, Ctrl+S)..."
cat > pep/src/main.rs << 'EOF'
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
    style::{Color, Print, ResetColor, SetForegroundColor, SetBackgroundColor},
    cursor::MoveTo,
};
use std::{fs, io, process::{Command, Stdio}, io::{BufRead, BufReader, Write}, path::Path, env};
use xlang_lexer::{Lexer, Token};

struct Theme {
    bg: Color, fg: Color, keyword: Color, string: Color,
    comment: Color, status_bg: Color, status_fg: Color, linenum: Color,
}

impl Theme {
    fn load() -> Self {
        let mut theme = Theme {
            bg: Color::Rgb { r: 20, g: 20, b: 30 }, fg: Color::Rgb { r: 220, g: 220, b: 220 }, 
            keyword: Color::Rgb { r: 100, g: 200, b: 255 }, string: Color::Rgb { r: 150, g: 255, b: 150 },
            comment: Color::Rgb { r: 120, g: 120, b: 140 }, status_bg: Color::Rgb { r: 40, g: 40, b: 60 },
            status_fg: Color::Rgb { r: 200, g: 200, b: 255 }, linenum: Color::Rgb { r: 100, g: 100, b: 120 },
        };
        let path = format!("{}/.config/pep/current.theme", env::var("HOME").unwrap_or_default());
        if let Ok(content) = fs::read_to_string(path) {
            for line in content.lines() {
                let parts: Vec<&str> = line.split('=').collect();
                if parts.len() == 2 {
                    let color = parse_color(parts[1]);
                    match parts[0] {
                        "bg" => theme.bg = color, "fg" => theme.fg = color,
                        "keyword" => theme.keyword = color, "string" => theme.string = color,
                        "comment" => theme.comment = color, "status_bg" => theme.status_bg = color,
                        "status_fg" => theme.status_fg = color, "linenum" => theme.linenum = color,
                        _ => {}
                    }
                }
            }
        }
        theme
    }
}

fn parse_color(s: &str) -> Color {
    if s.starts_with("RGB(") && s.ends_with(")") {
        let nums: Vec<u8> = s[4..s.len()-1].split(',').filter_map(|n| n.trim().parse().ok()).collect();
        if nums.len() == 3 { return Color::Rgb { r: nums[0], g: nums[1], b: nums[2] }; }
    }
    match s {
        "Black" => Color::Black, "DarkGrey" => Color::DarkGrey, "Red" => Color::Red, "DarkRed" => Color::DarkRed,
        "Green" => Color::Green, "DarkGreen" => Color::DarkGreen, "Yellow" => Color::Yellow, "DarkYellow" => Color::DarkYellow,
        "Blue" => Color::Blue, "DarkBlue" => Color::DarkBlue, "Magenta" => Color::Magenta, "DarkMagenta" => Color::DarkMagenta,
        "Cyan" => Color::Cyan, "DarkCyan" => Color::DarkCyan, "White" => Color::White, "Grey" => Color::Grey,
        _ => Color::Reset,
    }
}

struct App {
    lines: Vec<String>,
    cursor_x: usize,
    cursor_y: usize,
    scroll_y: usize,
    filename: String,
    status_msg: String,
    insert_mode: bool,
    theme: Theme,
    sidebar_files: Vec<String>,
    sidebar_selected: usize,
    focus_sidebar: bool,
}

impl App {
    fn new(filename: &str) -> Self {
        let content = fs::read_to_string(filename).unwrap_or_default();
        let lines: Vec<String> = if content.is_empty() { vec![String::new()] } else { content.lines().map(|s| s.to_string()).collect() };
        
        let mut sidebar_files = Vec::new();
        if let Some(parent) = Path::new(filename).parent() {
            if let Ok(entries) = fs::read_dir(parent) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_file() {
                        if let Some(ext) = p.extension().and_then(|s| s.to_str()) {
                            if matches!(ext, "x" | "xx" | "xxx" | "xh") {
                                sidebar_files.push(entry.file_name().to_string_lossy().to_string());
                            }
                        }
                    }
                }
            }
        }
        sidebar_files.sort();

        Self {
            lines, cursor_x: 0, cursor_y: 0, scroll_y: 0,
            filename: filename.to_string(),
            status_msg: "Kate Edition | Ctrl+S: Save | F5: Compile | Ctrl+B: Sidebar".to_string(),
            insert_mode: false,
            theme: Theme::load(),
            sidebar_files,
            sidebar_selected: 0,
            focus_sidebar: false,
        }
    }

    fn save(&mut self) -> io::Result<()> {
        fs::write(&self.filename, self.lines.join("\n"))?;
        self.status_msg = "Saved!".to_string();
        Ok(())
    }

    fn compile(&mut self) {
        let _ = self.save();
        self.status_msg = "Compiling...".to_string();
        
        let mut child = Command::new("xc")
            .arg(&self.filename)
            .stdout(Stdio::piped())
            .stdin(Stdio::piped())
            .spawn()
            .expect("Failed to start xc");

        let stdout = child.stdout.take().unwrap();
        let reader = BufReader::new(stdout);
        let mut stdin = child.stdin.take().unwrap();

        for line in reader.lines() {
            if let Ok(l) = line {
                if l.starts_with("XQLANG_QUERY:") {
                    self.status_msg = l.replace("XQLANG_QUERY:", "").trim().to_string();
                    let _ = stdin.write_all(b"y\n");
                } else if l.contains("Compiled successfully") {
                    self.status_msg = l;
                }
            }
        }
        let _ = child.wait();
    }

    fn draw(&self, term_width: u16, term_height: u16) -> io::Result<()> {
        let mut stdout = io::stdout();
        execute!(stdout, crossterm::terminal::Clear(crossterm::terminal::ClearType::All))?;
        execute!(stdout, SetBackgroundColor(self.theme.bg), SetForegroundColor(self.theme.fg))?;

        let menu_str = " File   Edit   View   Run   Help ";
        execute!(stdout, MoveTo(0, 0), SetBackgroundColor(self.theme.status_bg), SetForegroundColor(self.theme.status_fg), Print(format!("{:<1$}", menu_str, term_width as usize)))?;

        let sidebar_width = 20;
        let editor_x = sidebar_width + 1;
        let visible_lines = term_height.saturating_sub(3) as usize;

        // Отрисовка Sidebar
        execute!(stdout, SetBackgroundColor(self.theme.bg), SetForegroundColor(self.theme.linenum))?;
        for y in 1..term_height-2 {
            execute!(stdout, MoveTo(sidebar_width as u16, y), Print("░"))?;
        }
        execute!(stdout, MoveTo(0, 1), SetForegroundColor(self.theme.keyword), Print(" Project Files:"))?;
        
        for (i, file) in self.sidebar_files.iter().enumerate() {
            if i + 2 >= term_height as usize - 1 { break; }
            execute!(stdout, MoveTo(0, (i + 2) as u16))?;
            if i == self.sidebar_selected && self.focus_sidebar {
                execute!(stdout, SetBackgroundColor(self.theme.status_bg), SetForegroundColor(self.theme.status_fg))?;
                execute!(stdout, Print(format!("> {:<17}", file)))?;
            } else {
                execute!(stdout, SetBackgroundColor(self.theme.bg), SetForegroundColor(self.theme.fg))?;
                execute!(stdout, Print(format!("  {:<17}", file)))?;
            }
        }

        // Отрисовка редактора
        for (screen_y, line_idx) in (self.scroll_y..self.lines.len()).enumerate() {
            if screen_y >= visible_lines { break; }
            let line = &self.lines[line_idx];
            execute!(stdout, MoveTo(editor_x as u16, (screen_y + 1) as u16))?;
            
            execute!(stdout, SetForegroundColor(self.theme.linenum), Print(format!("{:4} │ ", line_idx + 1)))?;
            execute!(stdout, SetForegroundColor(self.theme.fg))?;

            let mut lexer = Lexer::new(line);
            let tokens = lexer.tokenize();
            let mut last_col = 0;

            for (tok, _, t_col) in tokens.iter() {
                if *t_col > last_col + 1 { execute!(stdout, Print(" ".repeat(*t_col - last_col - 1)))?; }
                match tok {
                    Token::Comment(c) => { execute!(stdout, SetForegroundColor(self.theme.comment), Print(format!("!{}!", c)))?; last_col = *t_col + c.len() + 2; }
                    Token::StringLiteral(s) => { execute!(stdout, SetForegroundColor(self.theme.string), Print(format!("\"{}\"", s)))?; last_col = *t_col + s.len() + 2; }
                    Token::Identifier(i) => { execute!(stdout, SetForegroundColor(self.theme.fg), Print(i))?; last_col = *t_col + i.len(); }
                    Token::Dollar => { execute!(stdout, SetForegroundColor(self.theme.keyword), Print("$"))?; last_col = *t_col + 1; }
                    Token::Alias | Token::Func | Token::Con | Token::If | Token::Else | Token::While | Token::For | Token::Return => { 
                        execute!(stdout, SetForegroundColor(self.theme.keyword), Print(format!("{:?}", tok).to_lowercase()))?; 
                        last_col = *t_col + format!("{:?}", tok).len(); 
                    }
                    _ => { execute!(stdout, SetForegroundColor(self.theme.fg), Print(format!("{:?}", tok)))?; last_col = *t_col + format!("{:?}", tok).len(); }
                }
            }
        }

        // Статус-бар
        let status_y = term_height.saturating_sub(2);
        execute!(stdout, MoveTo(0, status_y), SetBackgroundColor(self.theme.status_bg), SetForegroundColor(self.theme.status_fg))?;
        let mode = if self.insert_mode { "INSERT" } else { "NORMAL" };
        let pos_str = format!(" Ln {}, Col {} ", self.cursor_y + 1, self.cursor_x + 1);
        let status_text = format!(" {} | {} | {} |{}", mode, self.filename, self.status_msg, pos_str);
        execute!(stdout, Print(format!("{:<1$}", status_text, term_width as usize)))?;
        
        // Нижняя строка
        execute!(stdout, MoveTo(0, term_height.saturating_sub(1)), SetBackgroundColor(self.theme.bg), SetForegroundColor(self.theme.linenum))?;
        execute!(stdout, Print(format!("{:<1$}", " UTF-8 | X-lang | Spaces: 4", term_width as usize)))?;

        // Курсор
        let cursor_screen_y = (self.cursor_y - self.scroll_y) as u16 + 1;
        execute!(stdout, MoveTo((self.cursor_x + editor_x + 7) as u16, cursor_screen_y))?;
        Ok(())
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let filename = if args.len() > 1 { &args[1] } else { "test.x" };
    
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    
    let mut app = App::new(filename);
    let (term_width, term_height) = crossterm::terminal::size()?;

    loop {
        app.draw(term_width, term_height)?;
        
        if let Event::Key(key) = event::read()? {
            if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('q') { break; }
            if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('s') { let _ = app.save(); continue; }
            if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('b') { app.focus_sidebar = !app.focus_sidebar; continue; }
            if key.code == KeyCode::F(5) { app.compile(); continue; }

            if app.focus_sidebar {
                match key.code {
                    KeyCode::Up => { if app.sidebar_selected > 0 { app.sidebar_selected -= 1; } },
                    KeyCode::Down => { if app.sidebar_selected < app.sidebar_files.len().saturating_sub(1) { app.sidebar_selected += 1; } },
                    KeyCode::Enter => {
                        let new_file = app.sidebar_files[app.sidebar_selected].clone();
                        app.filename = new_file.clone();
                        app.lines = fs::read_to_string(&new_file).unwrap_or_default().lines().map(|s| s.to_string()).collect();
                        if app.lines.is_empty() { app.lines.push(String::new()); }
                        app.cursor_x = 0; app.cursor_y = 0; app.scroll_y = 0;
                        app.focus_sidebar = false;
                    },
                    _ => {}
                }
                continue;
            }

            if app.insert_mode {
                match key.code {
                    KeyCode::Esc => { app.insert_mode = false; app.status_msg = "NORMAL".to_string(); },
                    KeyCode::Char(c) => { app.lines[app.cursor_y].insert(app.cursor_x, c); app.cursor_x += 1; },
                    KeyCode::Enter => {
                        let rest = app.lines[app.cursor_y].split_off(app.cursor_x);
                        app.lines.insert(app.cursor_y + 1, rest);
                        app.cursor_y += 1; app.cursor_x = 0;
                    },
                    KeyCode::Backspace => {
                        if app.cursor_x > 0 { app.cursor_x -= 1; app.lines[app.cursor_y].remove(app.cursor_x); }
                        else if app.cursor_y > 0 {
                            let prev_line = app.lines.remove(app.cursor_y);
                            app.cursor_y -= 1; app.cursor_x = app.lines[app.cursor_y].len();
                            app.lines[app.cursor_y].push_str(&prev_line);
                        }
                    },
                    KeyCode::Left => { if app.cursor_x > 0 { app.cursor_x -= 1; } },
                    KeyCode::Right => { if app.cursor_x < app.lines[app.cursor_y].len() { app.cursor_x += 1; } },
                    KeyCode::Up => { if app.cursor_y > 0 { app.cursor_y -= 1; app.cursor_x = app.cursor_x.min(app.lines[app.cursor_y].len()); } },
                    KeyCode::Down => { if app.cursor_y < app.lines.len() - 1 { app.cursor_y += 1; app.cursor_x = app.cursor_x.min(app.lines[app.cursor_y].len()); } },
                    _ => {}
                }
            } else {
                match key.code {
                    KeyCode::Char('i') => { app.insert_mode = true; app.status_msg = "INSERT".to_string(); },
                    KeyCode::Char('h') => { if app.cursor_x > 0 { app.cursor_x -= 1; } },
                    KeyCode::Char('l') => { if app.cursor_x < app.lines[app.cursor_y].len() { app.cursor_x += 1; } },
                    KeyCode::Char('j') => { if app.cursor_y < app.lines.len() - 1 { app.cursor_y += 1; app.cursor_x = app.cursor_x.min(app.lines[app.cursor_y].len()); } },
                    KeyCode::Char('k') => { if app.cursor_y > 0 { app.cursor_y -= 1; app.cursor_x = app.cursor_x.min(app.lines[app.cursor_y].len()); } },
                    _ => {}
                }
            }

            // Скролл
            if app.cursor_y >= app.scroll_y + term_height.saturating_sub(3) as usize {
                app.scroll_y = app.cursor_y.saturating_sub(term_height.saturating_sub(4) as usize);
            } else if app.cursor_y < app.scroll_y {
                app.scroll_y = app.cursor_y;
            }
        }
    }

    disable_raw_mode()?;
    execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture)?;
    Ok(())
}
EOF

echo "==> 3. Сборка PEP v0.4..."
cargo build --release

echo "==> 4. Обновление бинарников..."
cp target/release/xlang-compiler ~/.local/bin/xc
cp target/release/pep ~/.local/bin/pep
cp target/release/pep-installer ~/.local/bin/pep-installer

echo "========================================="
echo "🎉 PEP v0.4 (KATE EDITION + GLASS) ГОТОВ!"
echo "========================================="
echo "1. Установи тему:"
echo "   pep-installer   (выбери glass-effect или kate-dark)"
echo ""
echo "2. Открой проект:"
echo "   pep ~/test_ipc.x"
echo ""
echo "Управление: Ctrl+S (сохранить), Ctrl+B (боковая панель), F5 (сборка), i (ввод)."
