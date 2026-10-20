use crossterm::{
    event::{self, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
    style::{Print, SetForegroundColor, Color},
    cursor::MoveTo,
};
use std::{fs, io};

fn main() -> io::Result<()> {
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen)?;

    let themes = vec!["classic", "classic-glass", "rainbow", "rainbow-glass", "aero", "aero-glossy"];
    let mut selected = 0;

    loop {
        execute!(io::stdout(), crossterm::terminal::Clear(crossterm::terminal::ClearType::All))?;
        execute!(io::stdout(), MoveTo(2, 1), SetForegroundColor(Color::Cyan), Print("=== PEP Theme Installer ==="))?;
        
        for (i, theme) in themes.iter().enumerate() {
            execute!(io::stdout(), MoveTo(2, 3 + i as u16))?;
            if i == selected {
                execute!(io::stdout(), SetForegroundColor(Color::Green), Print(format!("> {}", theme)))?;
            } else {
                execute!(io::stdout(), SetForegroundColor(Color::White), Print(format!("  {}", theme)))?;
            }
        }
        
        execute!(io::stdout(), MoveTo(2, 10), SetForegroundColor(Color::DarkGrey), Print("Up/Down to select, Enter to install, Q to quit"))?;

        if let Event::Key(key) = event::read()? {
            match key.code {
                KeyCode::Up => { if selected > 0 { selected -= 1; } },
                KeyCode::Down => { if selected < themes.len() - 1 { selected += 1; } },
                KeyCode::Enter => {
                    let theme_name = themes[selected];
                    let src = format!("{}/.config/pep/themes/{}.theme", std::env::var("HOME").unwrap(), theme_name);
                    let dst = format!("{}/.config/pep/current.theme", std::env::var("HOME").unwrap());
                    fs::copy(src, dst).unwrap();
                    
                    execute!(io::stdout(), MoveTo(2, 12), SetForegroundColor(Color::Green), Print(format!("Installed theme: {}!", theme_name)))?;
                    std::thread::sleep(std::time::Duration::from_millis(1000));
                },
                KeyCode::Char('q') | KeyCode::Char('Q') => break,
                _ => {}
            }
        }
    }

    disable_raw_mode()?;
    execute!(io::stdout(), LeaveAlternateScreen)?;
    Ok(())
}
