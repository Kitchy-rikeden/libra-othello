# libra-othello
Libra the Processor のオセロプログラム

## Rust tools

まずは人間と対戦できるCLIを用意しています。

```sh
cargo run --manifest-path othello-tools/Cargo.toml --bin othello-arena
```

手は `D3` や `f5` のように、列をアルファベット `A-H`、行を数字 `1-8` で入力します。

- `othello-ai`: 標準入出力で動く対戦相手プロセス
- `othello-arena`: 2つのプレイヤープロセスをつなぎ、盤面を表示しながら対局するCLI

`othello-ai` のプロトコルは1行テキストです。

```text
position <black|white> <64-cell-board>
```

盤面は左上 `A1` から右下 `H8` までの64文字で、黒は `B`、白は `W`、空きは `.` です。応答は `move D3` または `move pass` です。

別プロセスを相手にする場合は次のように指定できます。

```sh
cargo run --manifest-path othello-tools/Cargo.toml --bin othello-arena -- --black human --white 'engine:othello-tools/target/debug/othello-ai'
```
