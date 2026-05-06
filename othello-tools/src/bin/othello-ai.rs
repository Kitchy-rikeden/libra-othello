use std::io::{self, BufRead, Write};

use libra_othello::{choose_ai_move, Board, Color};

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(line) => line,
            Err(error) => {
                eprintln!("failed to read stdin: {error}");
                break;
            }
        };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line.eq_ignore_ascii_case("quit") {
            break;
        }

        let response = match handle_position(line) {
            Ok(response) => response,
            Err(error) => format!("error {error}"),
        };
        if writeln!(stdout, "{response}")
            .and_then(|_| stdout.flush())
            .is_err()
        {
            break;
        }
    }
}

fn handle_position(line: &str) -> Result<String, String> {
    let mut parts = line.split_whitespace();
    let command = parts.next().ok_or_else(|| "missing command".to_string())?;
    if !command.eq_ignore_ascii_case("position") {
        return Err("expected: position <black|white> <64-cell-board>".to_string());
    }
    let color = parts
        .next()
        .and_then(Color::parse)
        .ok_or_else(|| "missing or invalid color".to_string())?;
    let board = Board::from_wire(
        parts
            .next()
            .ok_or_else(|| "missing board string".to_string())?,
    )?;
    if parts.next().is_some() {
        return Err("too many fields".to_string());
    }

    Ok(format!("move {}", choose_ai_move(&board, color).label()))
}
