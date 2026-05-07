// プロトコル:
// - このプログラムは白 (1) として打つ. 相手は黒 (-1).
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

// メモリは0で初期化されている前提で初期配置
START:
    MOVI    A, 1
    STI     40      // D4 白
    STI     50      // E5 白
    STI     100     // MyColor = 1
    NOT     A
    STI     41      // E4 黒
    STI     49      // D5 黒
    STI     101     // OppColor = -1

// 相手の手を読み, 盤面に反映. 合法手かチェックはしない
// 重要な文字値:
// - 'A' = -56 なので, 列番号 = 入力 + 57
// - '1' = -72 なので, 行番号 = 入力 + 73
// - 'P' = -41
// 
// 遷移元: MY_TURN
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

// 遷移元: OPP_TURN (thru)
MY_TURN:
//todo

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
// 石を置いてひっくり返す.
// 入力: C = pos, ApplyColor,
// 出力: ApplyRes = (1つも返さなかったら0)
//
// 呼び出し元: OPP_TURN
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
// 遷移元: APPLY_FLIP (JZ)
// 前提: A = 0, B = stopped pos, C = dir /keep
APPLY_UNDO:
    SUB     C, C        // C = ~dir
    LDI     A, 103      // A = ApplyColor
    NOT     A           // A = ~ApplyColor
    STI     104         // FlipColor = ~ApplyColor
    CALL    FLIP        // A = 0
    SUB     C, C        // C = dir
    J       APPLY_NEXT

// 8方向の適用が終わった
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
