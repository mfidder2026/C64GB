; ---------------------------------------------------------------------------
; Game Boy Color hardware: VRAM/WRAM banks, HDMA, palette registers, speed
; ---------------------------------------------------------------------------

cgb_init:
        lda #1
        sta svbk
        sta pal_dirty
        lda #0
        sta vbk
        sta dspeed
        lda #$FF
        sta hdma_len
        ldx #127                ; palettes start white ($7FFF)
:       sta palram,x
        dex
        bpl :-
        jmp backend_wram_clear

; Reads of $FF4D-$FF7F in GBC mode. X = register, returns A.
cgb_io_read:
        cpx #$4D
        bne :+
        lda dspeed              ; KEY1: bit 7 current speed, bit 0 armed
        lsr
        ror
        ora IORAM+$4D
        ora #$7E
        rts
:       cpx #$4F
        bne :+
        lda vbk
        ora #$FE
        rts
:       cpx #$55
        bne :+
        lda hdma_len            ; $FF = idle, else blocks left - 1
        rts
:       cpx #$69
        bne :+
        lda IORAM+$68
        and #$3F
        tax
        lda palram,x
        rts
:       cpx #$6B
        bne :+
        lda IORAM+$6A
        and #$3F
        tax
        lda palram+64,x
        rts
:       cpx #$70
        bne :+
        lda svbk
        ora #$F8
        rts
:       lda IORAM,x
        rts

; Writes of $FF4D-$FF7F in GBC mode. X = register, A = value.
cgb_io_write:
        cpx #$4D
        bne :+
        and #1
        sta IORAM+$4D
        rts
:       cpx #$4F
        bne :+
        and #1
        sta vbk
        jmp vram_map
:       cpx #$51
        bcc @store
        cpx #$55
        bcs :+
        jmp @hdma_reg
:       bne :+
        jmp hdma_start
:       cpx #$68
        bcc @store
        cpx #$6C
        bcs @svbk
        sta IORAM,x             ; BCPS / OCPS: just store
        cpx #$69
        beq @bcpd
        cpx #$6B
        beq @ocpd
        rts
@bcpd:  ldy #$68
        bne @pd
@ocpd:  ldy #$6A
@pd:    pha
        lda IORAM,y             ; palette index
        and #$3F
        cpy #$6A
        bne :+
        ora #$40                ; OBJ palettes follow the BG palettes
:       tax
        pla
        sta palram,x
        lda #1
        sta pal_dirty
        lda IORAM,y
        bpl @r
        clc                     ; auto increment, index wraps within 0-63
        adc #1
        and #$BF
        sta IORAM,y
@r:     rts
@svbk:  cpx #$70
        bne @store
        and #7
        bne :+
        lda #1
:       cmp svbk
        beq @r
        tax
        lda svbk
        stx svbk
        jmp backend_wram_bank   ; A = old, X = new
@store: sta IORAM,x
        rts
@hdma_reg:
        cpx #$51
        bne :+
        sta hdma_src+1
        rts
:       cpx #$52
        bne :+
        and #$F0
        sta hdma_src
        rts
:       cpx #$53
        bne :+
        and #$1F
        ora #$80
        sta hdma_dst+1
        rts
:       and #$F0
        sta hdma_dst
        rts

; Map GB $8000-$9FFF to the selected VRAM bank.
vram_map:
        lda #>VRAM
        ldx vbk
        beq :+
        lda #>VRAM1
:       ldx #0
:       sta RMAP+$80,x
        sta WMAP+$80,x
        clc
        adc #1
        inx
        cpx #32
        bne :-
        rts

; HDMA5 write: A bit 7 = 0 general DMA (now), 1 = one block per HBlank.
hdma_start:
        tax
        bmi @hblank
        lda hdma_len
        cmp #$FF
        beq :+
        lda #$FF                ; writing bit 7 = 0 during HBlank DMA cancels it
        sta hdma_len
        rts
:       txa
        and #$7F
        sta etmp2
:       jsr hdma_block
        dec etmp2
        bpl :-
        lda #$FF
        sta hdma_len
        rts
@hblank:
        txa
        and #$7F
        sta hdma_len
        rts

; Called at the start of every HBlank.
hdma_hblank:
        lda hdma_len
        cmp #$FF
        beq :+
        jsr hdma_block
        dec hdma_len            ; $00 -> $FF = finished
:       rts

; Copy 16 bytes from hdma_src to VRAM (current bank) at hdma_dst.
hdma_block:
        ldx hdma_src+1
        lda RMAP,x
        bne :+
        jsr map_page
        bne :+
        lda #>FFPG
:       sta hptr+1
        lda hdma_src
        sta hptr
        ldx hdma_dst+1
        lda WMAP,x
        sta hptr2+1
        lda hdma_dst
        sta hptr2
        ldy #15
:       lda (hptr),y
        sta (hptr2),y
        dey
        bpl :-
        clc
        lda hdma_src
        adc #16
        sta hdma_src
        bcc :+
        inc hdma_src+1
:       clc
        lda hdma_dst
        adc #16
        sta hdma_dst
        bcc :+
        lda hdma_dst+1
        adc #0
        and #$1F
        ora #$80
        sta hdma_dst+1
:       rts

; STOP with KEY1 bit 0 set switches CPU speed.
cgb_stop:
        lda cgb
        beq @r
        lda IORAM+$4D
        and #1
        beq @r
        lda #0
        sta IORAM+$4D
        lda dspeed
        eor #1
        sta dspeed
@r:     rts
