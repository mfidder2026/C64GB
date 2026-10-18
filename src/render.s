; ---------------------------------------------------------------------------
; Scanline renderer: GB line -> C64 multicolor bitmap (160x200, 2bpp)
;
; Each GB tile row (8 pixels, 2 bitplanes) becomes 2 bitmap bytes of 4
; double-wide pixels. GB line y lives in bitmap cell row (y/8)+3, so the
; 144 GB lines are centred in the 200 bitmap lines.
;
; DMG: bit pair = shade: 0 white ($D021), 1 light grey (screen hi nibble),
;      2 dark grey (screen lo nibble), 3 black (color RAM).
; GBC: bit pair = color index within the tile's palette. Colors 1-3 of the
;      palette go into the cell's screen/color RAM, color 0 is the global
;      background ($D021 = BG palette 0 color 0). Colors are per 4x8 cell, so
;      tiles of different palettes within one cell row share the colors of the
;      cell's first line ("attribute clash").
;
; The tables live in RAM under the I/O area; the renderer runs with I/O off.
; ---------------------------------------------------------------------------

conv     = RTAB+$000    ; (hi nibble << 4 | lo nibble) -> 4 packed pixels
shr4     = RTAB+$100
shl4     = RTAB+$200    ; also (tile << 4) & $F0
rev      = RTAB+$300    ; bit reversal (X flip)
thi_u    = RTAB+$400    ; tile data page, $8000 addressing
thi_s    = RTAB+$500    ; tile data page, $8800 (signed) addressing
line_lo  = RTAB+$600    ; 144
line_hi  = RTAB+$690    ; 144
xoff_lo  = RTAB+$720    ; 160
xoff_hi  = RTAB+$7C0    ; 160
finebuf  = RTAB+$860    ; 21*16
spr_list = RTAB+$9B0    ; 10
shade4   = RTAB+$9BC    ; 4
dist16   = RTAB+$9C0    ; 16x16 C64 color distances
cellattr = RTAB+$AC0    ; 40: BG attributes of the current cell row (GBC)
lattr    = RTAB+$AE8    ; 21: BG attributes of the current line, per column
palprev  = RTAB+$B40    ; 128: palette RAM at the last conversion
                        ; end: RTAB+$BC0

VRAM1OFS = >VRAM1 - >VRAM

; One-time set-up code goes into the start-up overlay on the C64
.ifdef TARGET_C64
.define INITSEG "BROWSER"
.else
.define INITSEG "CODE"
.endif

; Per cell sprite color wishes, in the bottom of the stack page (the
; emulator uses far less than the remaining 96 bytes of stack)
wantn    = $0100        ; 40: number of sprite colors wanted
want0    = $0128        ; 40 each: the wanted C64 colors
want1    = $0150
want2    = $0178

.ifdef TARGET_C64
convp     = $3800       ; GBC: conv table per BG palette (over the browser's load image)
.endif
.segment "BSS"
.ifndef TARGET_C64
convp:    .res 8*256    ; GBC: conv table per BG palette (color -> bit pair)
.endif
palmap:   .res 8        ; GBC: color -> bit pair mapping byte per BG palette
palmapc:  .res 8        ; mapping the conv table was built for
colbuf:   .res 40       ; color RAM bytes (read while I/O is on)
.segment "CODE"

.macro IO_OFF
.ifdef TARGET_C64
        lda #$34
        sta $01
.endif
.endmacro

.macro IO_ON
.ifdef TARGET_C64
        lda #$35
        sta $01
.endif
.endmacro

; Rebuild conv[] for the 2-bit-per-color palette in A (BGP format).
build_conv:
        sta bgp_cache
        ldx #<conv
        stx r_pc
        ldx #>conv
        stx r_pc+1
; Same into the table at r_pc.
build_conv_to:
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
        txa
        tay
        lda r_t
        sta (r_pc),y
        inx
        bne @e
        rts

; Render GB line `ly` (called at the start of hblank).
hblank_hook:
        lda r_on
        bne :+
        rts
:       IO_OFF
        jsr render_line
        IO_ON
        rts

render_line:
        lda cgb
        beq @dmgpal
        lda pal_dirty
        beq :+
        jsr cgb_palettes
:       lda #$E4                ; GBC: bit pair = color index
        cmp bgp_cache
        beq @pal
        jsr build_conv
        jmp @pal
@dmgpal:
        lda IORAM+$47
        cmp bgp_cache
        beq @pal
        jsr build_conv
@pal:   ldx ly
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
        sta cgb_thi+1
        stx cgb_thi+2

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
        lda cgb                 ; on GBC, LCDC bit 0 only affects priority
        bne @bg
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
        bcs @colors
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

@colors:
        lda cgb                 ; GBC: set the cell colors on a cell row's first line
        beq @sprites
        lda ly
        and #7
        bne @sprites
        jsr commit_colors
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
        lda r_end
        sec
        sbc r_col
        sta r_cnt
        lda cgb
        beq dc_col
        jmp draw_cols_cgb
dc_col: ldy r_mx
        lda (r_map),y
        tax
        lda shl4,x
        ora r_fine
        sta r_tp
col_thi:
        lda thi_u,x
        sta r_tp+1
        ldy #1
        lda (r_tp),y
        sta r_hi
        dey
        lda (r_tp),y
        sta r_lo
        tax                     ; left 4 pixels: hi nibble | lo nibble >> 4
        lda r_hi
        and #$F0
        ora shr4,x
        tax
        lda conv,x
        sta (r_dst),y
        lda r_lo                ; right 4 pixels: hi << 4 | lo & 15
        and #$0F
        ldx r_hi
        ora shl4,x
        tax
        lda conv,x
        ldy #8
        sta (r_dst),y
        lda r_dst
        clc
        adc #16
        sta r_dst
        bcc :+
        inc r_dst+1
:       ldy r_mx
        iny
        tya
        and #31
        sta r_mx
        dec r_cnt
        bne dc_col
        rts

; GBC columns: tile attributes from VRAM bank 1 (palette, bank, flips).
draw_cols_cgb:
        lda r_map+1
        clc
        adc #VRAM1OFS
        sta r_amap+1
        lda r_map
        sta r_amap
        lda r_fine
        eor #$0E
        sta r_finef             ; tile row offset for Y-flipped tiles
        lda #<convp
        sta r_pc
dcc_col:
        ldy r_mx
        lda (r_amap),y          ; attributes
        sta r_a
        ldx r_col
        sta lattr,x
        lda (r_map),y           ; tile
        tax
        lda shl4,x
        bit r_a
        bvs @yf
        ora r_fine
        bvc @yd
@yf:    ora r_finef
@yd:    sta r_tp
cgb_thi:
        lda thi_u,x
        sta r_tp+1
        lda r_a
        and #$08                ; tile data in VRAM bank 1
        beq :+
        lda r_tp+1
        clc
        adc #VRAM1OFS
        sta r_tp+1
:       ldy #1
        lda (r_tp),y
        sta r_hi
        dey
        lda (r_tp),y
        sta r_lo
        lda r_a
        and #$20
        bne @xf
@xd:    lda r_a                 ; conv table of the tile's palette
        and #7
        clc
        adc #>convp
        sta r_pc+1
        lda r_hi                ; left 4 pixels
        and #$F0
        ldx r_lo
        ora shr4,x
        tay
        lda (r_pc),y
        ldy #0
        sta (r_dst),y
        lda r_lo                ; right 4 pixels
        and #$0F
        ldx r_hi
        ora shl4,x
        tay
        lda (r_pc),y
        ldy #8
        sta (r_dst),y
        lda r_dst
        clc
        adc #16
        sta r_dst
        bcc :+
        inc r_dst+1
:       inc r_col
        ldy r_mx
        iny
        tya
        and #31
        sta r_mx
        dec r_cnt
        beq :+
        jmp dcc_col
:       rts
@xf:    ldx r_lo                ; X flip
        lda rev,x
        sta r_lo
        ldx r_hi
        lda rev,x
        sta r_hi
        jmp @xd

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

; GBC: choose and write the colors of the current cell row (screen RAM and
; color RAM). Each cell starts with the three colors of its BG palette; slots
; that the cell's BG pixels do not use are given to sprite colors.
commit_colors:
        ldy #39
@c:     tya                     ; base colors from the BG palette
        lsr
        tax
        lda lattr,x
        sta cellattr,y
        and #7
        tax
        lda pal_scr,x
        lsr
        lsr
        lsr
        lsr
        sta cs1,y
        lda pal_scr,x
        and #15
        sta cs2,y
        lda pal_col,x
        sta cs3,y
        lda #0
        sta wantn,y
        dey
        bpl @c
        lda IORAM+$40
        and #2
        beq @write
        jsr sprite_wants
        ldy #39
@w:     lda wantn,y
        beq :+
        jsr cell_fill
:       dey
        bpl @w

@write: lda ly                  ; r_tp = cell row * 40
        lsr
        lsr
        lsr
        clc
        adc #TOP_ROW
        sta r_t
        lda #0
        sta r_tp+1
        lda r_t
        asl
        asl
        asl                     ; row * 8 (row < 32)
        sta r_lo
        asl
        rol r_tp+1
        asl
        rol r_tp+1              ; row * 32
        clc
        adc r_lo
        sta r_tp
        bcc :+
        inc r_tp+1
:       clc                     ; screen matrix
        lda r_tp
        adc #<SCREEN
        sta r_dst
        lda r_tp+1
        adc #>SCREEN
        sta r_dst+1
        ldy #39
:       lda cs1,y
        asl
        asl
        asl
        asl
        ora cs2,y
        sta (r_dst),y
        lda cs3,y
        sta colbuf,y
        dey
        bpl :-
        clc                     ; color RAM (needs I/O)
        lda r_tp
        adc #<COLRAM
        sta r_dst
        lda r_tp+1
        adc #>COLRAM
        sta r_dst+1
        IO_ON
        ldy #39
:       lda colbuf,y
        sta (r_dst),y
        dey
        bpl :-
.ifdef TARGET_C64
        lda gbg0
        sta $D021
.endif
        IO_OFF
        rts

; Collect, per cell of this cell row, the colors that sprites will draw there.
sprite_wants:
        lda IORAM+$40
        and #4
        beq :+
        lda #16
        bne :++
:       lda #8
:       sta r_end               ; sprite height
        lda ly
        clc
        adc #17
        sta s_ly17
        ldx #0
@s:     lda ly                  ; sprite top (oy - 16) <= ly + 7 ?
        clc
        adc #23
        cmp OAMPG,x
        bcs :+
        jmp @nx
:       lda OAMPG,x             ; sprite bottom (oy - 16 + h - 1) >= ly ?
        clc
        adc r_end
        bcs :+
        cmp s_ly17
        bcs :+
        jmp @nx
:       lda OAMPG+1,x           ; on screen horizontally?
        bne :+
        jmp @nx
:       cmp #168
        bcc :+
        jmp @nx
:
        lda ly                  ; rows r0..r1 of the sprite inside the cell row
        clc
        adc #16
        sec
        sbc OAMPG,x
        bcs :+
        adc #7                  ; starts above: r0 = 0, r1 = d + 7
        sta s_r1
        lda #0
        sta s_r0
        beq :++
:       sta s_r0
        clc
        adc #7
        sta s_r1
:       lda r_end
        sec
        sbc #1
        cmp s_r1
        bcs :+
        sta s_r1
:       lda #0                  ; colors used by those rows
        sta s_um
        stx s_ox
@row:   lda s_r0
        ldx s_ox
        jsr spr_row
        lda r_hi
        eor #$FF
        and r_lo
        beq :+
        lda s_um
        ora #2
        sta s_um
:       lda r_lo
        eor #$FF
        and r_hi
        beq :+
        lda s_um
        ora #4
        sta s_um
:       lda r_lo
        and r_hi
        beq :+
        lda s_um
        ora #8
        sta s_um
:       lda s_r0
        cmp s_r1
        bcs :+
        inc s_r0
        jmp @row
:       ldx s_ox                ; cells covered: x-8 .. x-1
        lda OAMPG+1,x
        sec
        sbc #1
        cmp #160
        bcc :+
        lda #159
:       lsr
        lsr
        sta s_right
        lda OAMPG+1,x
        sec
        sbc #8
        bcs :+
        lda #0
:       lsr
        lsr
        sta s_left
        lda OAMPG+3,x           ; OBJ palette * 4 + 32
        and #7
        asl
        asl
        ora #32
        sta s_pal
        lda #1
        sta s_c
@col:   lda s_um                ; for each used color 1-3
        ldx s_c
        and bitmask,x
        beq @nc
        lda s_pal
        clc
        adc s_c
        tax
        lda pal_c64,x
        sta s_col
        ldy s_left
:       lda s_col
        jsr add_want
        cpy s_right
        iny
        bcc :-
@nc:    inc s_c
        lda s_c
        cmp #4
        bne @col
        ldx s_ox
@nx:    txa
        clc
        adc #4
        tax
        cmp #160
        beq :+
        jmp @s
:       rts

bitmask: .byte 1, 2, 4, 8

; Add color A to cell Y's wish list (max 3, no duplicates). Preserves Y.
add_want:
        sta s_t
        ldx wantn,y
        beq @add
        cmp want0,y
        beq @r
        cpx #1
        beq @add
        cmp want1,y
        beq @r
        cpx #2
        beq @add
        cmp want2,y
        beq @r
        rts
@add:   txa
        beq @w0
        cpx #1
        beq @w1
        lda s_t
        sta want2,y
        jmp @inc
@w0:    lda s_t
        sta want0,y
        jmp @inc
@w1:    lda s_t
        sta want1,y
@inc:   lda wantn,y
        clc
        adc #1
        sta wantn,y
@r:     rts

; Give cell Y's free color slots to the colors on its wish list. Preserves Y.
cell_fill:
        sty s_cell
        lda wantn,y             ; quick check: all wanted colors already in the cell?
        sta s_n
        ldx #0
@q:     lda want0,y
        cpx #0
        beq :+
        lda want1,y
        cpx #1
        beq :+
        lda want2,y
:       cmp gbg0
        beq @qok
        cmp cs1,y
        beq @qok
        cmp cs2,y
        beq @qok
        cmp cs3,y
        bne @full
@qok:   inx
        cpx s_n
        bne @q
        rts
@full:  jsr bg_used             ; s_u = bit pairs used by BG pixels (bits 1-3)
        lda #0
        sta s_j
@j:     ldx s_j
        cpx s_n
        bcs @r
        lda want0,y
        cpx #0
        beq :+
        lda want1,y
        cpx #1
        beq :+
        lda want2,y
:       sta s_col
        cmp gbg0
        beq @nx
        lda s_u                 ; already shown by a used slot?
        and #2
        beq :+
        lda cs1,y
        cmp s_col
        beq @nx
:       lda s_u
        and #4
        beq :+
        lda cs2,y
        cmp s_col
        beq @nx
:       lda s_u
        and #8
        beq :+
        lda cs3,y
        cmp s_col
        beq @nx
:       lda s_u                 ; take a free slot
        and #2
        bne :+
        lda s_col
        sta cs1,y
        lda #2
        bne @take
:       lda s_u
        and #4
        bne :+
        lda s_col
        sta cs2,y
        lda #4
        bne @take
:       lda s_u
        and #8
        bne @r                  ; no free slot left
        lda s_col
        sta cs3,y
        lda #8
@take:  ora s_u
        sta s_u
@nx:    inc s_j
        jmp @j
@r:     ldy s_cell
        rts

; s_u = bit pairs (bits 1-3) used by the BG pixels of cell s_cell over the
; 8 lines of this cell row (window cells: all three).
bg_used:
        lda s_cell
        lsr
        sta s_tc                ; tile column
        cmp r_wcol
        bcc :+
        lda #$0E
        sta s_u
        rts
:       lda #0
        sta s_m
        sta s_r
@r:     lda ly
        clc
        adc s_r
        cmp #144
        bcc :+
        jmp @done
:       clc
        adc IORAM+$42           ; SCY
        sta s_by
        and #$F8                ; map row pointer
        ldx #0
        stx s_mp+1
        asl
        rol s_mp+1
        asl
        rol s_mp+1
        sta s_mp
        lda IORAM+$40
        and #$08
        beq :+
        lda #$04
:       ora #>(VRAM+$1800)
        clc
        adc s_mp+1
        sta s_mp+1
        lda IORAM+$43
        lsr
        lsr
        lsr
        clc
        adc s_tc
        and #31
        tay
        lda (s_mp),y            ; tile
        tax
        lda s_mp+1
        clc
        adc #VRAM1OFS
        sta s_mp+1
        lda (s_mp),y            ; attributes
        sta s_aa
        lda s_by                ; tile row (Y flip)
        and #7
        bit s_aa
        bvc :+
        eor #7
:       asl
        ora shl4,x
        sta r_tp
        lda IORAM+$40
        and #$10
        beq :+
        lda thi_u,x
        bne :++
:       lda thi_s,x
:       sta r_tp+1
        lda s_aa
        and #$08
        beq :+
        lda r_tp+1
        clc
        adc #VRAM1OFS
        sta r_tp+1
:       ldy #0
        lda (r_tp),y
        sta r_lo
        iny
        lda (r_tp),y
        sta r_hi
        lda s_cell              ; which nibble: left cell = high, X flip swaps
        and #1
        sta r_t
        lda s_aa
        and #$20
        beq :+
        lda r_t
        eor #1
        sta r_t
:       lda r_t
        bne :+
        ldx r_lo
        lda shr4,x
        sta r_lo
        ldx r_hi
        lda shr4,x
        sta r_hi
        jmp :++
:       lda r_lo
        and #15
        sta r_lo
        lda r_hi
        and #15
        sta r_hi
:       lda r_lo                ; colors present in the 4 pixels
        ora r_hi
        eor #15
        beq :+
        lda s_m
        ora #1
        sta s_m
:       lda r_hi
        eor #15
        and r_lo
        beq :+
        lda s_m
        ora #2
        sta s_m
:       lda r_lo
        eor #15
        and r_hi
        beq :+
        lda s_m
        ora #4
        sta s_m
:       lda r_lo
        and r_hi
        beq :+
        lda s_m
        ora #8
        sta s_m
:       inc s_r
        lda s_r
        cmp #8
        beq @done
        jmp @r
@done:  ldy s_cell              ; GB colors -> bit pairs of the cell's palette
        lda cellattr,y
        and #7
        tax
        lda palmap,x
        sta s_pm
        lda #0
        sta s_u
        ldx #0
@b:     lsr s_m
        bcc :+
        lda s_pm
        and #3
        tay
        lda s_u
        ora bitmask,y
        sta s_u
:       lsr s_pm
        lsr s_pm
        inx
        cpx #4
        bne @b
        lda s_u
        and #$0E
        sta s_u
        ldy s_cell
        rts

; Sprite row bytes: X = OAM offset, A = row within the sprite (before Y flip),
; r_end = sprite height. Returns r_lo/r_hi (no X flip). Preserves X.
spr_row:
        sta r_fine
        lda OAMPG+3,x
        and #$40
        beq :+
        lda r_fine              ; Y flip: row = height - 1 - row
        eor #$FF
        clc
        adc r_end
        sta r_fine
:       asl r_fine              ; row * 2 (may run into the next tile for 8x16)
        lda OAMPG+2,x
        ldy r_end
        cpy #16
        bne :+
        and #$FE
:       tay
        lda shl4,y
        clc
        adc r_fine
        sta r_tp
        lda thi_u,y
        adc #0
        sta r_tp+1
        lda cgb
        beq :+
        lda OAMPG+3,x           ; GBC: bit 3 = tile data in VRAM bank 1
        and #$08
        beq :+
        lda r_tp+1
        clc
        adc #VRAM1OFS
        sta r_tp+1
:       ldy #0
        lda (r_tp),y
        sta r_lo
        iny
        lda (r_tp),y
        sta r_hi
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
:       lda cgb                 ; GBC: priority by OAM order only
        bne @sorted
        ; DMG: stable insertion sort by X: lower X (then lower OAM index) on top
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
        jsr spr_row
        lda r_attr              ; X flip
        and #$20
        beq :+
        ldx r_lo
        lda rev,x
        sta r_lo
        ldx r_hi
        lda rev,x
        sta r_hi
:       lda cgb
        beq @dmgpal
        lda r_attr              ; GBC: dist16 rows of the 3 sprite colors
        and #7
        asl
        asl
        ora #32
        tay
        ldx #1
:       lda pal_c64+1,y
        asl
        asl
        asl
        asl
        sta trow,x
        iny
        inx
        cpx #4
        bne :-
        jmp @clip
@dmgpal:
        lda r_attr              ; DMG: shades of colors 1-3 from OBP0/1
        sta r_prio
        and #$10
        beq :+
        lda IORAM+$49
        bne :++
:       lda IORAM+$48
:       lsr
        lsr
        tay
        and #3
        sta spal+1
        tya
        lsr
        lsr
        tay
        and #3
        sta spal+2
        tya
        lsr
        lsr
        sta spal+3

@clip:  lda #8                  ; clip to the screen
        sta r_px
        lda r_x
        cmp #160
        bcc @right
        cmp #$F9
        bcs :+
        jmp @done               ; off screen
:       lda #0                  ; partly off the left edge: skip -x pixels
        sec
        sbc r_x
        tay
:       asl r_lo
        asl r_hi
        dec r_px
        dey
        bne :-
        lda #0
        sta r_x
@right: lda #160
        sec
        sbc r_x
        cmp r_px
        bcs :+
        sta r_px
:       ldx r_x                 ; bitmap byte of the first pixel
        lda xoff_lo,x
        clc
        adc r_line
        sta r_tp
        lda xoff_hi,x
        adc r_line+1
        sta r_tp+1
        txa
        lsr
        lsr
        sta r_cellx
        txa
        and #3
        tax                     ; X = pixel position within the byte
        lda cgb
        beq @pix
        jsr cell_map

@pix:   lda #0                  ; color = hi bit 7 << 1 | lo bit 7
        asl r_lo
        rol
        asl r_hi
        bcc :+
        ora #2
:       tay
        beq @next               ; color 0 is transparent
        lda spal,y              ; bit pair to draw
        bpl :+
        jsr map_color           ; GBC: not computed yet for this cell
:       bit r_prio
        bpl @put
        sta r_q                 ; behind BG: only over BG color 0
        ldy #0
        lda (r_tp),y
        and pmask,x
        sta s_t
        lda r_bg0
        ora posoff,x
        tay
        lda shtab,y
        cmp s_t
        bne @next
        lda r_q
@put:   ora posoff,x
        tay
        lda shtab,y
        sta r_q
        ldy #0
        lda (r_tp),y
        and pmask_inv,x
        ora r_q
        sta (r_tp),y
@next:  dec r_px
        beq @done
        inx
        cpx #4
        bne @pix
        ldx #0                  ; next bitmap byte (= next 4x8 cell)
        lda r_tp
        clc
        adc #8
        sta r_tp
        bcc :+
        inc r_tp+1
:       lda cgb
        beq @pix
        inc r_cellx
        jsr cell_map
        jmp @pix
@done:  ldy r_n
        jmp @one

; GBC: bit pairs for sprite colors 1-3 in cell r_cellx (nearest of the cell's
; four colors), plus the cell's priority and BG color 0 bit pair. Preserves X.
cell_map:
        stx s_ox
        ldx r_cellx
        lda cellattr,x
        sta r_prio
        and #7
        tay
        lda palmap,y
        and #3
        sta r_bg0
        lda IORAM+$40           ; LCDC bit 0 clear: sprites always on top
        and #1
        bne :+
        sta r_prio
        beq :++
:       lda r_attr
        ora r_prio
        sta r_prio
:       lda #$FF                ; sprite colors are mapped on first use
        sta spal+1
        sta spal+2
        sta spal+3
        ldx s_ox
        rts

; GBC: Y = sprite color (1-3) -> A = nearest of cell r_cellx's four colors,
; stored in spal. Preserves X.
map_color:
        sty s_c
        stx s_ox
        ldx r_cellx
        lda trow,y
        sta s_j
        ora gbg0
        tay
        lda dist16,y
        sta s_t
        lda #0
        sta s_col
        lda cs1,x
        ora s_j
        tay
        lda dist16,y
        cmp s_t
        bcs :+
        sta s_t
        lda #1
        sta s_col
:       lda cs2,x
        ora s_j
        tay
        lda dist16,y
        cmp s_t
        bcs :+
        sta s_t
        lda #2
        sta s_col
:       lda cs3,x
        ora s_j
        tay
        lda dist16,y
        cmp s_t
        bcs :+
        lda #3
        sta s_col
:       ldy s_c
        lda s_col
        sta spal,y
        ldx s_ox
        rts

pmask:     .byte $C0, $30, $0C, $03
pmask_inv: .byte $3F, $CF, $F3, $FC
posoff:    .byte 0, 4, 8, 12
shtab:     .byte $00, $40, $80, $C0     ; bit pair << (6 - 2 * position)
           .byte $00, $10, $20, $30
           .byte $00, $04, $08, $0C
           .byte $00, $01, $02, $03

; ---------------------------------------------------------------------------
; GBC colors -> C64 colors
; ---------------------------------------------------------------------------

; n_d = 2*dr^2 + 4*dg^2 + 3*db^2 between n_r/n_g/n_b and C64 color X.
color_dist:
        lda n_r
        sec
        sbc c64rgb,x
        bcs :+
        eor #$FF
        adc #1
:       tay
        lda sqtab_lo,y
        asl
        sta n_d
        lda sqtab_hi,y
        rol
        sta n_d+1
        lda n_g
        sec
        sbc c64rgb+16,x
        bcs :+
        eor #$FF
        adc #1
:       tay
        lda sqtab_lo,y
        sta n_t
        lda sqtab_hi,y
        asl n_t
        rol
        asl n_t
        rol
        sta n_t+1
        clc
        lda n_d
        adc n_t
        sta n_d
        lda n_d+1
        adc n_t+1
        sta n_d+1
        lda n_b
        sec
        sbc c64rgb+32,x
        bcs :+
        eor #$FF
        adc #1
:       tay
        lda sqtab_lo,y
        sta n_t
        lda sqtab_hi,y
        sta n_t+1
        asl n_t                 ; 2*db^2 ...
        rol n_t+1
        clc
        lda sqtab_lo,y          ; ... + db^2
        adc n_t
        sta n_t
        lda sqtab_hi,y
        adc n_t+1
        sta n_t+1
        clc
        lda n_d
        adc n_t
        sta n_d
        lda n_d+1
        adc n_t+1
        sta n_d+1
        rts

; Convert changed palette entries to C64 colors and rebuild the derived
; tables (screen/color RAM bytes per BG palette, sprite color mapping).
cgb_palettes:
        lda #0
        sta pal_dirty
        ldx #0                  ; X = palram offset (2 bytes per color)
@e:     lda palram,x
        cmp palprev,x
        bne @conv
        lda palram+1,x
        cmp palprev+1,x
        beq @nx
@conv:  lda palram,x
        sta palprev,x
        and #$1F
        sta n_r
        lda palram+1,x
        sta palprev+1,x
        lsr
        lsr
        and #$1F
        sta n_b
        lda palram+1,x          ; g = bits 5-9
        and #3
        sta n_g
        lda palram,x
        lsr
        lsr
        lsr
        lsr
        lsr
        asl n_g
        asl n_g
        asl n_g
        ora n_g
        sta n_g
        stx n_i
        jsr nearest
        lda n_i
        lsr
        tax
        lda n_bc
        sta pal_c64,x
        ldx n_i
@nx:    inx
        inx
        bpl @e

        lda pal_c64             ; global background = BG palette 0, color 0
        sta gbg0
        jsr assign_palettes

        rts

; n_bc = C64 color nearest to n_r/n_g/n_b.
nearest:
        lda #$FF
        sta n_bd
        sta n_bd+1
        ldx #15
@c:     jsr color_dist
        lda n_d+1
        cmp n_bd+1
        bcc @better
        bne @nx
        lda n_d
        cmp n_bd
        bcs @nx
@better:
        lda n_d
        sta n_bd
        lda n_d+1
        sta n_bd+1
        stx n_bc
@nx:    dex
        bpl @c
        rts

; For each BG palette, give every distinct color its own bit pair: colors equal
; to the global background use 0, the others get the cell's three colors. A
; fourth distinct color is merged into the nearest of those.
assign_palettes:
        ldx #7
@p:     stx n_i
        lda #0
        sta n_b                 ; slots used
        sta n_bc                ; mapping byte
        sta n_t                 ; slot colors 1-3 (n_t, n_t+1, n_g)
        sta n_t+1
        sta n_g
        txa
        asl
        asl
        sta n_r                 ; palette * 4
        lda #3
        sta n_d                 ; color index i (3..0, built from the top)
@i:     lda n_r
        clc
        adc n_d
        tay
        lda pal_c64,y
        sta n_d+1               ; color
        ldx #0                  ; bit pair
        cmp gbg0
        bne :+
        jmp @set
:       inx
        cmp n_t
        bne :+
        ldy n_b
        bne @set
:       inx
        cmp n_t+1
        bne :+
        ldy n_b
        cpy #2
        bcs @set
:       inx
        cmp n_g
        bne :+
        ldy n_b
        cpy #3
        bcs @set
:       ldx n_b                 ; new color: next free slot
        cpx #3
        bcs @merge
        inx
        stx n_b
        lda n_d+1
        cpx #1
        bne :+
        sta n_t
        jmp @set
:       cpx #2
        bne :+
        sta n_t+1
        jmp @set
:       sta n_g
        jmp @set
@merge: lda n_d+1               ; all slots taken: nearest of bg / slots
        asl
        asl
        asl
        asl
        sta n_bd+1
        ora gbg0
        tay
        lda dist16,y
        sta n_bd
        ldx #0
        lda n_t
        ora n_bd+1
        tay
        lda dist16,y
        cmp n_bd
        bcs :+
        sta n_bd
        ldx #1
:       lda n_t+1
        ora n_bd+1
        tay
        lda dist16,y
        cmp n_bd
        bcs :+
        sta n_bd
        ldx #2
:       lda n_g
        ora n_bd+1
        tay
        lda dist16,y
        cmp n_bd
        bcs @set
        ldx #3
@set:   txa                     ; mapping = mapping << 2 | bit pair
        asl n_bc
        asl n_bc
        ora n_bc
        sta n_bc
        dec n_d
        bmi :+
        jmp @i
:       ldx n_i
        lda n_t
        asl
        asl
        asl
        asl
        ora n_t+1
        sta pal_scr,x
        lda n_g
        sta pal_col,x
        lda n_bc
        sta palmap,x
        cmp palmapc,x           ; rebuild the conv table if the mapping changed
        beq :+
        sta palmapc,x
        pha
        lda #<convp
        sta r_pc
        txa
        clc
        adc #>convp
        sta r_pc+1
        pla
        jsr build_conv_to
:       ldx n_i
        dex
        bmi :+
        jmp @p
:       rts

; ---- one-time set-up (runs from the start-up overlay on the C64) ----------
.segment INITSEG
; Build the static lookup tables.
render_init:
        IO_OFF
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

        jsr color_init
        IO_ON
        lda #1
        sta r_on
        lda IORAM+$47
        eor #$FF
        sta bgp_cache           ; force a conversion table build
        rts

; C64 palette (Colodore), 5 bits per component
c64pal_r: .byte  0,31,16,14,17,10, 5,29,17,10,24, 9,15,21,14,22
c64pal_g: .byte  0,31, 6,25, 7,21, 5,30,10, 7,13, 9,15,31,13,22
c64pal_b: .byte  0,31, 7,25,18, 9,19,14, 5, 0,14, 9,15,19,29,22

color_init:
        ldx #15
:       lda c64pal_r,x
        sta c64rgb,x
        lda c64pal_g,x
        sta c64rgb+16,x
        lda c64pal_b,x
        sta c64rgb+32,x
        dex
        bpl :-
        lda #0                  ; squares 0..31: (n+1)^2 = n^2 + 2n + 1
        sta n_d
        sta n_d+1
        ldx #0
@sq:    lda n_d
        sta sqtab_lo,x
        lda n_d+1
        sta sqtab_hi,x
        txa
        asl
        sec
        adc n_d
        sta n_d
        bcc :+
        inc n_d+1
:       inx
        cpx #32
        bne @sq
        ; dist16[a*16+b] = distance >> 6
        lda #0
        sta n_i
@a:     lda n_i
        lsr
        lsr
        lsr
        lsr
        tax
        lda c64rgb,x
        sta n_r
        lda c64rgb+16,x
        sta n_g
        lda c64rgb+32,x
        sta n_b
        lda n_i
        and #15
        tax
        jsr color_dist
        lda n_d+1               ; >> 6
        sta n_t
        lda n_d
        asl
        rol n_t
        asl
        rol n_t
        ldx n_i
        lda n_t
        sta dist16,x
        inc n_i
        bne @a
        ldx #127                ; force a full palette conversion
        lda #0
:       sta palprev,x
        dex
        bpl :-
        ldx #7                  ; GBC conv tables start as identity mappings
@cv:    stx n_i
        lda #<convp
        sta r_pc
        txa
        clc
        adc #>convp
        sta r_pc+1
        lda #$E4
        sta palmapc,x
        sta palmap,x
        jsr build_conv_to
        ldx n_i
        dex
        bpl @cv
        rts

.segment "CODE"
