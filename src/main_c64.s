; ---------------------------------------------------------------------------
; C64 (Ultimate) target
;
; Expects the Game Boy ROM at REU address 0 (loaded by the UCI loader or as
; a REU image). Runs with BASIC/KERNAL banked out ($01 = $35), interrupts off.
; ---------------------------------------------------------------------------

.include "config.inc"
.include "zp.inc"
.include "macros.inc"

REU_CMD    = $DF01
REU_C64LO  = $DF02
REU_C64HI  = $DF03
REU_LO     = $DF04
REU_MID    = $DF05
REU_BANK   = $DF06
REU_LENLO  = $DF07
REU_LENHI  = $DF08
REU_ADDRCTL = $DF0A


FRAMESKIP  = 1              ; render every (FRAMESKIP+1)th frame

.segment "LOADADDR"
        .word $0801
.segment "EXEHDR"
        .word @next, 10         ; 10 SYS2061
        .byte $9E, "2061", 0
@next:  .word 0

.segment "CODE"

start:
        sei
        cld
        ldx #$FF
        txs
        lda #$35                ; RAM at $A000/$E000, I/O on
        sta $01
        lda #$7F                ; no CIA interrupts
        sta $DC0D
        sta $DD0D
        lda $DC0D
        lda $DD0D
        lda #<nmi
        sta $FFFA
        lda #>nmi
        sta $FFFB
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF

        lda $D031               ; Ultimate turbo: max speed, no badline stalls
        cmp #$FF
        beq :+
        lda #$8F
        sta $D031
:
        jsr zp_clear
        jsr browser             ; choose a ROM and load it into the REU
        jsr zp_clear
        jsr video_init
        jsr render_init
        jsr gb_init
        lda has_sram
        beq :+
        jsr sram_clear
:       jmp loop

irq:    rti

; RESTORE: back to the ROM browser.
nmi:    ldx #$FF
        txs
        jmp start

; ---- video ----------------------------------------------------------------

video_init:
        lda #0
        sta $D011               ; blank while setting up
        lda $DD02               ; VIC bank 3 ($C000-$FFFF)
        ora #3
        sta $DD02
        lda $DD00
        and #$FC
        sta $DD00
        lda #$48                ; screen $D000, bitmap $E000
        sta $D018
        lda #$18                ; multicolor, 40 columns
        sta $D016
        lda #0
        sta $D020
        lda #1                  ; shade 0: white
        sta $D021

        ; bitmap: margins black (%11), GB area white (%00)
        lda #>BITMAP
        sta ptr+1
        lda #$FF
        ldx #$1F
        jsr fill_pages
        ldy #$3F
:       sta BITMAP+$1F00,y
        dey
        bpl :-
        lda #<(BITMAP+TOP_ROW*320)
        sta ptr
        lda #>(BITMAP+TOP_ROW*320)
        sta ptr+1
        ldx #18                 ; 18 cell rows * 320 bytes
@row:   ldy #0
        lda #0
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        ldy #63
:       sta (ptr),y
        dey
        bpl :-
        lda ptr
        clc
        adc #64
        sta ptr
        bcc :+
        inc ptr+1
:       dex
        bne @row

        lda #$34                ; screen matrix lives under I/O
        sta $01
        lda #>SCREEN
        sta ptr+1
        lda #$FB                ; %01 light grey, %10 dark grey
        ldx #4
        jsr fill_pages
        lda #$35
        sta $01
        lda #$D8                ; color RAM: %11 black
        sta ptr+1
        lda #0
        ldx #4
        jsr fill_pages

        lda #$3B                ; bitmap mode, display on
        sta $D011
        rts

; ---- REU backend -------------------------------------------------------------

; Load REU page key_hi:key_lo into C64 page A.
backend_load_page:
        sta REU_C64HI
        lda #0
        sta REU_C64LO
        sta REU_LO
        sta REU_LENLO
        sta REU_ADDRCTL
        lda key_lo
        sta REU_MID
        lda key_hi
        sta REU_BANK
        lda #1
        sta REU_LENHI
        lda #$91                ; REU -> C64, execute now
        sta REU_CMD
        rts

; Store C64 page A to REU page key_save (cartridge RAM write-back).
backend_store_page:
        sta REU_C64HI
        lda #0
        sta REU_C64LO
        sta REU_LO
        sta REU_LENLO
        sta REU_ADDRCTL
        lda key_save
        sta REU_MID
        lda key_save+1
        sta REU_BANK
        lda #1
        sta REU_LENHI
        lda #$90                ; C64 -> REU, execute now
        sta REU_CMD
        rts

; GBC: swap WRAM bank at $7000 (GB $D000): A = old bank, X = new bank.
backend_wram_bank:
        stx mtmp
        jsr @setup
        lda #$90                ; C64 -> REU
        sta REU_CMD
        lda mtmp
        jsr @setup
        lda #$91                ; REU -> C64
        sta REU_CMD
        rts
@setup: asl                     ; REU $FC0000 + bank * $1000
        asl
        asl
        asl
        sta REU_MID
        lda #REU_WRAM
        sta REU_BANK
        lda #0
        sta REU_LO
        sta REU_C64LO
        sta REU_LENLO
        sta REU_ADDRCTL
        lda #>(WRAM+$1000)
        sta REU_C64HI
        lda #$10
        sta REU_LENHI
        rts

; GBC: zero the REU WRAM bank area ($FC0000-$FC7FFF).
backend_wram_clear:
        lda #0
        sta etmp
        lda #<etmp
        sta REU_C64LO
        lda #>etmp
        sta REU_C64HI
        lda #0
        sta REU_LO
        sta REU_MID
        sta REU_LENLO
        lda #$80
        sta REU_LENHI
        sta REU_ADDRCTL         ; fix C64 address
        lda #REU_WRAM
        sta REU_BANK
        lda #$90
        sta REU_CMD
        lda #0
        sta REU_ADDRCTL
        rts

; Zero the REU cartridge RAM area (128 KB) from a fixed zero byte.
sram_clear:
        lda #0
        sta etmp
        ldx #1
:       lda #<etmp
        sta REU_C64LO
        lda #>etmp
        sta REU_C64HI
        lda #0
        sta REU_LO
        sta REU_MID
        sta REU_LENLO
        sta REU_LENHI           ; length 0 = 64 KB
        txa
        clc
        adc #REU_SRAM
        sta REU_BANK
        lda #$80                ; fix C64 address
        sta REU_ADDRCTL
        lda #$90
        sta REU_CMD
        dex
        bpl :-
        lda #0
        sta REU_ADDRCTL
        rts

; ---- hooks -------------------------------------------------------------------

serial_out:
sound_write:
        rts

palette_write:
        sta IORAM+$47
        rts

vblank_hook:
        lda #0
        sta r_winln
        inc frames
        bne :+
        inc frames+1
:       lda frames
        and #FRAMESKIP
        beq :+
        lda #0
        beq :++
:       lda #1
:       sta r_on
        jsr read_input
.ifdef AUTOKEYS
        jmp autokeys
.else
        rts
.endif

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
        and #$02
        bne :+
        lda joy_btns
        ora #8
        sta joy_btns
:       lda #$FF
        sta $DC00
        rts

; C64 joystick (bit0 up, 1 down, 2 left, 3 right) -> GB (0 R, 1 L, 2 U, 3 D)
joymap:
        .repeat 16, I
        .byte ((I & 8) >> 3) | ((I & 4) >> 1) | ((I & 1) << 2) | ((I & 2) << 2)
        .endrep

.ifdef AUTOKEYS
; Scripted input for screenshots: entries (frame, buttons, directions),
; each held for 6 frames. Built by tools/shot.sh.
autokeys:
        ldx #0
@nx:    lda autokey_tab+1,x
        cmp #$FF
        beq @r
        lda frames
        sec
        sbc autokey_tab,x
        sta etmp
        lda frames+1
        sbc autokey_tab+1,x
        bne @skip
        lda etmp
        cmp #6
        bcs @skip
        lda joy_btns
        ora autokey_tab+2,x
        sta joy_btns
        lda joy_dirs
        ora autokey_tab+3,x
        sta joy_dirs
@skip:  txa
        clc
        adc #4
        tax
        bne @nx
@r:     rts
autokey_tab:
        .include "autokeys.inc"
        .word $FFFF
.endif

.include "cpu.s"
.include "mem.s"
.include "io.s"
.include "init.s"
.include "cgb.s"
.include "render.s"
.include "browser.s"
.include "tables.s"
