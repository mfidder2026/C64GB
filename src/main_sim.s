; ---------------------------------------------------------------------------
; sim65 target: headless test build.
; Loads "rom.gb" from the current directory, prints the GB serial port to
; stdout and exits when the ROM ends in "jr -2" (Blargg test convention).
; ---------------------------------------------------------------------------

.include "config.inc"
.include "zp.inc"
.include "macros.inc"

.ifndef SIM_FRAMES
SIM_FRAMES = 0
.endif

PV_LSEEK = $FFF1
PV_OPEN  = $FFF4
PV_READ  = $FFF6
PV_WRITE = $FFF7
PV_EXIT  = $FFF9

.import __MAIN_START__

.segment "EXEHDR"
        .byte "sim65", 2, 0, csp
        .word __MAIN_START__, start

.segment "CODE"

start:
        cld
        ldx #$FF
        txs
        jsr zp_clear
        lda #<CSTACK
        sta csp
        lda #>CSTACK
        sta csp+1

        lda #<romname           ; open("rom.gb", O_RDONLY)
        ldx #>romname
        jsr pushax
        lda #1
        ldx #0
        jsr pushax
        ldy #4
        jsr PV_OPEN
        sta fd_rom
        stx fd_rom+1
        cpx #$FF
        bne :+
        lda #<msg_noopen
        ldx #>msg_noopen
        jsr puts
        lda #4
        jmp PV_EXIT
:
.ifdef RENDER
        jsr render_init
.endif
        jsr gb_init
        jmp loop

romname:    .byte "rom.gb", 0
msg_noopen: .byte "cannot open rom.gb", 10, 0
msg_ill:    .byte 10, "illegal opcode at ", 0
msg_done:   .byte 10, "[cycles $", 0
msg_end:    .byte "]", 10, 0

; Push A (lo) / X (hi) on the cc65 parameter stack.
pushax:
        pha
        lda csp
        sec
        sbc #2
        sta csp
        bcs :+
        dec csp+1
:       ldy #1
        txa
        sta (csp),y
        dey
        pla
        sta (csp),y
        rts

; write(1, A/X, Y)
write_out:
        sty etmp
        pha
        txa
        pha
        lda #1
        ldx #0
        jsr pushax
        pla
        tax
        pla
        jsr pushax
        lda etmp
        ldx #0
        jmp PV_WRITE

; Print the zero-terminated string at A/X.
puts:
        sta ptr2
        stx ptr2+1
        ldy #0
:       lda (ptr2),y
        beq :+
        iny
        bne :-
:       lda ptr2
        ldx ptr2+1
        jmp write_out

; Print A as two hex digits.
puthex:
        pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexdig,x
        sta hexbuf
        pla
        and #$0F
        tax
        lda hexdig,x
        sta hexbuf+1
        lda #<hexbuf
        ldx #>hexbuf
        ldy #2
        jmp write_out
hexdig: .byte "0123456789ABCDEF"

.segment "BSS"
hexbuf: .res 3
.segment "CODE"

; ---- backend ---------------------------------------------------------------

; Load REU page key_hi:key_lo (= ROM offset key*256) into C64 page A.
backend_load_page:
        sta tmp_b
        lda fd_rom              ; lseek(fd, key_lo << 8, SEEK_SET)
        ldx fd_rom+1
        jsr pushax
        lda #0
        tax
        jsr pushax
        lda #0
        ldx key_lo
        jsr pushax
        lda #2
        ldx #0
        jsr PV_LSEEK
        lda key_hi              ; + key_hi * 64K (sim65 only seeks 16 bits)
        asl
        beq @read
        sta etmp2
:       lda fd_rom
        ldx fd_rom+1
        jsr pushax
        lda #0
        tax
        jsr pushax
        lda #0
        ldx #$80
        jsr pushax
        lda #0                  ; SEEK_CUR
        tax
        jsr PV_LSEEK
        dec etmp2
        bne :-
@read:  lda fd_rom              ; read(fd, page, 256)
        ldx fd_rom+1
        jsr pushax
        lda #0
        ldx tmp_b
        jsr pushax
        lda #0
        ldx #1
        jmp PV_READ

backend_store_page:             ; no cached cartridge RAM in sim65
        rts

; GBC WRAM banks live in the host file "wram.bin" (bank * 4 KB).
fd_ram  = $56                   ; 2 bytes
wram_new = $55

; Create wram.bin with 32 KB of zeros (VRAM bank 1, still clear, is the source).
backend_wram_clear:
        lda #<wramname          ; open("wram.bin", O_RDWR | O_CREAT | O_TRUNC)
        ldx #>wramname
        jsr pushax
        lda #$33
        ldx #0
        jsr pushax
        ldy #4
        jsr PV_OPEN
        sta fd_ram
        stx fd_ram+1
        lda #4
        sta wram_new
:       lda fd_ram
        ldx fd_ram+1
        jsr pushax
        lda #<VRAM1
        ldx #>VRAM1
        jsr pushax
        lda #0
        ldx #$20
        jsr PV_WRITE
        dec wram_new
        bne :-
        rts
wramname: .byte "wram.bin", 0

; Swap the WRAM bank at $7000: A = old bank, X = new bank.
backend_wram_bank:
        stx wram_new
        jsr @seek
        lda fd_ram              ; write(fd, $7000, $1000)
        ldx fd_ram+1
        jsr pushax
        lda #<(WRAM+$1000)
        ldx #>(WRAM+$1000)
        jsr pushax
        lda #0
        ldx #$10
        jsr PV_WRITE
        lda wram_new
        jsr @seek
        lda fd_ram              ; read(fd, $7000, $1000)
        ldx fd_ram+1
        jsr pushax
        lda #<(WRAM+$1000)
        ldx #>(WRAM+$1000)
        jsr pushax
        lda #0
        ldx #$10
        jmp PV_READ
@seek:  asl                     ; lseek(fd, bank << 12, SEEK_SET)
        asl
        asl
        asl
        pha
        lda fd_ram
        ldx fd_ram+1
        jsr pushax
        lda #0
        tax
        jsr pushax
        pla
        tax
        lda #0
        jsr pushax
        lda #2
        ldx #0
        jmp PV_LSEEK

serial_out:
        lda #<(IORAM+1)
        ldx #>(IORAM+1)
        ldy #1
        jmp write_out

sound_status:
        lda IORAM+$26
        rts
palette_write:
        sta IORAM+$47
sound_write:
.ifndef RENDER
hblank_hook:
.endif
        rts

vblank_hook:
        inc frames
        bne :+
        inc frames+1
:
.ifdef AUTOKEYS
        lda #0
        sta joy_btns
        sta joy_dirs
        ldx #0
@ak:    lda autokey_tab+1,x
        cmp #$FF
        beq @akd
        lda frames
        sec
        sbc autokey_tab,x
        sta etmp
        lda frames+1
        sbc autokey_tab+1,x
        bne @aks
        lda etmp
        cmp #6
        bcs @aks
        lda joy_btns
        ora autokey_tab+2,x
        sta joy_btns
        lda joy_dirs
        ora autokey_tab+3,x
        sta joy_dirs
@aks:   txa
        clc
        adc #4
        tax
        bne @ak
@akd:
.endif
.ifdef PROFILE                  ; trace (clock + PC) during frames PROFILE..PROFILE+PROF_N-1
        lda frames
        cmp #<PROFILE
        bne :+
        lda #$30
        sta $FFCB
:       lda frames
        cmp #<(PROFILE+PROF_N)
        bne :+
        lda #0
        sta $FFCB
        jmp sim_done
:
.endif
.if SIM_FRAMES > 0
        lda frames
        cmp #<SIM_FRAMES
        bne :+
        lda frames+1
        cmp #>SIM_FRAMES
        bne :+
        jmp sim_done
:
.endif
        rts

; Test finished: print the GB cycle count and exit.
sim_done:
.ifdef DUMP
        jsr dump
.endif
.ifdef FRAMEDUMP
        jsr framedump
.endif
        lda #<msg_done
        ldx #>msg_done
        jsr puts
        lda mclk+2
        jsr puthex
        lda mclk+1
        jsr puthex
        lda mclk
        jsr puthex
        lda #<msg_end
        ldx #>msg_end
        jsr puts
        lda #0
        jmp PV_EXIT

.ifdef FRAMEDUMP
; Write bitmap, screen matrix, color RAM and $D021 color to "frame.bin".
framedump:
        lda #<fdname
        ldx #>fdname
        jsr pushax
        lda #$32                ; O_WRONLY | O_CREAT | O_TRUNC
        ldx #0
        jsr pushax
        ldy #4
        jsr PV_OPEN
        sta ptr2
        stx ptr2+1
        lda #<BITMAP
        ldx #>BITMAP
        ldy #>8000
        jsr @w
        lda #<SCREEN
        ldx #>SCREEN
        ldy #4
        jsr @w
        lda #<COLRAM
        ldx #>COLRAM
        ldy #4
        jsr @w
        lda gbg0
        sta hexbuf
        lda #<hexbuf
        ldx #>hexbuf
        ldy #0
@w:     sta ptr                 ; write(fd, A/X, Y * 256 (or 1 when Y = 0))
        stx ptr+1
        sty etmp2
        lda ptr2
        ldx ptr2+1
        jsr pushax
        lda ptr
        ldx ptr+1
        jsr pushax
        lda #0
        ldx etmp2
        bne :+
        lda #1
:       jmp PV_WRITE
fdname: .byte "frame.bin", 0
.endif
.ifdef AUTOKEYS
autokey_tab:
        .include "autokeys.inc"
        .word $FFFF
.endif
.ifdef TRACEIO
; Print "frame ly mode reg=val" for writes to LCDC/SCY/SCX/LYC/WY/WX.
trace_io:
        pha
        cpx #$40
        beq :+
        cpx #$42
        beq :+
        cpx #$43
        beq :+
        cpx #$45
        beq :+
        cpx #$4A
        beq :+
        cpx #$4B
        bne @r
:       lda frames
        cmp #<TRACEIO
        bne @r
        txa
        pha
        tsx
        lda $0102,x             ; value
        sta etmp2
        pla
        pha
        sta hexbuf+2            ; (reg kept on the stack)
        lda ly
        jsr puthex
        lda #'/'
        jsr putch
        lda ppu_mode
        jsr puthex
        lda #' '
        jsr putch
        pla
        pha
        jsr puthex
        lda #'='
        jsr putch
        lda etmp2
        jsr puthex
        lda #10
        jsr putch
        pla
        tax
@r:     pla
        rts
putch:  sta hexbuf
        lda #<hexbuf
        ldx #>hexbuf
        ldy #1
        jmp write_out
.endif
.ifdef TRACE
trace_lcdc:                     ; prints "ly:value " (value on stack above return)
        lda ly
        jsr puthex
        lda #':'
        sta hexbuf
        lda #<hexbuf
        ldx #>hexbuf
        ldy #1
        jsr write_out
        tsx
        lda $0103,x
        jsr puthex
        lda #' '
        sta hexbuf
        lda #<hexbuf
        ldx #>hexbuf
        ldy #1
        jmp write_out
.endif

.ifdef DUMP
dump:
.ifdef DUMPBMP
        lda #<(BITMAP+(66/8+3)*320)     ; cell row of line 66
        ldx #>(BITMAP+(66/8+3)*320)
        ldy #255
        jsr hexdump
        lda #<OAMPG
        ldx #>OAMPG
        ldy #160
        jmp hexdump
.endif
                                ; palram, pal_c64, pal_scr/col, screen + color row 10
        lda #<palram
        ldx #>palram
        ldy #128
        jsr hexdump
        lda #<pal_c64
        ldx #>pal_c64
        ldy #80
        jsr hexdump
        lda #<(SCREEN+13*40)
        ldx #>(SCREEN+13*40)
        ldy #40
        jsr hexdump
        lda #<(COLRAM+13*40)
        ldx #>(COLRAM+13*40)
        ldy #40
        jsr hexdump
        lda #<(cellattr)
        ldx #>(cellattr)
        ldy #40
hexdump:
        sta ptr2
        stx ptr2+1
        sty etmp2
        ldy #0
:       sty frames
        lda (ptr2),y
        jsr puthex
        ldy frames
        iny
        cpy etmp2
        bne :-
        lda #10
        sta hexbuf
        lda #<hexbuf
        ldx #>hexbuf
        ldy #1
        jmp write_out
.endif

sim_illegal:
        lda #<msg_ill
        ldx #>msg_ill
        jsr puts
        lda pc_page
        jsr puthex
        lda pcl
        jsr puthex
        lda #3
        jmp PV_EXIT

.include "cpu.s"
.include "mem.s"
.include "io.s"
.include "init.s"
.include "cgb.s"
.ifdef RENDER
.include "render.s"
.endif
.include "tables.s"
