use std::fmt;

pub const BOARD_SIZE: usize = 8;
pub const BOARD_CELLS: usize = BOARD_SIZE * BOARD_SIZE;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Color {
    Black,
    White,
}

impl Color {
    pub fn opponent(self) -> Self {
        match self {
            Self::Black => Self::White,
            Self::White => Self::Black,
        }
    }

    pub fn stone(self) -> char {
        match self {
            Self::Black => 'B',
            Self::White => 'W',
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Black => "Black",
            Self::White => "White",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "b" | "black" => Some(Self::Black),
            "w" | "white" => Some(Self::White),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Coord {
    pub row: usize,
    pub col: usize,
}

impl Coord {
    pub fn new(row: usize, col: usize) -> Option<Self> {
        if row < BOARD_SIZE && col < BOARD_SIZE {
            Some(Self { row, col })
        } else {
            None
        }
    }

    pub fn index(self) -> usize {
        self.row * BOARD_SIZE + self.col
    }

    pub fn label(self) -> String {
        let col = (b'A' + self.col as u8) as char;
        format!("{col}{}", self.row + 1)
    }
}

impl fmt::Display for Coord {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.label())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseMoveError(String);

impl fmt::Display for ParseMoveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for ParseMoveError {}

pub fn parse_coord(input: &str) -> Result<Coord, ParseMoveError> {
    let value = input.trim();
    if value.len() < 2 || value.len() > 3 {
        return Err(ParseMoveError("move must look like D3".to_string()));
    }

    let mut chars = value.chars();
    let first = chars.next().unwrap();
    let rest: String = chars.collect();
    let col_char = first.to_ascii_uppercase();
    if !('A'..='H').contains(&col_char) {
        return Err(ParseMoveError("column must be A-H".to_string()));
    }
    let row_number = rest
        .parse::<usize>()
        .map_err(|_| ParseMoveError("row must be 1-8".to_string()))?;
    if !(1..=BOARD_SIZE).contains(&row_number) {
        return Err(ParseMoveError("row must be 1-8".to_string()));
    }

    Ok(Coord {
        row: row_number - 1,
        col: col_char as usize - 'A' as usize,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Move {
    Place(Coord),
    Pass,
}

impl Move {
    pub fn parse(input: &str) -> Result<Self, ParseMoveError> {
        if input.trim().eq_ignore_ascii_case("pass") {
            Ok(Self::Pass)
        } else {
            parse_coord(input).map(Self::Place)
        }
    }

    pub fn label(&self) -> String {
        match self {
            Self::Place(coord) => coord.label(),
            Self::Pass => "pass".to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Board {
    cells: [Option<Color>; BOARD_CELLS],
}

impl Default for Board {
    fn default() -> Self {
        Self::new()
    }
}

impl Board {
    pub fn new() -> Self {
        let mut board = Self {
            cells: [None; BOARD_CELLS],
        };
        board.set(Coord { row: 3, col: 3 }, Some(Color::White));
        board.set(Coord { row: 3, col: 4 }, Some(Color::Black));
        board.set(Coord { row: 4, col: 3 }, Some(Color::Black));
        board.set(Coord { row: 4, col: 4 }, Some(Color::White));
        board
    }

    pub fn from_wire(value: &str) -> Result<Self, String> {
        let text = value.trim();
        if text.chars().count() != BOARD_CELLS {
            return Err(format!("board must contain {BOARD_CELLS} cells"));
        }

        let mut board = Self {
            cells: [None; BOARD_CELLS],
        };
        for (i, ch) in text.chars().enumerate() {
            board.cells[i] = match ch {
                'B' | 'b' => Some(Color::Black),
                'W' | 'w' => Some(Color::White),
                '.' | '-' | '_' => None,
                _ => return Err(format!("invalid board cell '{ch}'")),
            };
        }
        Ok(board)
    }

    pub fn to_wire(&self) -> String {
        self.cells
            .iter()
            .map(|cell| cell.map(Color::stone).unwrap_or('.'))
            .collect()
    }

    pub fn get(&self, coord: Coord) -> Option<Color> {
        self.cells[coord.index()]
    }

    pub fn set(&mut self, coord: Coord, color: Option<Color>) {
        self.cells[coord.index()] = color;
    }

    pub fn count(&self, color: Color) -> usize {
        self.cells
            .iter()
            .filter(|&&cell| cell == Some(color))
            .count()
    }

    pub fn is_full(&self) -> bool {
        self.cells.iter().all(Option::is_some)
    }

    pub fn legal_moves(&self, color: Color) -> Vec<Coord> {
        let mut moves = Vec::new();
        for row in 0..BOARD_SIZE {
            for col in 0..BOARD_SIZE {
                let coord = Coord { row, col };
                if self.get(coord).is_none() && !self.flips_for(coord, color).is_empty() {
                    moves.push(coord);
                }
            }
        }
        moves
    }

    pub fn has_legal_move(&self, color: Color) -> bool {
        for row in 0..BOARD_SIZE {
            for col in 0..BOARD_SIZE {
                let coord = Coord { row, col };
                if self.get(coord).is_none() && !self.flips_for(coord, color).is_empty() {
                    return true;
                }
            }
        }
        false
    }

    pub fn apply_move(&mut self, color: Color, mv: Move) -> Result<(), String> {
        match mv {
            Move::Pass => {
                if self.has_legal_move(color) {
                    Err("pass is only legal when there are no legal moves".to_string())
                } else {
                    Ok(())
                }
            }
            Move::Place(coord) => {
                if self.get(coord).is_some() {
                    return Err(format!("{coord} is already occupied"));
                }
                let flips = self.flips_for(coord, color);
                if flips.is_empty() {
                    return Err(format!("{coord} is not a legal move"));
                }
                self.set(coord, Some(color));
                for flip in flips {
                    self.set(flip, Some(color));
                }
                Ok(())
            }
        }
    }

    pub fn game_over(&self) -> bool {
        self.is_full() || (!self.has_legal_move(Color::Black) && !self.has_legal_move(Color::White))
    }

    pub fn render(&self, turn: Color, highlights: &[Coord]) -> String {
        let mut out = String::new();
        out.push_str("    A B C D E F G H\n");
        out.push_str("  +-----------------+\n");
        for row in 0..BOARD_SIZE {
            out.push_str(&format!("{} |", row + 1));
            for col in 0..BOARD_SIZE {
                let coord = Coord { row, col };
                let ch = match self.get(coord) {
                    Some(color) => color.stone(),
                    None if highlights.contains(&coord) => '*',
                    None => '.',
                };
                out.push(' ');
                out.push(ch);
            }
            out.push_str(&format!(" | {}\n", row + 1));
        }
        out.push_str("  +-----------------+\n");
        out.push_str("    A B C D E F G H\n");
        out.push_str(&format!(
            "Turn: {}   Black: {}   White: {}\n",
            turn.name(),
            self.count(Color::Black),
            self.count(Color::White)
        ));
        out
    }

    fn flips_for(&self, coord: Coord, color: Color) -> Vec<Coord> {
        const DIRECTIONS: [(isize, isize); 8] = [
            (-1, -1),
            (-1, 0),
            (-1, 1),
            (0, -1),
            (0, 1),
            (1, -1),
            (1, 0),
            (1, 1),
        ];

        let mut flips = Vec::new();
        for (dr, dc) in DIRECTIONS {
            let mut line = Vec::new();
            let mut row = coord.row as isize + dr;
            let mut col = coord.col as isize + dc;
            while (0..BOARD_SIZE as isize).contains(&row) && (0..BOARD_SIZE as isize).contains(&col)
            {
                let current = Coord {
                    row: row as usize,
                    col: col as usize,
                };
                match self.get(current) {
                    Some(stone) if stone == color.opponent() => line.push(current),
                    Some(stone) if stone == color => {
                        if !line.is_empty() {
                            flips.extend(line);
                        }
                        break;
                    }
                    _ => break,
                }
                row += dr;
                col += dc;
            }
        }
        flips
    }
}

pub fn choose_ai_move(board: &Board, color: Color) -> Move {
    let legal_moves = board.legal_moves(color);
    let Some(best) = legal_moves
        .into_iter()
        .max_by_key(|&coord| score_move(board, color, coord))
    else {
        return Move::Pass;
    };
    Move::Place(best)
}

fn score_move(board: &Board, color: Color, coord: Coord) -> i32 {
    let positional = POSITION_WEIGHTS[coord.index()];
    let mut next = board.clone();
    let _ = next.apply_move(color, Move::Place(coord));
    let gain = next.count(color) as i32 - board.count(color) as i32;
    let opponent_mobility = next.legal_moves(color.opponent()).len() as i32;
    positional + gain * 8 - opponent_mobility * 3
}

const POSITION_WEIGHTS: [i32; BOARD_CELLS] = [
    120, -30, 20, 5, 5, 20, -30, 120, -30, -60, -5, -5, -5, -5, -60, -30, 20, -5, 15, 3, 3, 15, -5,
    20, 5, -5, 3, 3, 3, 3, -5, 5, 5, -5, 3, 3, 3, 3, -5, 5, 20, -5, 15, 3, 3, 15, -5, 20, -30, -60,
    -5, -5, -5, -5, -60, -30, 120, -30, 20, 5, 5, 20, -30, 120,
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_human_coordinates() {
        assert_eq!(parse_coord("D3").unwrap(), Coord { row: 2, col: 3 });
        assert_eq!(parse_coord("h8").unwrap(), Coord { row: 7, col: 7 });
        assert!(parse_coord("I1").is_err());
        assert!(parse_coord("A9").is_err());
    }

    #[test]
    fn initial_board_has_four_black_moves() {
        let board = Board::new();
        let labels: Vec<_> = board
            .legal_moves(Color::Black)
            .into_iter()
            .map(|coord| coord.label())
            .collect();
        assert_eq!(labels, ["D3", "C4", "F5", "E6"]);
    }

    #[test]
    fn applying_move_flips_stones() {
        let mut board = Board::new();
        board
            .apply_move(Color::Black, Move::Place(parse_coord("D3").unwrap()))
            .unwrap();
        assert_eq!(board.get(parse_coord("D3").unwrap()), Some(Color::Black));
        assert_eq!(board.get(parse_coord("D4").unwrap()), Some(Color::Black));
        assert_eq!(board.count(Color::Black), 4);
        assert_eq!(board.count(Color::White), 1);
    }

    #[test]
    fn wire_round_trip_keeps_board() {
        let board = Board::new();
        assert_eq!(Board::from_wire(&board.to_wire()).unwrap(), board);
    }
}
