; ---------------------------------------------------------------------------
; GB memory access through the RMAP/WMAP page tables, page cache
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
        cpx #$FF
        beq @ff
        jsr map_page            ; ROM / cartridge RAM cache miss
        beq @none
        sta mp+1
        ldy ml
        lda (mp),y
        rts
@ff:    ldx ml
        bpl @io
        lda IORAM,x
        rts
@io:    jmp io_read_x
@none:  lda #$FF                ; disabled cartridge RAM etc.
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
        beq @ff
.ifdef SRAM_CACHED
        cpx #$A0
        bcc @ign
        cpx #$C0
        bcs @ign
        pha
        jsr sram_miss           ; map the cartridge RAM page, then write
        tay
        pla
        cpy #0
        beq @ign
        sty mp+1
        ldy ml
        sta (mp),y
.endif
@ign:   rts
@ff:    ldx ml
        bpl @io
        cpx #$FF
        beq @io
        sta IORAM,x
        rts
@io:    jmp io_write_x

; C64 page for GB page X when RMAP has none: loads ROM / cartridge RAM pages
; into the cache. Returns A = page (Z=1: unmapped). Clobbers X, Y.
map_page:
        cpx #$80
        bcs :+
        jmp rom_miss
:       cpx #$FF
        bne :+
        lda #>IORAM
        rts
:
.ifdef SRAM_CACHED
        cpx #$A0
        bcc @none
        cpx #$C0
        bcs @none
        jmp sram_miss
.endif
@none:  lda #0
        rts

; ---------------------------------------------------------------------------
; Page cache
;
; Each slot holds one 256-byte page from the REU, tagged with its REU page
; number (key). ROM pages: key = bank*64 + page%64. Cartridge RAM pages live
; at REU $FE0000 (key_hi >= $FE) and are written back when evicted.
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
        ror                     ; bits 1:0 -> 7:6
        and #$C0
        sta key_lo
        lda miss_pg
        and #$3F
        ora key_lo
        sta key_lo
        jsr cache_get
        ldx miss_pg
        sta RMAP,x
        ora #0                  ; Z=0
        rts

.ifdef SRAM_CACHED
; Resolve cartridge RAM page X ($A0-$BF). Returns A = C64 page (0 when the
; RAM is disabled), RMAP and WMAP updated.
sram_miss:
        lda ram_en
        and has_sram
        beq @off
        lda ram_bank
        cmp #8
        bcs @off                ; MBC3 RTC register
        stx miss_pg
        lsr                     ; key = $FE00 + bank*32 + page%32
        lsr
        lsr
        clc
        adc #REU_SRAM
        sta key_hi
        lda ram_bank
        asl
        asl
        asl
        asl
        asl
        sta key_lo
        txa
        and #$1F
        ora key_lo
        sta key_lo
        jsr cache_get
        ldx miss_pg
        sta RMAP,x
        sta WMAP,x
        ora #0
        rts
@off:   lda #0
        rts
.endif

; Find or load the page key_hi:key_lo. Returns A = C64 page, Y = slot, and
; records miss_pg as the slot's GB page.
cache_get:
        ldy nslots
        dey
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
@found: lda miss_pg
        sta slot_gb,y
        lda slot_page,y
        rts

; Pick the next slot to replace, write it back if it holds cartridge RAM and
; unmap its previous owner. Returns Y.
evict:
        ldy clock
@again: iny
        cpy nslots
        bcc :+
        ldy #0
:       lda slot_page,y
        cmp pcpg
        beq @again
        sty clock
        ldx slot_khi,y
        cpx #REU_SRAM
        bcc :+
        cpx #$FF
        beq :+
        sty etmp2               ; dirty-capable page: store it back
        ldx slot_klo,y
        stx key_save
        ldx slot_khi,y
        stx key_save+1
        lda slot_page,y
        jsr backend_store_page  ; C64 page A -> REU page key_save
        ldy etmp2
:       ldx slot_gb,y
        cpx #$FF
        beq @done               ; not mapped
        lda slot_page,y
        cmp RMAP,x
        bne :+
        lda #0
        sta RMAP,x
        cpx #$80
        bcc :+
        sta WMAP,x              ; cartridge RAM page
        bcs @done
:       txa
        eor #$40                ; same ROM key could be mapped in the other region
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

; Cartridge RAM enable / bank / RTC selection changed: reset its mapping.
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
@on:
.ifdef SRAM_RES
        ldx #31                 ; sim65: one resident bank
        lda #>(SRAM_RES+$1F00)
:       sta RMAP+$A0,x
        sta WMAP+$A0,x
        sec
        sbc #1
        dex
        bpl :-
        rts
.endif
@off:   lda #0                  ; cached: pages are mapped on first access
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
        beq :++
:       sta sav_dirty           ; the game may write its save data now
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

; Select cartridge RAM bank A (cached pages are tagged per bank).
set_ram_bank:
        cmp ram_bank
        beq @r
        sta ram_bank
        jmp sram_map
@r:     rts
