use std::env;
use std::io::{self, BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use libra_othello::{Board, Color, Coord, Move};

enum Player {
    Human,
    Engine(Engine),
}

struct Engine {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl Engine {
    fn start(command: &str) -> Result<Self, String> {
        let mut parts = command.split_whitespace();
        let program = parts
            .next()
            .ok_or_else(|| "engine command is empty".to_string())?;
        let args: Vec<_> = parts.collect();
        let mut child = Command::new(program)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|error| format!("failed to start engine '{command}': {error}"))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "failed to open engine stdin".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "failed to open engine stdout".to_string())?;
        Ok(Self {
            child,
            stdin,
            stdout: BufReader::new(stdout),
        })
    }

    fn request_move(&mut self, board: &Board, color: Color) -> Result<Move, String> {
        let request = format!(
            "position {} {}\n",
            color.name().to_ascii_lowercase(),
            board.to_wire()
        );
        self.stdin
            .write_all(request.as_bytes())
            .and_then(|_| self.stdin.flush())
            .map_err(|error| format!("failed to send position to engine: {error}"))?;

        let mut response = String::new();
        let bytes = self
            .stdout
            .read_line(&mut response)
            .map_err(|error| format!("failed to read engine response: {error}"))?;
        if bytes == 0 {
            return Err("engine exited without a response".to_string());
        }

        parse_engine_response(&response)
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = writeln!(self.stdin, "quit");
        let _ = self.child.wait();
    }
}

struct Config {
    black: PlayerKind,
    white: PlayerKind,
}

#[derive(Clone)]
enum PlayerKind {
    Human,
    Engine(String),
}

fn main() {
    if let Err(error) = run() {
        eprintln!("error: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let config = parse_args()?;
    let mut black = make_player(config.black)?;
    let mut white = make_player(config.white)?;
    let mut board = Board::new();
    let mut turn = Color::Black;
    let mut passes = 0;

    while !board.game_over() && passes < 2 {
        let legal_moves = board.legal_moves(turn);
        println!("{}", board.render(turn, &legal_moves));

        if legal_moves.is_empty() {
            println!("{} has no legal move and passes.", turn.name());
            passes += 1;
            turn = turn.opponent();
            continue;
        }

        let mv = match player_for(turn, &mut black, &mut white) {
            Player::Human => read_human_move(turn, &legal_moves)?,
            Player::Engine(engine) => {
                let mv = engine.request_move(&board, turn)?;
                println!("{} plays {}", turn.name(), mv.label());
                mv
            }
        };

        board.apply_move(turn, mv)?;
        passes = 0;
        turn = turn.opponent();
    }

    println!("{}", board.render(turn, &[]));
    print_result(&board);
    Ok(())
}

fn parse_args() -> Result<Config, String> {
    let mut black = PlayerKind::Human;
    let mut white = PlayerKind::Engine(default_engine_command()?);
    let mut args = env::args().skip(1);

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--black" => black = parse_player_arg(args.next(), "--black")?,
            "--white" => white = parse_player_arg(args.next(), "--white")?,
            "-h" | "--help" => {
                print_help();
                std::process::exit(0);
            }
            _ => return Err(format!("unknown argument: {arg}")),
        }
    }

    Ok(Config { black, white })
}

fn parse_player_arg(value: Option<String>, flag: &str) -> Result<PlayerKind, String> {
    let value = value.ok_or_else(|| format!("{flag} needs human or engine:<command>"))?;
    if value.eq_ignore_ascii_case("human") {
        Ok(PlayerKind::Human)
    } else if let Some(command) = value.strip_prefix("engine:") {
        Ok(PlayerKind::Engine(command.to_string()))
    } else {
        Err(format!("{flag} must be human or engine:<command>"))
    }
}

fn default_engine_command() -> Result<String, String> {
    let exe =
        env::current_exe().map_err(|error| format!("failed to locate current exe: {error}"))?;
    let mut path: PathBuf = exe;
    path.set_file_name(if cfg!(windows) {
        "othello-ai.exe"
    } else {
        "othello-ai"
    });
    if path.exists() {
        Ok(path.to_string_lossy().into_owned())
    } else {
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
        Ok(format!(
            "cargo run --quiet --manifest-path {} --bin othello-ai --",
            manifest.to_string_lossy()
        ))
    }
}

fn print_help() {
    println!(
        "Usage: othello-arena [--black human|engine:<command>] [--white human|engine:<command>]"
    );
    println!("Moves are entered as column+row, for example D3 or f5.");
    println!("Default: --black human --white engine:<sibling othello-ai binary>");
}

fn make_player(kind: PlayerKind) -> Result<Player, String> {
    match kind {
        PlayerKind::Human => Ok(Player::Human),
        PlayerKind::Engine(command) => Engine::start(&command).map(Player::Engine),
    }
}

fn player_for<'a>(turn: Color, black: &'a mut Player, white: &'a mut Player) -> &'a mut Player {
    match turn {
        Color::Black => black,
        Color::White => white,
    }
}

fn read_human_move(turn: Color, legal_moves: &[Coord]) -> Result<Move, String> {
    let legal_labels = legal_moves
        .iter()
        .map(|coord| coord.label())
        .collect::<Vec<_>>()
        .join(", ");
    loop {
        print!("{} move ({legal_labels}): ", turn.name());
        io::stdout()
            .flush()
            .map_err(|error| format!("failed to flush stdout: {error}"))?;

        let mut input = String::new();
        io::stdin()
            .read_line(&mut input)
            .map_err(|error| format!("failed to read move: {error}"))?;
        let mv = match Move::parse(&input) {
            Ok(mv) => mv,
            Err(error) => {
                println!("{error}");
                continue;
            }
        };
        match mv {
            Move::Place(coord) if legal_moves.contains(&coord) => return Ok(Move::Place(coord)),
            Move::Place(coord) => println!("{coord} is not legal here."),
            Move::Pass => println!("pass is only available when there are no legal moves."),
        }
    }
}

fn parse_engine_response(response: &str) -> Result<Move, String> {
    let mut parts = response.split_whitespace();
    let command = parts
        .next()
        .ok_or_else(|| "engine returned an empty response".to_string())?;
    if command.eq_ignore_ascii_case("error") {
        return Err(response.trim().to_string());
    }
    if !command.eq_ignore_ascii_case("move") {
        return Err(format!("engine response must start with move: {response}"));
    }
    let value = parts
        .next()
        .ok_or_else(|| "engine response is missing move value".to_string())?;
    if parts.next().is_some() {
        return Err(format!("engine response has too many fields: {response}"));
    }
    Move::parse(value).map_err(|error| error.to_string())
}

fn print_result(board: &Board) {
    let black = board.count(Color::Black);
    let white = board.count(Color::White);
    match black.cmp(&white) {
        std::cmp::Ordering::Greater => println!("Black wins {black}-{white}."),
        std::cmp::Ordering::Less => println!("White wins {white}-{black}."),
        std::cmp::Ordering::Equal => println!("Draw {black}-{white}."),
    }
}
