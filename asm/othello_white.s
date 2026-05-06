// Libra オセロプレイヤー
//
// プロトコル:
// - このプログラムは白 (1) として打つ. 相手は黒 (-1).
// - 入力は相手の手を1行ずつ受け取る: D3 または P
// - 出力は自分の手を1行ずつ返す: D3 または P
//
// 盤面:
// - データメモリ 0..99 を, 外周に空白マスを持つ 10x10 盤面として使う.
// - 実際に打てるマスは 行 1..8, 列 1..8.
// - マスのアドレス = 行 * 10 + 列.
// - 0 = 空き, 1 = 白, -1 = 黒.
//
// 変数:
// 100 POS, 101 COLOR, 102 NEG, 104 SCAN
// 105 ROW, 106 COL, 109 FLIPPED, 110 OPPPASS

// 盤面を初期化する.
//
// オセロ自体は 8x8 だが, ここでは 10x10 配列として持つ.
// 実際の 8x8 盤面の外側に 0 の外周を1マス分置くことで,
// 方向スキャンが盤外へ出たときに自然に停止できる.
//
// 初期配置:
// - 白 = 1: D4, E5
// - 黒 = -1: E4, D5
START:      MOVI    A, 1
            STI     44          // D4 白
            STI     55          // E5 白
            MOVI    A, -1
            STI     45          // E4 黒
            STI     54          // D5 黒

// メインループ: 相手の手を読む.
//
// 入力は MMIO アドレス 121 から ASCII として読む.
// シミュレータの ascii 形式では, 各文字は「ASCIIコード - 121」として扱われる.
//
// 重要な文字値:
// - 'A' = -56 なので, 列番号 = 入力 + 57
// - '1' = -72 なので, 行番号 = 入力 + 73
// - 'P' = -41
//
// "D3\n" または "P\n" を読んでいる間, B には MMIO アドレスを保持する.
TURN:       MOVI    B, 121
            LD      A, B        // 列文字または 'P'
            CMPI    -41         // 'P'
            JZ      OPP_PASS

            // 相手の手の文字列を数値の COL/ROW に変換し,
            // 最後の改行を読み捨てる. 相手の手は合法であると信用する.
            ADDI    A, 57       // A=col 1..8
            STI     106         // COL
            LD      A, B        // 行文字
            ADDI    A, 73       // A=行 1..8
            STI     105         // ROW
            LD      A, B        // 改行を読み捨て

            // 相手の手を黒として盤面に反映する.
            // APPLY は石が反転したかどうかを返すが,
            // 相手入力は合法と仮定するので戻り値は無視する.
            CALL    MAKE_POS
            MOVI    A, -1
            STI     101         // COLOR
            CALL    APPLY
            SUB     A, A        // A = 0
            STI     110         // OPPPASS
            J       MY_TURN

// 相手がパスした.
//
// 'P' の後ろの改行を読み捨て, 直前の手がパスだったことを記録する.
// 次に自分もパスするならゲーム終了.
OPP_PASS:   LD      A, B        // 改行を読み捨て
            MOVI    A, 1
            STI     110

// 自分の手を選ぶ.
//
// このプログラムは常に白として打つので COLOR に 1 を入れる.
// FIND は最初に見つけた合法手を探し, 見つけたらその場で盤面に反映する.
// FIND が 0 を返した場合は合法手なしなのでパスする.
MY_TURN:    MOVI    A, 1
            STI     101         // COLOR
            CALL    FIND
            JZ      MY_PASS

            // 選んだ手を "D3\n" の形で出力する.
            // ROW/COL は FIND が保持したままなので, ASCII オフセット値に戻す.
            MOVI    B, 121
            LDI     A, 106      // COL
            ADDI    A, -57      // 列を ASCII オフセットへ
            ST      B
            LDI     A, 105      // ROW
            ADDI    A, -73      // 行を ASCII オフセットへ
            ST      B
            MOVI    A, -111     // 改行
            ST      B
            J       TURN

// 白の合法手が見つからなかった.
//
// 相手も直前にパスしていた場合, 両者連続パスなのでゲーム終了.
// そうでなければ "P\n" を出力して続行する.
MY_PASS:    LDI     A, 110      // OPPPASS
            CMPI    1
            JZ      END
            MOVI    A, -41      // 'P'
            STI     121
            MOVI    A, -111     // 改行
            STI     121
            J       TURN

// 両者連続パスで停止する.
END:        HALT

// ROW/COL を盤面アドレスに変換する.
//
// 入力:
// - MEM[105] ROW: 1..8
// - MEM[106] COL: 1..8
//
// 出力:
// - A = ROW * 10 + COL
// - MEM[100] POS = ROW * 10 + COL
//
// 乗算命令がないので, ROW * 10 は次のように作る:
// 2r, 4r, 8r, 9r, 10r.
MAKE_POS:   LDI     A, 105
            ADD     A, A        // 2r
            MOV     B, A
            ADD     A, A        // 4r
            ADD     A, A        // 8r
            ADD     A, B        // 10r
            LDI     B, 106
            ADD     A, B
            STI     100
            RET

// COLOR の最初の合法手を探し, その手を盤面に反映する.
//
// 探索順は行優先: A1, B1, ..., H1, A2, ...
//
// 入力:
// - MEM[101] COLOR
//
// 手が見つかった場合の出力:
// - その手はすでに盤面に反映済み.
// - MEM[105] ROW と MEM[106] COL に選んだ手が残る.
// - A は非ゼロ, 符号レジスタは正.
//
// 手が見つからなかった場合の出力:
// - A は 0, 符号レジスタは 0.
//
// ここでは合法手判定専用のサブルーチンを呼ばず,
// 候補マスに COLOR を仮置きして APPLY を実行する.
// APPLY が1つ以上の石を反転したなら合法手なので, そのまま盤面に残す.
// 何も反転しなかった場合は不合法なので, FIND_UNDO で仮置きだけ消して探索を続ける.
FIND:       MOVI    A, 1
            STI     105         // ROW

// 行の開始または継続. ROW > 8 なら盤面全体を調べ終わった.
FIND_ROW:   LDI     A, 105
            CMPI    8
            JP      FIND_NONE
            MOVI    A, 1
            STI     106         // COL

// 現在の行で列を1つ調べる.
//
// 空きでないマスはスキップする.
// 空きマスだけ候補手として試す.
FIND_COL:   LDI     A, 106
            CMPI    8
            JP      FIND_NEXT_ROW
            CALL    MAKE_POS
            MOV     B, A
            LD      A, B
            CMPI    0
            JZ      FIND_EMPTY

// 次の列へ進む.
FIND_ADV:   LDI     A, 106
            ADDI    A, 1
            STI     106
            J       FIND_COL

// 候補マスが空きだったので, ここに COLOR を置いてみる.
//
// APPLY が 0 を返すならどの方向も反転せず, その手は不合法.
// 0 でなければ合法手はすでに反映済みなので, FIND はそのまま戻る.
FIND_EMPTY: CALL    APPLY
            JZ      FIND_UNDO
            RET

// 不合法だった候補手を取り消す.
//
// APPLY が 0 を返したとき, 相手の石は1つも変化していない.
// 書き換わったのは POS の仮置きだけなので, board[POS] を 0 に戻せばよい.
FIND_UNDO:  LDI     B, 100      // POS
            SUB     A, A        // A = 0
            ST      B
            J       FIND_ADV

// 次の行へ進み, 列1から再開する.
FIND_NEXT_ROW:  LDI     A, 105  // ROW
            ADDI    A, 1
            STI     105
            J       FIND_ROW

// 合法手が見つからなかった.
FIND_NONE:  MOVI    A, 0
            RET

// POS に COLOR を置き, 挟める全方向の石を反転する.
//
// 入力:
// - MEM[100] POS
// - MEM[101] COLOR
//
// 出力:
// - board[POS] = COLOR
// - 挟める相手石の列をすべて反転する
// - どこか1方向でも反転したなら MEM[109] FLIPPED = 1, そうでなければ 0
// - 戻る前に A と 0 を比較するので, 呼び出し側は CALL APPLY の直後に JZ/JP を使える.
//
// 10x10 盤面上の方向オフセット:
// -11, -10, -9, -1, 1, 9, 10, 11.
//
// 方向テーブルをメモリに置かないため, C を -11 から始め,
// APPLY_NEXT で +1, +2, +8 を使ってこの列を進める.
APPLY:      LDI     B, 100      // POS
            LDI     A, 101      // COLOR
            ST      B           // MEM[POS] = COLOR
            NOT     A
            STI     102
            SUB     A, A
            STI     109
            MOVI    C, -11

// 現在の方向 C を試す.
//
// FLIP_DIR はこの方向で反転した場合に正の値を返す.
APPLY_DIR:  CALL    FLIP_DIR
            JP      APPLY_MARK

// C を次の方向へ進める.
//
// 方向列:
// -11 -> -10 -> -9 -> -1 -> 1 -> 9 -> 10 -> 11
//
// この列の差分:
// -9 から -1 は +8
// -1 から 1 は +2
// 1 から 9 は +8
// それ以外は +1.
APPLY_NEXT: MOV     A, C
            CMPI    11
            JZ      APPLY_END
            CMPI    -9
            JZ      APPLY_ADD8
            CMPI    -1
            JZ      APPLY_ADD2
            CMPI    1
            JZ      APPLY_ADD8
            MOV     A, C
            ADDI    C, 1
            J       APPLY_DIR

// 方向差分 +8.
APPLY_ADD8: MOV     A, C
            ADDI    C, 6
// 方向差分 +2.
APPLY_ADD2: MOV     A, C
            ADDI    C, 2
            J       APPLY_DIR

// 少なくとも1方向で反転した.
// この手は合法であると記録し, 他方向でも反転できる可能性があるので続行する.
APPLY_MARK: MOVI    A, 1
            STI     109
            J       APPLY_NEXT

// FLIPPED を返し, A - 0 によって符号レジスタを設定する.
APPLY_END:  LDI     A, 109
            CMPI    0
            RET

// POS から現在の方向 C が挟める方向か確認する.
//
// 入力:
// - MEM[100] POS
// - MEM[101] COLOR
// - MEM[102] NEG = -COLOR
// - C = 方向オフセット
//
// 出力:
// - NEG の石が1つ以上続き, その先に COLOR があれば A = 1
// - そうでなければ A = 0
//
// このルーチンは調べるだけで, 盤面は変更しない.
SCAN_DIR:   LDI     A, 100
            ADD     A, C
            STI     104         // SCAN
            CALL    LOAD_SCAN
            LDI     B, 102      // NEG
            CMP     B
            JZ      SCAN_MORE
            SUB     A, A
            RET

// 隣のマスが NEG だったので, NEG でなくなるまで C 方向へ進む.
// 最初に見つかった非 NEG のマスが COLOR なら, この方向は挟める.
SCAN_MORE:  LDI     A, 104      // SCAN
            ADD     A, C
            STI     104
            CALL    LOAD_SCAN
            LDI     B, 102      // NEG
            CMP     B
            JZ      SCAN_MORE
            LDI     B, 101      // COLOR
            CMP     B
            JZ      SCAN_YES
            SUB     A, A
            RET

// 現在の方向は挟める.
SCAN_YES:   MOVI    A, 1
            RET

// SCAN_DIR で挟めると分かった場合, 現在の方向 C の石を反転する.
//
// 入力:
// - SCAN_DIR と同じ
//
// 出力:
// - 反転した場合は A = 1, 符号レジスタは正
// - 挟めない方向だった場合は A = 0, 符号レジスタは 0
FLIP_DIR:   CALL    SCAN_DIR
            JZ      FLIP_RET

// この方向は挟める.
// SCAN を隣マスに戻し, 連続する NEG の石を COLOR で上書きしていく.
FLIP_START: LDI     A, 100
            ADD     A, C
            STI     104
            J       FLIP_LOOP

// 挟めない方向だった. SCAN_DIR がすでに A=0 を返している.
FLIP_RET:   RET

// 連続する NEG の石を反転する.
//
// SCAN_DIR によってこの方向が挟めることは確認済みなので,
// ここで最初に出会う非 NEG のマスは COLOR である.
// つまり, 非 NEG に到達したら反転は完了.
FLIP_LOOP:  CALL    LOAD_SCAN
            LDI     B, 102
            CMP     B
            JZ      FLIP_ONE
            MOVI    A, 1
            RET

// board[SCAN] が NEG だったので, COLOR を書き込み,
// SCAN を方向 C へ進めて反転ループを続ける.
FLIP_ONE:   LDI     B, 104
            LDI     A, 101
            ST      B
            LDI     A, 104
            ADD     A, C
            STI     104
            J       FLIP_LOOP

// board[SCAN] を読み込む.
//
// 入力:
// - MEM[104] SCAN
//
// 出力:
// - A = board[SCAN]
LOAD_SCAN:  LDI     A, 104
            LD      A, A
            RET
