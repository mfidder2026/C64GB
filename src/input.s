; ---------------------------------------------------------------------------
; Input: joystick port 2, WASD and keys (resident, $C300 area)
; ---------------------------------------------------------------------------

; Joystick port 2 + keyboard -> joy_dirs / joy_btns.
read_input:
        lda #$FF
        sta $DC02               ; port A output (keyboard columns)
        lda #0
        sta $DC03               ; port B input
        lda #$FF
        sta $DC00
        lda $DC00               ; joystick 2, active low
        eor #$FF
        tax
        and #$0F
        tay
        lda joymap,y
        sta joy_dirs
        txa
        and #$10
        beq :+
        lda #1                  ; fire = A
:       sta joy_btns
        lda #$7F                ; column 7: SPACE = B (row 4)
        sta $DC00
        lda $DC01
        and #$10
        bne :+
        lda joy_btns
        ora #2
        sta joy_btns
:       lda #$FD                ; column 1: left SHIFT = Select (row 7)
        sta $DC00
        lda $DC01
        and #$80
        bne :+
        lda joy_btns
        ora #4
        sta joy_btns
:       lda #$FE                ; column 0: RETURN = Start (row 1)
        sta $DC00
        lda $DC01
        tax
        and #$02
        bne :+
        lda joy_btns
        ora #8
        sta joy_btns
:       lda #$FF
        sta $DC00
        lda #$FD                ; column 1: W (row 1), A (row 2), S (row 5)
        sta $DC00
        lda $DC01
        eor #$FF
        sta etmp
        lda #$FB                ; column 2: D (row 2)
        sta $DC00
        lda $DC01
        and #$04
        bne :+
        lda joy_dirs
        ora #1                  ; right
        sta joy_dirs
:       lda etmp
        and #$02
        beq :+
        lda joy_dirs
        ora #4                  ; up
        sta joy_dirs
:       lda etmp
        and #$04
        beq :+
        lda joy_dirs
        ora #2                  ; left
        sta joy_dirs
:       lda etmp
        and #$20
        beq :+
        lda joy_dirs
        ora #8                  ; down
        sta joy_dirs
:       lda #$FF
        sta $DC00
        txa                     ; F1 (row 4): save the game on key press
        and #$10
        cmp f1_prev
        sta f1_prev
        beq :+
        cmp #0
        bne :+
        jmp save_game
:       rts

; C64 joystick (bit0 up, 1 down, 2 left, 3 right) -> GB (0 R, 1 L, 2 U, 3 D)
joymap:
        .repeat 16, I
        .byte ((I & 8) >> 3) | ((I & 4) >> 1) | ((I & 1) << 2) | ((I & 2) << 2)
        .endrep

