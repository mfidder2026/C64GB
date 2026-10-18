; ---------------------------------------------------------------------------
; Emulator initialisation (target independent)
; ---------------------------------------------------------------------------

; Clear the emulator's zero page ($02-$EF).
.import __ZPCODE_LOAD__, __ZPCODE_RUN__, __ZPCODE_SIZE__
zp_clear:
        lda #0
        ldx #$02
:       sta $00,x
        inx
        cpx #$F0
        bne :-
        rts

; Fill A into pages ptr+1 .. ptr+1+X-1.
fill_pages:
        ldy #0
        sty ptr
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        dex
        bne :-
        rts

; $0149 RAM size codes: none, 2 KB, 8 KB, 32 KB, 128 KB, 64 KB (in pages)
ramsize_lo: .byte 0, 8, 32, 128, 0, 0
ramsize_hi: .byte 0, 0, 0, 0, 2, 1
batt_types: .byte $03, $06, $09, $0D, $0F, $10, $13, $1B, $1E, $22, $FF
batt_types_end:

.segment "BSS"
sram_pages: .res 2              ; cartridge RAM size in 256-byte pages
sav_dirty:  .res 1              ; cartridge RAM was enabled since the last save
has_batt:   .res 1              ; cartridge RAM is battery backed
.segment "CODE"

; Set up memory maps, read the cartridge header and reset the GB state.
gb_init:
        ldx #<(__ZPCODE_SIZE__-1)   ; install the zero page dispatcher
:       lda __ZPCODE_LOAD__,x
        sta __ZPCODE_RUN__,x
        dex
        bpl :-
        lda #0
        sta pcl
        lda #0
        tax
:       sta RMAP,x
        sta WMAP,x
        inx
        bne :-

        lda #>VRAM              ; VRAM, WRAM and SRAM ($4000-$9FFF)
        sta ptr+1
        lda #0
        ldx #$60
        jsr fill_pages
        lda #>IORAM
        sta ptr+1
        lda #0
        ldx #2                  ; IORAM + OAMPG
        jsr fill_pages
        lda #>FFPG
        sta ptr+1
        lda #$FF
        ldx #1
        jsr fill_pages

        ; cache slots available in every mode
        ldy #0
        lda #>SLOTS0
:       sta slot_page,y
        clc
        adc #1
        iny
        cpy #NSLOTS0
        bne :-
.if NSLOTS1 > 0
        lda #>SLOTS1
:       sta slot_page,y
        clc
        adc #1
        iny
        cpy #NSLOTS_A
        bne :-
.endif
        sty nslots
        ldy #MAXSLOTS-1
        lda #$FF
:       sta slot_khi,y
        sta slot_gb,y
        dey
        bpl :-

        ; fixed mappings
        ldx #31
:       txa
        clc
        adc #>VRAM
        sta RMAP+$80,x
        sta WMAP+$80,x
        txa
        clc
        adc #>WRAM
        sta RMAP+$C0,x
        sta WMAP+$C0,x
        cpx #30
        bcs :+
        sta RMAP+$E0,x          ; echo RAM $E000-$FDFF
        sta WMAP+$E0,x
:       dex
        bpl :--
        lda #>OAMPG
        sta RMAP+$FE
        sta WMAP+$FE

        ; cartridge
        lda #1
        sta bank_hi
        lda #$FF
        sta bank_msk
        lda #$01
        sta bank_msk+1
        sta mh
        lda #$47                ; cartridge type
        sta ml
        jsr rd
        ldx #batt_types_end-batt_types-1
:       cmp batt_types,x        ; battery-backed RAM: save games
        beq :+
        dex
        bpl :-
:       inx                     ; X = 0: no battery
        stx has_batt
        ldx #0
        cmp #$0F                ; MBC3 + timer (+ battery / RAM)
        beq :+
        cmp #$10
        bne :++
:       inx
:       stx has_rtc
        ldx #0
        cmp #$01
        bcc @mbc
        ldx #1
        cmp #$04
        bcc @mbc
        ldx #2
        cmp #$07
        bcc @mbc
        ldx #0
        cmp #$0F
        bcc @mbc
        ldx #3
        cmp #$14
        bcc @mbc
        ldx #0
        cmp #$19
        bcc @mbc
        ldx #5
        cmp #$1F
        bcc @mbc
        ldx #0
@mbc:   stx mbc_type

        inc ml                  ; $0148: ROM size -> bank mask
        jsr rd
        and #$0F
        tax
        lda #1
        sta bank_msk
        lda #0
        sta bank_msk+1
        cpx #0
        beq @msk
:       sec
        rol bank_msk
        rol bank_msk+1
        dex
        bne :-
@msk:
        inc ml                  ; $0149: RAM size
        jsr rd
        cmp #6
        bcc :+
        lda #0
:       tay
        lda ramsize_lo,y        ; size in 256-byte pages (for save files)
        sta sram_pages
        lda ramsize_hi,y
        sta sram_pages+1
        tya
        ldx mbc_type
        cpx #2
        bne :+
        lda #2                  ; MBC2: 512 x 4 bits built in
        sta sram_pages
        lda #1
:       cmp #0
        beq :+
        lda #1
:       sta has_sram
        lda #1
        and bank_msk
        sta bank_hi

        lda #$43                ; $0143 bit 7: Game Boy Color ROM
        sta ml
        jsr rd
        and #$80
        beq @dmg
        lda #1
        sta cgb
        jsr cgb_init
        jmp @regs
@dmg:   ldy nslots              ; DMG: $8000-$9FFF becomes more cache slots
        lda #>VRAM1
:       sta slot_page,y
        clc
        adc #1
        iny
        cmp #>(VRAM1+$2000)
        bne :-
        sty nslots
@regs:

        ; CPU registers as left by the DMG boot ROM
        lda #$01
        sta rA
        lda #0
        sta zv                  ; Z=1
        sta fn
        lda #$20
        sta fh
        lda #1
        sta fc
        lda #$13
        sta rC
        lda #$D8
        sta rE
        lda #$01
        sta rH
        lda #$4D
        sta rL
        lda #$FE
        sta sp_lo
        lda #$FF
        sta sp_hi

        ; I/O registers
        lda #$30
        sta IORAM+$00
        lda #$F8
        sta IORAM+$07
        lda #$E1
        sta IORAM+$0F
        lda #$91
        sta IORAM+$40
        lda #$85
        sta IORAM+$41
        lda #$77                ; sound on, as left by the boot ROM
        sta IORAM+$24
        lda #$F3
        sta IORAM+$25
        lda #$F1
        sta IORAM+$26
        lda #$FC
        sta IORAM+$47
        lda #$FF
        sta IORAM+$48
        sta IORAM+$49
        lda #$C0
        sta divc
        lda #$2A
        sta divc+1

        lda cgb                 ; GBC boot ROM leaves A=$11 (games test this)
        beq :+
        lda #$11
        sta rA
        lda #0
        sta fh
        sta fc
        sta rC
        lda #$FF
        sta rD
        lda #$56
        sta rE
        lda #0
        sta rH
        lda #$0D
        sta rL
:
.ifdef SRAM_RES
        lda #>SRAM_RES
        sta ptr+1
        lda #0
        ldx #32
        jsr fill_pages
.endif
        lda #2
        sta ppu_mode
        lda #20
        sta ppu_left

        lda #$01
        sta pc_page
        jsr pc_resolve
        jmp schedule
