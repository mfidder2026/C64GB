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
hexbuf: .res 2
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
backend_wram_bank:              ; GBC WRAM banks are not swapped in sim65
backend_wram_clear:
        rts

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
