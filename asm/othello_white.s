// Libra オセロプレイヤー
//
// プロトコル:
// - このプログラムは白 (1) として打つ. 相手は黒 (-1).
// - 入力は相手の手を1行ずつ受け取る: D3 または P
// - 出力は自分の手を1行ずつ返す: D3 または P
//
// 盤面:
// - データメモリ 0..89 を, 番兵つきの 10行x9列 盤面として使う.
// - 実際に打てるマスは 行 1..8, 列 1..8.
// - マスのアドレス = 行 * 9 + 列.
// - 各行の列0を左右共用の番兵として使う.
// - 0 = 空き, 1 = 白, -1 = 黒.
//
// 変数:
// 100 POS, 101 COLOR, 102 NEG
// 105 ROW, 106 COL, 109 FLIPPED, 110 OPPPASS

// 盤面を初期化する.
//
// オセロ自体は 8x8 だが, ここでは 10行x9列の配列として持つ.
// 行0/行9と各行の列0を番兵にする. 右端から +1 した場合は
// 次行の列0に入るため, 右番兵と左番兵を共用できる.
//
// 初期配置:
// - 白 = 1: D4, E5
// - 黒 = -1: E4, D5
//
// レジスタ使用:
// - A: 作業用. 初期石の値 1, -1 を入れる. 破壊される.
// - B: 未使用. このブロックでは保存される.
// - C: 未使用. このブロックでは保存される.
START:      MOVI    A, 1
            STI     40          // D4 白
            STI     50          // E5 白
            NOT     A
            STI     41          // E4 黒
            STI     49          // D5 黒

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
//
// レジスタ使用:
// - A: 入力文字, ROW/COL 変換, サブルーチン戻り値用. 破壊される.
// - B: 入力なし. 最初に MMIO アドレス 121 を入れる.
//      パス分岐では OPP_PASS へ B=121 を渡す.
//      通常手では CALL MAKE_POS と CALL APPLY により破壊される.
// - C: 入力なし. 通常手では COL 退避, CALL MAKE_POS, CALL APPLY により破壊される.
//      パス分岐ではこのブロック内では使わない.
TURN:       MOVI    B, 121
            LD      A, B        // 列文字または 'P'
            CMPI    -41         // 'P'
            JZ      OPP_PASS

            // 相手の手の文字列を数値の COL/ROW に変換し,
            // 最後の改行を読み捨てる. 相手の手は合法であると信用する.
            ADDI    A, 57       // A=col 1..8
            MOV     C, A        // C=COL. ROW 読み取り中だけ退避
            LD      A, B        // 行文字
            ADDI    A, 73       // A=行 1..8

            // 相手の手を黒として盤面に反映する.
            // APPLY は石が反転したかどうかを返すが,
            // 相手入力は合法と仮定するので戻り値は無視する.
            MOV     B, C
            CALL    MAKE_POS
            MOVI    B, 121
            LD      A, B        // 改行を読み捨て
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
//
// レジスタ使用:
// - A: 改行読み捨てと OPPPASS=1 の書き込みに使う. 破壊される.
// - B: 入力. TURN から B=121 が来ている前提で MMIO 読み取りに使う. 保存される.
// - C: 未使用. 保存される.
OPP_PASS:   LD      A, B        // 改行を読み捨て
            MOVI    A, 1
            STI     110

// 自分の手を選ぶ.
//
// このプログラムは常に白として打つので COLOR に 1 を入れる.
// FIND は最初に見つけた合法手を探し, 見つけたらその場で盤面に反映する.
// FIND が 0 を返した場合は合法手なしなのでパスする.
//
// レジスタ使用:
// - A: COLOR=1 設定, FIND の戻り値, 出力文字生成に使う. 破壊される.
//      CALL FIND は A を破壊し, 戻り値 A と符号レジスタだけを保証する.
// - B: 入力なし. CALL FIND で破壊される. 出力時は MMIO アドレス 121 を保持する.
// - C: 入力なし. CALL FIND 内部の CALL APPLY により破壊される.
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
//
// レジスタ使用:
// - A: OPPPASS 判定と "P\n" 出力に使う. 破壊される.
// - B: 未使用. このブロックでは保存される.
// - C: 未使用. このブロックでは保存される.
MY_PASS:    LDI     A, 110      // OPPPASS
            CMPI    1
            JZ      END
            MOVI    A, -41      // 'P'
            STI     121
            MOVI    A, -111     // 改行
            STI     121
            J       TURN

// 両者連続パスで停止する.
//
// レジスタ使用:
// - A/B/C: 参照しない. HALT するため保存は意味を持たない.
END:        HALT

// ROW/COL を盤面アドレスに変換する.
//
// 入力:
// - A = ROW: 1..8
// - B = COL: 1..8
//
// 出力:
// - A = ROW * 9 + COL
// - MEM[100] POS = ROW * 9 + COL
//
// レジスタ使用:
// - A: 入出力. 入力 ROW を受け取り, POS を計算して返す. 破壊されるが戻り値になる.
// - B: 入力 COL. 計算中は COL として使う. 保存される.
// - C: 未使用. 保存される.
// - CALL: なし. CALL 先による追加破壊はない.
MAKE_POS:   SL      A       // 3r
            SL      A       // 9r
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
//
// レジスタ使用:
// - A: ROW/COL/POS 計算, セル値確認, APPLY 戻り値に使う.
//      出力は A=1 相当または A=0. 符号レジスタも戻り値判定に使う.
// - B: MAKE_POS 後の POS アドレス保持, セル読み込み, UNDO に使う. 破壊される.
// - C: FIND 自体の直接入力ではないが, CALL APPLY が方向オフセットに使うため破壊される.
// - CALL:
//   - MAKE_POS は A を破壊し, B/C を保存する.
//   - APPLY は A/B/C を破壊し, A と符号レジスタで成否を返す.
FIND:       MOVI    A, 1
            STI     105         // ROW

// 行の開始または継続. ROW > 8 なら盤面全体を調べ終わった.
//
// レジスタ使用:
// - A: ROW 判定と COL 初期化に使う. 破壊される.
// - B/C: この小ブロックでは未使用. ただし FIND 全体としては後続 CALL で破壊される.
FIND_ROW:   LDI     A, 105
            CMPI    8
            JP      FIND_NONE
            MOVI    A, 1
            STI     106         // COL

// 現在の行で列を1つ調べる.
//
// 空きでないマスはスキップする.
// 空きマスだけ候補手として試す.
//
// レジスタ使用:
// - A: COL 判定, ROW 入力, MAKE_POS 戻り値, board[POS] 読み込み値に使う. 破壊される.
// - B: COL 入力として使う. CALL MAKE_POS 後はこの小ブロックでは使わない.
// - C: この小ブロックでは直接使わない. CALL MAKE_POS でも保存される.
FIND_COL:   LDI     A, 106
            CMPI    8
            JP      FIND_NEXT_ROW
            MOV     B, A
            LDI     A, 105
            CALL    MAKE_POS
            LD      A, A
            CMPI    0
            JZ      FIND_EMPTY

// 次の列へ進む.
//
// レジスタ使用:
// - A: COL+1 の計算に使う. 破壊される.
// - B/C: 未使用. この小ブロックでは保存される.
FIND_ADV:   LDI     A, 106
            ADDI    A, 1
            STI     106
            J       FIND_COL

// 候補マスが空きだったので, ここに COLOR を置いてみる.
//
// APPLY が 0 を返すならどの方向も反転せず, その手は不合法.
// 0 でなければ合法手はすでに反映済みなので, FIND はそのまま戻る.
//
// レジスタ使用:
// - A: CALL APPLY の戻り値. 戻る場合は合法手ありを示す非ゼロ値.
// - B: CALL APPLY により破壊される.
// - C: CALL APPLY により破壊される.
FIND_EMPTY: CALL    APPLY
            JZ      FIND_UNDO
            RET

// 不合法だった候補手を取り消す.
//
// APPLY が 0 を返したとき, 相手の石は1つも変化していない.
// 書き換わったのは POS の仮置きだけなので, board[POS] を 0 に戻せばよい.
//
// レジスタ使用:
// - A: 0 を作って board[POS] に書き込む. 破壊される.
// - B: POS を読み, board[POS] のアドレスとして使う. 破壊される.
// - C: 未使用. 保存される.
FIND_UNDO:  LDI     B, 100      // POS
            SUB     A, A        // A = 0
            ST      B
            J       FIND_ADV

// 次の行へ進み, 列1から再開する.
//
// レジスタ使用:
// - A: ROW+1 の計算に使う. 破壊される.
// - B/C: 未使用. この小ブロックでは保存される.
FIND_NEXT_ROW:  LDI     A, 105  // ROW
            ADDI    A, 1
            STI     105
            J       FIND_ROW

// 合法手が見つからなかった.
//
// レジスタ使用:
// - A: 出力. 0 を返す.
// - B/C: 未使用. この小ブロックでは保存される.
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
// 10行x9列 盤面上の方向オフセット:
// -10, -9, -8, -1, 1, 8, 9, 10.
//
// 方向テーブルをメモリに置かないため, C を -10 から始め,
// APPLY_NEXT で +1, +2, +7 を使ってこの列を進める.
//
// レジスタ使用:
// - A: COLOR 読み込み, NEG 作成, FLIPPED 初期化, FLIP_DIR 戻り値,
//      最終戻り値に使う. 破壊されるが, 戻り値として FLIPPED を返す.
// - B: POS アドレス保持などの作業用. CALL FLIP_DIR 経由でも破壊される.
// - C: 方向オフセットとして -10 から 10 まで進める. 入力値は不要で, 破壊される.
// - CALL:
//   - FLIP_DIR は A/B を破壊し, C を方向入力として保存する.
//   - FLIP_DIR 内部の SCAN_DIR も A/B を破壊し, C は保存する.
APPLY:      LDI     B, 100      // POS
            LDI     A, 101      // COLOR
            ST      B           // MEM[POS] = COLOR
            NOT     A
            STI     102
            SUB     A, A
            STI     109
            MOVI    C, -10

// 現在の方向 C を試す.
//
// FLIP_DIR はこの方向で反転した場合に正の値を返す.
//
// レジスタ使用:
// - A: CALL FLIP_DIR の戻り値. JP 判定に使う.
// - B: CALL FLIP_DIR により破壊される.
// - C: 入力. 現在の方向オフセット. FLIP_DIR では保存される.
APPLY_DIR:  CALL    FLIP_DIR
            JP      APPLY_MARK

// C を次の方向へ進める.
//
// 方向列:
// -10 -> -9 -> -8 -> -1 -> (0) -> 1 -> 8 -> 9 -> 10
//
// この列の差分:
// -8, 1 からは +7
// それ以外は +1.
// 0 は方向としては不適だが, やっても問題はない.
//
// レジスタ使用:
// - A: C の値を比較するための作業用. 破壊される.
// - B: 未使用. この小ブロックでは保存される.
// - C: 入出力. 次の方向オフセットへ更新される.
APPLY_NEXT: MOV     A, C
            CMPI    10
            JZ      APPLY_END
            CMPI    -8
            JZ      APPLY_ADD7
            CMPI    1
            JZ      APPLY_ADD7
            ADDI    C, 1
            J       APPLY_DIR

// 方向差分 +7.
//
// レジスタ使用:
// - A: C を A に移して ADDI のソースにする. 破壊される.
// - B: 未使用. 保存される.
// - C: 入出力. 合計 +7 される.
//      実装上はここで +5 し, 直後の APPLY_ADD2 に落ちてさらに +2 する.
APPLY_ADD7: ADDI    C, 7
            J       APPLY_DIR

// 少なくとも1方向で反転した.
// この手は合法であると記録し, 他方向でも反転できる可能性があるので続行する.
//
// レジスタ使用:
// - A: FLIPPED=1 の書き込みに使う. 破壊される.
// - B: 未使用. 保存される.
// - C: 入力. 現在方向を保持したまま APPLY_NEXT へ渡す. 保存される.
APPLY_MARK: MOVI    A, 1
            STI     109
            J       APPLY_NEXT

// FLIPPED を返し, A - 0 によって符号レジスタを設定する.
//
// レジスタ使用:
// - A: 出力. MEM[109] FLIPPED を返し, CMPI 0 で符号レジスタを設定する.
// - B: 未使用. この小ブロックでは保存される.
// - C: 方向探索後の値が残るが, APPLY の呼び出し規約上は破壊扱い.
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
//
// レジスタ使用:
// - A: SCAN 計算, board[SCAN] 読み込み値, 戻り値 0/1 に使う. 破壊される.
// - B: NEG/COLOR の比較用に使う. 破壊される.
// - C: 入力. 方向オフセットとして参照する. 保存される.
// - スタック: SCAN を一時退避する. RET 前には必ず POP して戻す.
SCAN_DIR:   LDI     A, 100
            ADD     A, C
            PUSH                // SCAN
            LD      A, A        // A = board[SCAN]
            LDI     B, 102      // NEG
            CMP     B
            JZ      SCAN_MORE
            POP     B           // SCAN を破棄
            SUB     A, A
            RET

// 隣のマスが NEG だったので, NEG でなくなるまで C 方向へ進む.
// 最初に見つかった非 NEG のマスが COLOR なら, この方向は挟める.
//
// レジスタ使用:
// - A: SCAN 更新, board[SCAN] 読み込み値, 戻り値 0 に使う. 破壊される.
// - B: NEG/COLOR 比較に使う. 破壊される.
// - C: 入力. 方向オフセットとして使う. 保存される.
// - スタック: 入口で前回の SCAN が積まれている. 次の SCAN に置き換え,
//   ループ継続なら積んだまま, 終了時は POP して戻す.
SCAN_MORE:  POP     A           // A = SCAN
            ADD     A, C
            PUSH                // 次の SCAN
            LD      A, A        // A = board[SCAN]
            LDI     B, 102      // NEG
            CMP     B
            JZ      SCAN_MORE
            POP     B           // SCAN を破棄
            LDI     B, 101      // COLOR
            CMP     B
            JZ      SCAN_YES
            SUB     A, A
            RET

// 現在の方向は挟める.
//
// レジスタ使用:
// - A: 出力. 1 を返す.
// - B/C: 未使用. この小ブロックでは保存される.
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
//
// レジスタ使用:
// - A: SCAN_DIR/FLIP_LOOP の戻り値. 破壊されるが, 成否の戻り値になる.
// - B: SCAN_DIR/FLIP_LOOP により破壊される.
// - C: 入力. 方向オフセット. SCAN_DIR と反転ループでは保存される.
// - CALL:
//   - SCAN_DIR は A/B を破壊し, C を保存する.
FLIP_DIR:   CALL    SCAN_DIR
            JZ      FLIP_RET

// この方向は挟める.
// SCAN を隣マスに戻し, 連続する NEG の石を COLOR で上書きしていく.
//
// レジスタ使用:
// - A: SCAN 初期化に使う. 破壊される.
// - B: 未使用. この小ブロックでは保存される.
// - C: 入力. 方向オフセットとして使う. 保存される.
// - スタック: 最初の SCAN を積んで FLIP_LOOP に渡す.
FLIP_START: LDI     A, 100
            ADD     A, C
            PUSH                // SCAN
            J       FLIP_LOOP

// 挟めない方向だった. SCAN_DIR がすでに A=0 を返している.
//
// レジスタ使用:
// - A: 出力. SCAN_DIR の 0 をそのまま返す.
// - B: SCAN_DIR で破壊済み.
// - C: 保存される.
FLIP_RET:   RET

// 連続する NEG の石を反転する.
//
// SCAN_DIR によってこの方向が挟めることは確認済みなので,
// ここで最初に出会う非 NEG のマスは COLOR である.
// つまり, 非 NEG に到達したら反転は完了.
//
// レジスタ使用:
// - A: board[SCAN] の読み込み値, 比較, 最終戻り値 1 に使う. 破壊される.
// - B: NEG 比較用に使う. 破壊される.
// - C: 入力. 方向オフセット. 保存される.
// - スタック: 入口で SCAN が積まれている. NEG なら FLIP_ONE が POP し,
//   終了時はここで POP して戻す.
FLIP_LOOP:  POP     A           // A = SCAN
            PUSH                // FLIP_ONE 用に SCAN を残す
            LD      A, A        // A = board[SCAN]
            LDI     B, 102
            CMP     B
            JZ      FLIP_ONE
            POP     B           // SCAN を破棄
            MOVI    A, 1
            RET

// board[SCAN] が NEG だったので, COLOR を書き込み,
// SCAN を方向 C へ進めて反転ループを続ける.
//
// レジスタ使用:
// - A: COLOR 読み込み, SCAN 更新に使う. 破壊される.
// - B: board[SCAN] のアドレスとして使う. 破壊される.
// - C: 入力. 方向オフセットとして使う. 保存される.
// - スタック: FLIP_LOOP が残した SCAN を POP して使い切り,
//   次の SCAN を PUSH して FLIP_LOOP に渡す.
FLIP_ONE:   POP     B           // B = SCAN
            LDI     A, 101
            ST      B
            MOV     A, B
            ADD     A, C
            PUSH                // 次の SCAN
            J       FLIP_LOOP
