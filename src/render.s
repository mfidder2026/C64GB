; ---------------------------------------------------------------------------
; Scanline renderer: GB line -> C64 multicolor bitmap (160x200, 2bpp)
;
; Each GB tile row (8 pixels, 2 bitplanes) becomes 2 bitmap bytes of 4
; double-wide pixels. GB line y lives in bitmap cell row (y/8)+3, so the
; 144 GB lines are centred in the 200 bitmap lines.
; Bit pair value = GB shade: 0 white ($D021), 1 light grey (screen hi nibble),
; 2 dark grey (screen lo nibble), 3 black (color RAM).
; ---------------------------------------------------------------------------



.segment "BSS"
conv:     .res 256      ; (hi nibble << 4 | lo nibble) -> 4 packed pixels
shr4:     .res 256
shl4:     .res 256
rev:      .res 256      ; bit reversal (sprite X flip)
tlo:      .res 256      ; (tile << 4) & $F0
thi_u:    .res 256      ; tile data page, $8000 addressing
thi_s:    .res 256      ; tile data page, $8800 (signed) addressing
line_lo:  .res 144
line_hi:  .res 144
xoff_lo:  .res 160
xoff_hi:  .res 160
spr_list: .res 10
finebuf:  .res 21*16
shade4:   .res 4
.segment "CODE"

; Build the static lookup tables.
render_init:
        ldx #0
@t:     txa
        lsr
        lsr
        lsr
        lsr
        sta shr4,x
        txa
        asl
        asl
        asl
        asl
        sta shl4,x
        sta tlo,x
        txa                     ; bit reverse
        ldy #8
:       lsr
        rol r_t
        dey
        bne :-
        lda r_t
        sta rev,x
        txa
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>VRAM
        sta thi_u,x
        cpx #$80
        bcs :+
        adc #$10                ; tiles 0-127 at $9000 in signed mode
:       sta thi_s,x
        inx
        bne @t

        ; bitmap line addresses
        ldx #0
@l:     txa
        lsr
        lsr
        lsr
        clc
        adc #TOP_ROW
        tay                     ; Y = cell row
        lda #0
        sta r_lo
        sta r_hi
:       cpy #0                  ; r_hi:r_lo = cell row * 320
        beq :+
        clc
        lda r_lo
        adc #<320
        sta r_lo
        lda r_hi
        adc #>320
        sta r_hi
        dey
        jmp :-
:       txa
        and #7
        clc
        adc r_lo
        sta line_lo,x
        lda r_hi
        adc #>BITMAP
        sta line_hi,x
        inx
        cpx #144
        bne @l

        ; pixel x -> byte offset within a line
        ldx #0
@x:     txa
        lsr
        lsr
        lsr
        sta r_t                 ; tile column
        lda #0
        sta r_hi
        lda r_t
        asl
        asl
        asl
        asl
        rol r_hi
        sta r_lo                ; column * 16
        txa
        and #4
        beq :+
        lda r_lo
        ora #8
        sta r_lo
:       lda r_lo
        sta xoff_lo,x
        lda r_hi
        sta xoff_hi,x
        inx
        cpx #160
        bne @x

        lda #1
        sta r_on
        lda IORAM+$47
        eor #$FF
        sta bgp_cache           ; force a conversion table build
        rts

; Rebuild conv[] for the palette in BGP.
build_conv:
        lda IORAM+$47
        sta bgp_cache
        ldy #0
:       pha
        and #3
        sta shade4,y
        pla
        lsr
        lsr
        iny
        cpy #4
        bne :-
        lda shade4
        sta r_bg0
        ldx #0
@e:     stx r_lo                ; low nibble: bitplane 0 of 4 pixels
        txa
        lsr
        lsr
        lsr
        lsr
        sta r_hi                ; high nibble: bitplane 1
        lda #0
        sta r_t
        lda #4
        sta r_px
@p:     ldy #0                  ; color of the pixel in bit 3
        lda r_lo
        and #8
        beq :+
        iny
:       lda r_hi
        and #8
        beq :+
        iny
        iny
:       asl r_lo
        asl r_hi
        lda r_t
        asl
        asl
        ora shade4,y
        sta r_t
        dec r_px
        bne @p
        sta conv,x
        inx
        bne @e
        rts

; Render GB line `ly` (called at the start of hblank).
hblank_hook:
        lda r_on
        bne :+
        rts
:       lda IORAM+$47
        cmp bgp_cache
        beq :+
        jsr build_conv
:       ldx ly
        lda line_lo,x
        sta r_dst
        sta r_line
        lda line_hi,x
        sta r_dst+1
        sta r_line+1

        ; tile data addressing mode
        lda IORAM+$40
        and #$10
        beq :+
        lda #<thi_u
        ldx #>thi_u
        bne :++
:       lda #<thi_s
        ldx #>thi_s
:       sta col_thi+1
        stx col_thi+2

        ; window start column
        lda #20
        sta r_wcol
        lda IORAM+$40
        and #$20
        beq @nowin
        lda ly
        cmp IORAM+$4A
        bcc @nowin
        lda IORAM+$4B
        sec
        sbc #7
        bcs :+
        lda #0
:       cmp #160
        bcs @nowin
        lsr
        lsr
        lsr
        sta r_wcol
@nowin:
        lda IORAM+$40
        and #1
        bne @bg
        ; BG and window off: white line
        lda #20
        sta r_t
:       lda #0
        ldy #0
        sta (r_dst),y
        ldy #8
        sta (r_dst),y
        clc
        lda r_dst
        adc #16
        sta r_dst
        bcc :+
        inc r_dst+1
:       dec r_t
        bne :--
        jmp @sprites
@bg:
        lda #0
        sta r_col
        lda r_wcol
        beq @win
        sta r_end
        ; background row
        lda ly
        clc
        adc IORAM+$42           ; SCY
        tax
        and #7
        asl
        sta r_fine
        txa
        and #$F8
        ldx #0
        stx r_map+1
        asl
        rol r_map+1
        asl
        rol r_map+1
        sta r_map
        lda IORAM+$40
        and #$08
        beq :+
        lda #$04
:       ora #>(VRAM+$1800)
        clc
        adc r_map+1
        sta r_map+1
        lda IORAM+$43           ; SCX
        lsr
        lsr
        lsr
        sta r_mx
        lda IORAM+$43
        and #7
        bne :+
        jsr draw_cols
        jmp @win
:       jsr draw_cols_fine
@win:   lda r_wcol
        cmp #20
        bcs @sprites
        sta r_col
        lda #20
        sta r_end
        lda r_winln
        tax
        and #7
        asl
        sta r_fine
        txa
        and #$F8
        ldx #0
        stx r_map+1
        asl
        rol r_map+1
        asl
        rol r_map+1
        sta r_map
        lda IORAM+$40
        and #$40
        beq :+
        lda #$04
:       ora #>(VRAM+$1800)
        clc
        adc r_map+1
        sta r_map+1
        lda #0
        sta r_mx
        jsr draw_cols
        inc r_winln

@sprites:
        lda IORAM+$40
        and #2
        bne :+
        rts
:       jmp draw_sprites

; Draw screen columns r_col..r_end-1 from map row r_map starting at r_mx.
draw_cols:
        lda r_col               ; r_dst = r_line + r_col * 16
        asl
        asl
        asl
        asl
        php
        clc
        adc r_line
        sta r_dst
        lda r_line+1
        adc #0
        plp
        adc #0
        sta r_dst+1
dc_col: ldy r_mx
        lda (r_map),y
        tax
        lda tlo,x
        ora r_fine
        sta r_tp
col_thi:
        lda thi_u,x
        sta r_tp+1
        ldy #0
        lda (r_tp),y
        sta r_lo
        iny
        lda (r_tp),y
        sta r_hi
        and #$F0                ; left 4 pixels
        ldx r_lo
        ora shr4,x
        tax
        lda conv,x
        ldy #0
        sta (r_dst),y
        ldx r_hi                ; right 4 pixels
        lda shl4,x
        sta r_t
        lda r_lo
        and #$0F
        ora r_t
        tax
        lda conv,x
        ldy #8
        sta (r_dst),y
        clc
        lda r_dst
        adc #16
        sta r_dst
        bcc :+
        inc r_dst+1
:       lda r_mx
        clc
        adc #1
        and #31
        sta r_mx
        inc r_col
        lda r_col
        cmp r_end
        bne dc_col
        rts

; Background with fine horizontal scroll (SCX & 7 != 0): draw one extra tile
; into a scratch line with the same layout as the bitmap (byte i at offset 8*i),
; then copy it into the bitmap shifted left by SCX & 7 pixels.
draw_cols_fine:
        lda r_line
        pha
        lda r_line+1
        pha
        lda #<finebuf
        sta r_line
        lda #>finebuf
        sta r_line+1
        lda r_end
        pha
        inc r_end               ; one tile more for the pixels shifted in
        jsr draw_cols
        pla
        sta r_end
        pla
        sta r_line+1
        sta r_dst+1
        pla
        sta r_line
        sta r_dst
        lda IORAM+$43           ; whole bytes to skip: (SCX & 4) / 4
        and #4
        asl
        adc #<finebuf
        sta r_tp
        lda #>finebuf
        adc #0
        sta r_tp+1
        lda IORAM+$43           ; bit shift: 2 * (SCX & 3)
        and #3
        asl
        sta r_px
        lda r_end
        asl
        sta r_n                 ; bytes to produce: 2 per column
@b:     ldy #8
        lda (r_tp),y
        sta r_lo
        ldy #0
        lda (r_tp),y
        ldx r_px
        beq :++
:       asl r_lo
        rol
        dex
        bne :-
:       sta (r_dst),y
        clc
        lda r_tp
        adc #8
        sta r_tp
        bcc :+
        inc r_tp+1
:       clc
        lda r_dst
        adc #8
        sta r_dst
        bcc :+
        inc r_dst+1
:       dec r_n
        bne @b
        rts

; Draw the (max 10) sprites that cover line ly.
draw_sprites:
        lda IORAM+$40
        and #4
        beq :+
        lda #16
        bne :++
:       lda #8
:       sta r_end               ; sprite height
        lda #0
        sta r_n
        ldx #0
@scan:  lda ly
        clc
        adc #16
        sec
        sbc OAMPG,x             ; row = ly + 16 - y
        cmp r_end
        bcs @nx
        ldy r_n
        txa
        sta spr_list,y
        iny
        sty r_n
        cpy #10
        beq @draw
@nx:    txa
        clc
        adc #4
        tax
        cmp #160
        bne @scan
@draw:  ldy r_n
        bne :+
        rts
:       ; stable insertion sort by X: lower X (then lower OAM index) on top
        lda #1
        sta r_attr              ; i
@sort:  lda r_attr
        cmp r_n
        bcs @sorted
        tay
        lda spr_list,y
        sta r_q                 ; entry being inserted
        tax
        lda OAMPG+1,x
        sta r_t                 ; its X
@ins:   cpy #0
        beq @place
        ldx spr_list-1,y
        lda OAMPG+1,x
        cmp r_t
        beq @place
        bcc @place
        txa
        sta spr_list,y
        dey
        jmp @ins
@place: lda r_q
        sta spr_list,y
        inc r_attr
        jmp @sort
@sorted:
        ldy r_n                 ; draw back to front: list end first

@one:   dey
        bpl :+
        rts
:       sty r_n
        ldx spr_list,y
        lda OAMPG+3,x
        sta r_attr
        lda OAMPG+1,x
        sec
        sbc #8
        sta r_x
        lda ly                  ; row within the sprite
        clc
        adc #16
        sec
        sbc OAMPG,x
        bit r_attr
        bvc :+
        eor #$FF                ; Y flip: row = height - 1 - row
        clc
        adc r_end
:       asl
        sta r_fine              ; row * 2 (may run into the next tile for 8x16)
        lda OAMPG+2,x
        ldy r_end
        cpy #16
        bne :+
        and #$FE
:       tax
        lda tlo,x
        clc
        adc r_fine
        sta r_tp
        lda thi_u,x
        adc #0
        sta r_tp+1
        ldy #0
        lda (r_tp),y
        sta r_lo
        iny
        lda (r_tp),y
        sta r_hi
        lda r_attr              ; X flip
        and #$20
        beq :+
        ldx r_lo
        lda rev,x
        sta r_lo
        ldx r_hi
        lda rev,x
        sta r_hi
:       lda r_attr
        and #$10
        beq :+
        lda IORAM+$49
        bne :++
:       lda IORAM+$48
:       sta r_pal
        lda #8
        sta r_px
@pix:   lda #0                  ; color = hi bit 7 << 1 | lo bit 7
        asl r_lo
        rol
        asl r_hi
        bcc :+
        ora #2
:       tay
        beq @skip               ; color 0 is transparent
        lda r_x
        cmp #160
        bcs @skip
        lda r_pal               ; shade = (pal >> 2*color) & 3
:       lsr
        lsr
        dey
        bne :-
        sta r_t
        jsr put_pixel
@skip:  inc r_x
        dec r_px
        bne @pix
        ldy r_n
        jmp @one

; Plot a sprite pixel: r_x = x, r_t bits 0-1 = shade,
; r_attr bit 7 = behind background colors 1-3.
put_pixel:
        ldx r_x
        lda xoff_lo,x
        clc
        adc r_line
        sta r_tp
        lda xoff_hi,x
        adc r_line+1
        sta r_tp+1
        txa
        and #3
        tax                     ; X = pixel within byte (0 = leftmost)
        ldy #0
        lda r_attr
        bpl @draw
        lda (r_tp),y            ; behind BG: only over BG color 0
        and pmask,x
        sta r_q
        lda r_bg0
        jsr shift_shade
        cmp r_q
        bne @r
@draw:  lda r_t
        and #3
        jsr shift_shade
        sta r_q
        lda (r_tp),y
        and pmask_inv,x
        ora r_q
        sta (r_tp),y
@r:     rts

; A = shade (0-3), X = pixel position in byte -> shade moved into place.
shift_shade:
        cpx #3
        beq @r
        asl
        asl
        cpx #2
        beq @r
        asl
        asl
        cpx #1
        beq @r
        asl
        asl
@r:     rts

pmask:     .byte $C0, $30, $0C, $03
pmask_inv: .byte $3F, $CF, $F3, $FC
