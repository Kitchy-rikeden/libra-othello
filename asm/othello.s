// プロトコル:
// - このプログラムが先行(黒)なら'B', 後攻(白)なら'W' を最初に1行送る.
// - 入力は相手の手を1行ずつ受け取る: D3 または P
// - 出力は自分の手を1行ずつ返す: D3 または P
//
// メモリ
// 0 ~ 89 : 盤面(番兵込み)
// row: 1 ~ 8, col 1 ~ 8 とし, address = row * 9 + col
// row == 0, 9, col == 0 は番兵.
// 0 = 空き, 1 = 白, -1 = 黒.
// 
// 100: MyColor, 101: OppColor
// 102: ApplyRes, 103: ApplyColor
// 104: FlipColor
// 110: OppPass

// メモリ初期化 (0 ~ 120)
// C = pos
    SUB     C, A    // C = 0
CLEAR:
    SUB     A, A    // A = 0
    ST      C       // board[pos] = 0
    MOV     A, C    // A = pos
    CMPI    120
    JZ      INIT    // if (pos == 89)
    ADDI    C, 1    // C = pos + 1
    J       CLEAR

// 石の初期配置, 先攻後攻の決定
INIT:
    MOVI    A, 1
    STI     40      // D4 白
    STI     50      // E5 白
    NOT     A
    STI     41      // E4 黒
    STI     49      // D5 黒
    LDI     A, 121  // A = MMIO in
    LDI     B, 121  // 改行読み飛ばし
    ADDI    A, 35   // 'W' = -34 なら A = 1, 'B' = -55 なら A < 0
    JP      INIT_L1 // if (A == 'W')
    MOVI    A, -1   // A = MyColor
INIT_L1:
    STI     100     // MyColor = MyColor
    NOT     A
    STI     101     // OppColor = ~MyColor
    CMPI    0
    JP      MY_TURN // if (OppColor == 1)

// 相手の手を読み, 盤面に反映. 合法手かチェックはしない
// 重要な文字値:
// - 'A' = -56 なので, 列番号 = 入力 + 57
// - '1' = -72 なので, 行番号 = 入力 + 73
// - 'P' = -41
// 
// 遷移元: SEARCH_OK (J), INIT_L1 (thru)
OPP_TURN:
    MOVI    B, 121
    LD      A, B        // MMIO in
    ADDI    C, 57       // C = col
    ADDI    A, 42       // check 'P' (A は 'A'-'G', 'P' のみなので 'P' のときだけ正になる)
    JP      OPP_PASS

    LD      A, B        // MMIO in
    LD      B, B        // 改行読み飛ばし
    ADDI    A, 73       // A = row
    CALL    MAKE_POS    // C = pos
    LDI     A, 101      // A = OppColor
    STI     103         // ApplyColor = OppColor
    CALL    APPLY

    // 相手入力は合法と仮定するので戻り値は無視する.
    SUB     A, A        // A = 0
    STI     110         // OppPass
    J       MY_TURN

// 遷移元: OPP_TURN (JP)
// 前提: A = 1, B = 121
OPP_PASS:
    STI     110         // OppPass = 1
    LD      C, B        // 改行読み飛ばし

// 合法手を探して最初に見つかったものを選ぶ
// 遷移元: OPP_PASS (thru)
MY_TURN:
    LDI     A, 100      // A = MyColor
    STI     103         // ApplyColor = MyColor
    MOVI    C, 10       // C = pos

// pos から始めて置けるかどうか試す
// 遷移元: MY_TURN (thru), SEARCH_NEXT
// 前提: C = pos, ApplyColor = MyColor
SEARCH:
    LD      A, C        // A = board[pos]
    CMPI    0
    JZ      SEARCH_TRY  // if (board[pos] == 0)
    J       SEARCH_NEXT // else

// pos が空きなので置いてみる.
// 遷移元: SEARCH (JZ)
// 前提: C = pos, ApplyColor = MyColor
SEARCH_TRY:
    CALL    APPLY       // C = pos
    LDI     A, 102      // A = ApplyRes
    CMPI    0
    JZ      SEARCH_UNDO // if (ApplyRes == 0)

// 置けたので出力する.
// 遷移元: SEARCH_TRY (thru)
// 前提: C = pos
SEARCH_OK:
    MOV     A, C        // A = pos
    // pos = 9 * row + col から row と col を取り出す.
    // col は 0~8 であるが、pos の下2桁は -4~4 のためそのままは取り出せない.
    // pos-4 を考えると col-4 は -4~4 になり、上位3桁は row に一致する.
    ADDI    A, -4       // A = pos - 4
    SR      A
    SR      A           // A = row
    MOV     B, A        // B = row
    SL      A
    SL      A           // A = row * 9
    SUB     A, C        // A = -col
    NOT     A           // A = col
    ADDI    A, -57      // col を 'A'-'H' に
    MOVI    C, 121      // C = 121
    ST      C           // MMIO out
    MOV     A, B        // A = row
    ADDI    A, -73      // row を '1'-'8' に
    ST      C           // MMIO out
    MOVI    A, -111     // A = '\n'
    ST      C           // MMIO out
    J       OPP_TURN

// 置いてみた石が違法だったためキャンセル
// 前提: A = 0, C = pos, ApplyColor = MyColor
SEARCH_UNDO:
    ST      C           // board[pos] = 0

// 次の pos へ
// 遷移元: SEARCH (JZ), SEARCH_NEXT (JZ), SEARCH_UNDO (thru)
// 前提: C = pos, ApplyColor = MyColor
SEARCH_NEXT:
    MOV     A, C        // A = pos
    CMPI    80
    JZ      SEARCH_END  // if (pos == 80)
    ADDI    C, 1        // C = pos + 1
    MOV     A, C        // A = pos + 1
    ANDI    A, 0t###11  // A &= 0t###11
    CMPI    0t###00
    JZ      SEARCH_NEXT // if ((pos+1) % 9 == 0) then +1 again
    J       SEARCH

// 合法手が見つからなかった
// 遷移元: SEARCH_NEXT
SEARCH_END:
    MOVI    A, -41      // A = 'P'
    STI     121         // MMIO out
    MOVI    A, -111     // A = '\n'
    STI     121         // MMIO out
    LDI     A, 110      // A = OppPass
    CMPI    0
    JZ      OPP_TURN    // if (OppPass == 0)

// 相手と自分が連続でパスしたため終了
// 遷移元: SEARCH_END (thru)
GAME_END:
    HALT

// function
// 入力: A = row, B /k, C = col
// 出力: C = pos
// 
// 呼び出し元: OPP_TURN
MAKE_POS:
    SL      A
    SL      A
    ADD     C, C
    RET

// function
// 石を置いてひっくり返す. pos は空きマスという前提.
// 入力: C = pos /keep, ApplyColor,
// 出力: ApplyRes = (1つも返さなかったら0)
//
// 呼び出し元: OPP_TURN, SEARCH
APPLY:
    SUB     A, A        // A = 0
    STI     102         // ApplyRes = 0
    MOV     A, C        // A = pos
    MOVI    C, -10

// 隣接マスが逆の色かどうか調べる
// 遷移元: APPLY (thru), APPLY_NEXT_ADD1 (J)
// 前提: A = pos, C = dir
APPLY_DIR_FIRST:
    PUSH                // push_1. pos
    ADD     A, C        // A = moved pos
    PUSH                // push_2. moved pos
    LD      A, A        // A = board[moved pos]
    NOT     B           // B = ~board[moved pos]
    LDI     A, 103      // A = ApplyColor
    CMP     B
    POP     B           // pop_2. B = moved pos
    JZ      APPLY_FLIP  // if (~board[moved pos] == ApplyColor)

// 次の方向の処理に進む
// 遷移元: APPLY_DIR_FIRST (thru), APPLY_FLIP (J), APPLY_UNDO (J) 
// 前提: C = dir
APPLY_NEXT:
    MOV     A, C        // A = dir
    CMPI    10
    JZ      APPLY_END
    CMPI    -8
    JZ      APPLY_NEXT_ADD7
    CMPI    1
    JZ      APPLY_NEXT_ADD7
    J       APPLY_NEXT_ADD1
APPLY_NEXT_ADD7:
    ADDI    A, 6        // A = dir + 6
APPLY_NEXT_ADD1:
    ADDI    C, 1        // C = (dir or dir+6) + 1
    POP     A           // pop_1. A = pos
    J       APPLY_DIR_FIRST

// 隣接マスが逆の色だったのでひっくり返してみる.
// 遷移元: APPLY_DIR_FIRST (JZ)
// 前提: A = ApplyColor, B = pos, C = dir /keep
APPLY_FLIP:
    STI     104         // FlipColor = ApplyColor
    CALL    FLIP
    CMPI    0
    JZ      APPLY_UNDO  // if (flip result == 0)
    STI     102         // ApplyRes = 1 or -1
    J       APPLY_NEXT

// ひっくり返してみたがダメだったので元に戻す. 元の位置には必ず空きマスがあるはずなので, 逆向きにFlipする.
// 止まったマスの1つ手前に戻ってからFLIPを実行
// 遷移元: APPLY_FLIP (JZ)
// 前提: A = 0, B = stopped pos, C = dir /keep
APPLY_UNDO:
    SUB     C, C        // C = ~dir
    MOV     A, B        // A = stopped pos
    ADD     B, C        // B = stopped pos - dir ; 1個戻ったマス
    LDI     A, 103      // A = ApplyColor
    NOT     A           // A = ~ApplyColor
    STI     104         // FlipColor = ~ApplyColor
    CALL    FLIP        // A = 0
    SUB     C, C        // C = dir
    J       APPLY_NEXT

// 8方向の適用が終わった. 最後に石を置く.
// 遷移元: APPLY_NEXT (JZ)
APPLY_END:
    POP     C           // pop_1. C = pos
    LDI     A, 103      // A = ApplyColor
    ST      C           // board[pos] = color
    RET

// function
// 指定の方向にひっくり返していく. pos を返してから次に進む. pos はひっくり返せる前提.
// FlipColor か空きマスにぶつかったら終了し、止まったマスの位置と色を返す.
//
// 入力: A = FlipColor, B = pos, C = dir /keep
// 出力: A = result, B = stopped pos
// 呼び出し元: APPLY_DIR_FIRST, APPLY_UNDO
FLIP:
    ST      B           // board[pos] = FlipColor
    MOV     A, B        // A = pos
    ADD     A, C        // A = moved pos
    PUSH                // push_3. moved pos
    LD      A, A        // A = board[moved pos]
    CMPI    0
    JZ      FLIP_END    // if (board[moved pos] == 0) 
    LDI     B, 104      // B = FlipColor
    CMP     B
    JZ      FLIP_END    // if (board[moved pos] == FlipColor)
    POP     B           // pop_3. B = moved pos
    NOT     A           // A = FlipColor
    J       FLIP
FLIP_END:
    POP     B           // pop_3. B = moved pos
    RET
