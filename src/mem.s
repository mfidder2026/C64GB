; ---------------------------------------------------------------------------
; GB memory access through the RMAP/WMAP page tables, ROM page cache
; ---------------------------------------------------------------------------

; A = byte at GB address ml/mh. Clobbers X, Y.
rd:
        ldx mh
        lda RMAP,x
        beq rd_slow
        sta mp+1
        ldy ml
        lda (mp),y
        rts

rd_hl:
        lda rL
        sta ml
        ldx rH
        stx mh
        ; fall through, X = page

rd_slow:
        cpx #$80
        bcs @hi
        jsr rom_miss
        sta mp+1
        ldy ml
        lda (mp),y
        rts
@hi:    cpx #$FF
        bne @ff
        ldx ml
        bpl @io
        lda IORAM,x
        rts
@io:    jmp io_read_x
@ff:    lda #$FF                ; disabled cartridge RAM etc.
        rts

; Write A to GB address ml/mh. Clobbers X, Y.
wr:
        ldx mh
        ldy WMAP,x
        beq wr_slow
        sty mp+1
        ldy ml
        sta (mp),y
        rts

; Write A to (HL). Clobbers X, Y.
wr_hl:
        ldx rH
        ldy WMAP,x
        beq @slow
        sty mp+1
        ldy rL
        sta (mp),y
        rts
@slow:  ldy rL
        sty ml
        stx mh
        ; fall through, X = page

wr_slow:
        cpx #$80
        bcs @hi
        jmp mbc_write
@hi:    cpx #$FF
        bne @ign
        ldx ml
        bpl @io
        cpx #$FF
        beq @io
        sta IORAM,x
@ign:   rts
@io:    jmp io_write_x

; ---------------------------------------------------------------------------
; ROM page cache
;
; Each slot holds one 256-byte page of the ROM, tagged with its REU page
; number (key). The ROM lives at REU address 0, so key = bank*64 + page%64.
; ---------------------------------------------------------------------------

; Resolve ROM page X ($00-$7F): returns A = C64 page, RMAP updated.
; Clobbers X, Y. Never evicts the slot holding the current PC page.
rom_miss:
        stx miss_pg
        cpx #$40
        bcs @hi
        lda bank_lo
        ldy bank_lo+1
        jmp @key
@hi:    lda bank_hi
        ldy bank_hi+1
@key:   sta tmp_b
        lsr
        lsr
        sta key_hi
        tya
        ror                     ; bit 0 -> C
        lda #0
        ror                     ; C -> bit 7
        lsr                     ; -> bit 6
        ora key_hi
        sta key_hi
        lda tmp_b
        ror
        ror
        ror                     ; bits 1:0 -> 7:6 (C was clear? masked below)
        and #$C0
        sta key_lo
        lda miss_pg
        and #$3F
        ora key_lo
        sta key_lo

        ldy #NSLOTS-1
@srch:  lda slot_klo,y
        cmp key_lo
        bne @nx
        lda slot_khi,y
        cmp key_hi
        beq @found
@nx:    dey
        bpl @srch

        jsr evict               ; Y = free slot
        sty miss_slot
        lda key_lo
        sta slot_klo,y
        lda key_hi
        sta slot_khi,y
        lda slot_page,y
        jsr backend_load_page   ; load REU page key -> C64 page A
        ldy miss_slot

@found: ldx miss_pg
        txa
        sta slot_gb,y
        lda slot_page,y
        sta RMAP,x
        rts

; Pick the next slot to replace and unmap its previous owner. Returns Y.
evict:
        ldy clock
@again: iny
        cpy #NSLOTS
        bcc :+
        ldy #0
:       lda slot_page,y
        cmp pcb+1
        beq @again
        sty clock
        ldx slot_gb,y
        bmi @done               ; $FF = not mapped
        cmp RMAP,x
        bne :+
        lda #0
        sta RMAP,x
:       txa
        eor #$40                ; same key could be mapped in the other region
        tax
        lda slot_page,y
        cmp RMAP,x
        bne @done
        lda #0
        sta RMAP,x
@done:  lda #$FF
        sta slot_gb,y
        sta slot_khi,y          ; invalid until reloaded
        rts

; The bank at $4000-$7FFF changed.
bank_hi_changed:
        lda #0
        ldx #$3F
:       sta RMAP+$40,x
        dex
        bpl :-
        lda pc_page
        and #$C0
        cmp #$40
        bne :+
        jmp pc_resolve
:       rts

; The bank at $0000-$3FFF changed (MBC1 mode 1).
bank_lo_changed:
        lda #0
        ldx #$3F
:       sta RMAP,x
        dex
        bpl :-
        lda pc_page
        cmp #$40
        bcs :+
        jmp pc_resolve
:       rts

; Map or unmap cartridge RAM at $A000-$BFFF according to ram_en/has_sram.
sram_map:
        lda ram_en
        and has_sram
        beq @off
        lda mbc_type
        cmp #3
        bne @on
        lda ram_bank            ; MBC3: RTC register selected?
        cmp #8
        bcc @on
        lda #>FFPG              ; RTC not emulated: reads $FF, writes ignored
        ldx #31
:       sta RMAP+$A0,x
        dex
        bpl :-
        lda #0
        ldx #31
:       sta WMAP+$A0,x
        dex
        bpl :-
        rts
@on:    ldx #31
        lda #>(SRAM+$1F00)
:       sta RMAP+$A0,x
        sta WMAP+$A0,x
        sec
        sbc #1
        dex
        bpl :-
        rts
@off:   lda #0
        ldx #31
:       sta RMAP+$A0,x
        sta WMAP+$A0,x
        dex
        bpl :-
        rts

; ---------------------------------------------------------------------------
; MBC register writes: A = value, X = GB page ($00-$7F)
; ---------------------------------------------------------------------------

mbc_write:
        sta mtmp
        ldy mbc_type
        bne :+
        rts
:       cpy #1
        beq mbc1
        cpy #2
        beq mbc2
        cpy #3
        bne :+
        jmp mbc3
:       jmp mbc5

mbc_ram_enable:
        lda mtmp
        and #$0F
        cmp #$0A
        beq :+
        lda #0
:       sta ram_en
        jmp sram_map

mbc1:
        cpx #$20
        bcc mbc_ram_enable
        cpx #$40
        bcs @upper
        lda mtmp                ; $2000-$3FFF: low 5 bank bits
        and #$1F
        sta mbc_lo
        jmp mbc1_update
@upper: cpx #$60
        bcs @mode
        lda mtmp                ; $4000-$5FFF: upper 2 bits / RAM bank
        and #3
        sta mbc1_hi
        jmp mbc1_update
@mode:  lda mtmp
        and #1
        sta mbc1_mode
        ; fall through

mbc1_update:
        ; bank_hi = (hi << 5) | (lo ? lo : 1)
        lda mbc_lo
        bne :+
        lda #1
:       sta etmp
        lda mbc1_hi
        asl
        asl
        asl
        asl
        asl
        ora etmp
        ldx #0
        jsr set_bank_hi
        ; mode 1: $0000 bank = hi << 5, RAM bank = hi
        lda mbc1_mode
        beq @m0
        lda mbc1_hi
        jsr set_ram_bank
        lda mbc1_hi
        asl
        asl
        asl
        asl
        asl
        jmp set_bank_lo
@m0:    lda #0
        jsr set_ram_bank
        lda #0
        jmp set_bank_lo

mbc2:
        cpx #$40
        bcs @r
        txa
        and #1                  ; address bit 8 selects ROM bank register
        beq mbc_ram_enable
        lda mtmp
        and #$0F
        bne :+
        lda #1
:       ldx #0
        jmp set_bank_hi
@r:     rts

mbc3:
        cpx #$20
        bcs :+
        jmp mbc_ram_enable
:
        cpx #$40
        bcs @upper
        lda mtmp
        and #$7F
        bne :+
        lda #1
:       ldx #0
        jmp set_bank_hi
@upper: cpx #$60
        bcs @r                  ; $6000-$7FFF: RTC latch, ignored
        lda mtmp
        jsr set_ram_bank
        jmp sram_map
@r:     rts

mbc5:
        cpx #$20
        bcs :+
        jmp mbc_ram_enable
:
        cpx #$30
        bcs @b8
        lda mtmp                ; $2000-$2FFF: low 8 bits
        sta mbc_lo
        ldx mbc1_hi
        jmp set_bank_hi
@b8:    cpx #$40
        bcs @ram
        lda mtmp                ; $3000-$3FFF: bit 8
        and #1
        sta mbc1_hi
        tax
        lda mbc_lo
        jmp set_bank_hi
@ram:   cpx #$60
        bcs @r
        lda mtmp
        and #$0F
        jmp set_ram_bank
@r:     rts

; Select ROM bank X:A for $4000-$7FFF (masked to the ROM size).
set_bank_hi:
        and bank_msk
        sta etmp
        txa
        and bank_msk+1
        sta etmp2
        lda etmp
        cmp bank_hi
        bne @chg
        lda etmp2
        cmp bank_hi+1
        beq @r
@chg:   lda etmp
        sta bank_hi
        lda etmp2
        sta bank_hi+1
        jmp bank_hi_changed
@r:     rts

; Select ROM bank A (< 256) for $0000-$3FFF.
set_bank_lo:
        and bank_msk
        cmp bank_lo
        beq @r
        sta bank_lo
        jmp bank_lo_changed
@r:     rts

; Select cartridge RAM bank A. sram_cur tracks which bank is in C64 memory.
set_ram_bank:
        sta ram_bank
        cmp #8
        bcs @r                  ; MBC3 RTC register: no memory swap
        cmp sram_cur
        beq @r
        tax
        lda sram_cur
        stx sram_cur
        jmp backend_ram_bank    ; A = old bank, X = new bank
@r:     rts
