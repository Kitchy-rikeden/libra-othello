// Libra Othello player
//
// Protocol:
// - This program plays White (1). The opponent is Black (-1).
// - Input one opponent move per line: D3 or P
// - Output one move per line: D3 or P
//
// Board:
// - Data memory 0..99 is a 10x10 board with an empty border.
// - Playable squares are row 1..8, col 1..8.
// - Cell address = row * 10 + col.
// - 0 = empty, 1 = white, -1 = black.
//
// Variables:
// 100 POS, 101 COLOR, 102 NEG, 103 DIR, 104 SCAN
// 105 ROW, 106 COL, 107 BASE, 108 DIRPTR, 109 DIRCNT, 110 OPPPASS
// 111..118 direction table

START:      MOVI    A, 1
            STI     44          // D4 white
            STI     55          // E5 white
            MOVI    A, -1
            STI     45          // E4 black
            STI     54          // D5 black

            MOVI    A, -11
            STI     111
            MOVI    A, -10
            STI     112
            MOVI    A, -9
            STI     113
            MOVI    A, -1
            STI     114
            MOVI    A, 1
            STI     115
            MOVI    A, 9
            STI     116
            MOVI    A, 10
            STI     117
            MOVI    A, 11
            STI     118

TURN:       LDI     A, 121      // column char or 'P'
            CMPI    -41         // 'P'
            JZ      OPP_PASS

            ADDI    A, 57       // A=col 1..8
            STI     106
            LDI     A, 121      // row char
            ADDI    A, 73       // A=row 1..8
            STI     105
            LDI     A, 121      // consume newline

            CALL    MAKE_POS
            MOVI    A, -1
            STI     101
            CALL    APPLY
            MOVI    A, 0
            STI     110
            J       MY_TURN

OPP_PASS:   LDI     A, 121      // consume newline
            MOVI    A, 1
            STI     110

MY_TURN:    MOVI    A, 1
            STI     101
            CALL    FIND
            CMPI    0
            JZ      MY_PASS

            CALL    APPLY
            LDI     A, 106
            ADDI    A, -57      // col to ASCII-offset
            STI     121
            LDI     A, 105
            ADDI    A, -73      // row to ASCII-offset
            STI     121
            MOVI    A, -111     // newline
            STI     121
            J       TURN

MY_PASS:    LDI     A, 110
            CMPI    1
            JZ      END
            MOVI    A, -41      // 'P'
            STI     121
            MOVI    A, -111     // newline
            STI     121
            J       TURN

END:        HALT

// ROW/COL -> POS
MAKE_POS:   LDI     A, 105
            MOV     B, A
            ADD     A, B        // 2r
            MOV     C, A
            ADD     A, C        // 4r
            MOV     C, A
            ADD     A, C        // 8r
            ADD     A, B        // 9r
            ADD     A, B        // 10r
            LDI     B, 106
            ADD     A, B
            STI     100
            RET

// Find first legal move for COLOR.
// Returns A=1 if found, A=0 otherwise.
FIND:       MOVI    A, 1
            STI     105         // row
            MOVI    A, 10
            STI     107         // base

FIND_ROW:   LDI     A, 105
            CMPI    8
            JP      FIND_NONE
            MOVI    A, 1
            STI     106         // col

FIND_COL:   LDI     A, 106
            CMPI    8
            JP      FIND_NEXT_ROW
            LDI     A, 107
            LDI     B, 106
            ADD     A, B
            STI     100
            MOV     B, A
            LD      A, B
            CMPI    0
            JZ      FIND_EMPTY

FIND_ADV:   LDI     A, 106
            ADDI    A, 1
            STI     106
            J       FIND_COL

FIND_EMPTY: CALL    IS_LEGAL
            CMPI    1
            JZ      FIND_YES
            J       FIND_ADV

FIND_NEXT_ROW:            LDI     A, 105
            ADDI    A, 1
            STI     105
            LDI     A, 107
            ADDI    A, 10
            STI     107
            J       FIND_ROW

FIND_YES:   MOVI    A, 1
            RET

FIND_NONE:  MOVI    A, 0
            RET

// Apply COLOR at POS, flipping all bracketed directions.
APPLY:      LDI     B, 100
            LDI     A, 101
            ST      B
            NOT     A
            STI     102
            MOVI    A, 111
            STI     108
            MOVI    A, 8
            STI     109

APPLY_DIR:  LDI     A, 109
            CMPI    0
            JZ      APPLY_END
            LDI     A, 108
            MOV     B, A
            LD      A, B
            STI     103
            CALL    FLIP_DIR
            LDI     A, 108
            ADDI    A, 1
            STI     108
            LDI     A, 109
            ADDI    A, -1
            STI     109
            J       APPLY_DIR

APPLY_END:  RET

// Returns A=1 if POS is legal for COLOR in at least one direction.
IS_LEGAL:   LDI     A, 101
            NOT     A
            STI     102
            MOVI    A, 111
            STI     108
            MOVI    A, 8
            STI     109

LEGAL_DIR:  LDI     A, 109
            CMPI    0
            JZ      LEGAL_NO
            LDI     A, 108
            MOV     B, A
            LD      A, B
            STI     103
            CALL    SCAN_DIR
            CMPI    1
            JZ      LEGAL_YES
            LDI     A, 108
            ADDI    A, 1
            STI     108
            LDI     A, 109
            ADDI    A, -1
            STI     109
            J       LEGAL_DIR

LEGAL_YES:  MOVI    A, 1
            RET

LEGAL_NO:   MOVI    A, 0
            RET

// Check current DIR from POS.
// Returns A=1 if at least one NEG stone is followed by COLOR.
SCAN_DIR:   LDI     A, 100
            LDI     B, 103
            ADD     A, B
            STI     104
            CALL    LOAD_SCAN
            LDI     C, 102
            CMP     C
            JZ      SCAN_MORE
            MOVI    A, 0
            RET

SCAN_MORE:  LDI     A, 104
            LDI     B, 103
            ADD     A, B
            STI     104
            CALL    LOAD_SCAN
            LDI     C, 102
            CMP     C
            JZ      SCAN_MORE
            LDI     C, 101
            CMP     C
            JZ      SCAN_YES
            MOVI    A, 0
            RET

SCAN_YES:   MOVI    A, 1
            RET

// Flip stones in current DIR if SCAN_DIR says it is bracketed.
FLIP_DIR:   CALL    SCAN_DIR
            CMPI    1
            JZ      FLIP_START
            RET

FLIP_START: LDI     A, 100
            LDI     B, 103
            ADD     A, B
            STI     104

FLIP_LOOP:  CALL    LOAD_SCAN
            LDI     C, 102
            CMP     C
            JZ      FLIP_ONE
            RET

FLIP_ONE:   LDI     B, 104
            LDI     A, 101
            ST      B
            LDI     A, 104
            LDI     B, 103
            ADD     A, B
            STI     104
            J       FLIP_LOOP

// A = board[SCAN]
LOAD_SCAN:  LDI     A, 104
            MOV     B, A
            LD      A, B
            RET
