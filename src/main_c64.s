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


; Frame pacing: CIA ticks per GB frame (70224 / 1048576 s at the PAL CIA
; clock of 985248 Hz). Assumes the CIA keeps its 1 MHz clock in turbo mode.
FRAME_TICKS = 16495
MAX_LAG     = 3 * FRAME_TICKS  ; never build up more debt than this
MAX_SKIP    = 3                ; render at least every 4th frame

.import __BROWSER_LOAD__, __BROWSER_RUN__, __BROWSER_SIZE__
.import __HICODE_LOAD__, __HICODE_RUN__, __HICODE_SIZE__
REU_BROWSER = $FD           ; REU bank holding a copy of the ROM browser

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
        jsr browser_fetch
        jsr zp_clear
        jsr browser             ; choose a ROM and load it into the REU
        jsr zp_clear
        jsr video_init
        jsr render_init
        jsr timer_init          ; (before gb_init, which clears the overlay)
        jsr gb_init
        jsr sound_init
        lda #0
        sta sav_active
        sta sav_dirty
        lda has_sram
        beq :++
        lda sav_loaded          ; keep a save file loaded by the browser
        bne :+
        jsr sram_clear
:       lda has_batt            ; saving possible: battery RAM and a file name
        beq :+
        lda sav_name
        beq :+
        lda #1
        sta sav_active
:       jmp loop

irq:    rti

; The ROM browser runs at $9000. Its load image at $3800 is saved in the REU
; on the first start and copied from there on every start (RESTORE included).
browser_fetch:
        lda first_run
        beq :+
        jsr hicode_copy
        lda #$90                ; C64 -> REU
        jsr @dma
        lda #0
        sta first_run
:       lda #$91                ; REU -> C64
@dma:   pha
        cmp #$90
        bne :+
        lda #<__BROWSER_LOAD__
        ldx #>__BROWSER_LOAD__
        bne :++
:       lda #<__BROWSER_RUN__
        ldx #>__BROWSER_RUN__
:       sta REU_C64LO
        stx REU_C64HI
        lda #0
        sta REU_LO
        sta REU_MID
        sta REU_ADDRCTL
        lda #REU_BROWSER
        sta REU_BANK
        lda #<__BROWSER_SIZE__
        sta REU_LENLO
        lda #>__BROWSER_SIZE__
        sta REU_LENHI
        pla
        sta REU_CMD
        rts
first_run:
        .byte 1

; Copy the extra resident code from its load image ($4000) to $C300.
hicode_copy:
        lda #<__HICODE_LOAD__
        sta ptr
        lda #>__HICODE_LOAD__
        sta ptr+1
        lda #<__HICODE_RUN__
        sta ptr2
        lda #>__HICODE_RUN__
        sta ptr2+1
        ldx #>(__HICODE_SIZE__+255)
        ldy #0
:       lda (ptr),y
        sta (ptr2),y
        iny
        bne :-
        inc ptr+1
        inc ptr2+1
        dex
        bne :-
        rts

; RESTORE: save the game if needed, then back to the ROM browser.
nmi:    ldx #$FF
        txs
        lda #$35
        sta $01
        lda sav_dirty
        beq :+
        jsr save_game
:       jmp start

; ---- save games ------------------------------------------------------------

.segment "BSS"
sav_name:   .res 64             ; save file name (ROM name with .sav), "" = none
sav_loaded: .res 1              ; the browser loaded a save file into the REU
sav_active: .res 1              ; saving is possible for the running game
f1_prev:    .res 1
.segment "CODE"

; Write the cartridge RAM to the save file through the Ultimate DOS.
save_game:
        lda sav_active
        beq @r
        lda #5                  ; green border while saving
        sta $D020
        jsr sram_flush
        lda #$01                ; open file for writing, always overwrite
        sta UCI_CMD
        lda #$02
        sta UCI_CMD
        lda #$0E
        sta UCI_CMD
        ldy #0
:       lda sav_name,y
        beq :+
        sta UCI_CMD
        iny
        bne :-
:       jsr uci_go
        bcc @err
        lda #$01                ; save REU $FE0000, sram_pages * 256 bytes
        sta UCI_CMD
        lda #$22
        sta UCI_CMD
        lda #0
        sta UCI_CMD
        sta UCI_CMD
        lda #REU_SRAM
        sta UCI_CMD
        lda #0
        sta UCI_CMD
        sta UCI_CMD
        lda sram_pages
        sta UCI_CMD
        lda sram_pages+1
        sta UCI_CMD
        lda #0
        sta UCI_CMD
        jsr uci_go
        php
        lda #$01                ; close
        sta UCI_CMD
        lda #$03
        sta UCI_CMD
        jsr uci_go
        plp
        bcc @err
        lda #0
        sta sav_dirty
        sta $D020
@r:     rts
@err:   lda #2                  ; red border: saving failed
        sta $D020
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
:       jsr frame_pace
        jsr sound_frame
        jsr read_input
.ifdef AUTOKEYS
        jmp autokeys
.else
        rts
.endif

; Keep the game at real-time speed: wait when ahead, skip rendering the next
; frame when more than a frame behind (at most MAX_SKIP in a row).
frame_pace:
        jsr timer_read          ; t_d = ticks since the last frame
        sec
        lda t_last
        sbc t_now
        sta t_d
        lda t_last+1
        sbc t_now+1
        sta t_d+1
        lda t_blast             ; whole 65536-tick periods in between?
        sbc t_bnow              ; (C from above: borrow if the 16 bits wrapped)
        ldx t_bnow
        stx t_blast
        cmp #0
        beq :+
        lda #<MAX_LAG           ; a very slow frame: just mark as far behind
        sta t_bal
        lda #>MAX_LAG
        sta t_bal+1
        lda t_now
        sta t_last
        lda t_now+1
        sta t_last+1
        jmp @behind
:       lda t_now
        sta t_last
        lda t_now+1
        sta t_last+1
        clc                     ; t_bal += t_d - FRAME_TICKS
        lda t_bal
        adc t_d
        sta t_bal
        lda t_bal+1
        adc t_d+1
        sta t_bal+1
        sec
        lda t_bal
        sbc #<FRAME_TICKS
        sta t_bal
        lda t_bal+1
        sbc #>FRAME_TICKS
        sta t_bal+1
        bpl @behind
        sec                     ; ahead: wait -t_bal ticks
        lda #0
        sbc t_bal
        sta t_d
        lda #0
        sbc t_bal+1
        sta t_d+1
:       jsr timer_read
        sec
        lda t_last
        sbc t_now
        tax
        lda t_last+1
        sbc t_now+1
        cmp t_d+1
        bcc :-
        bne :+
        cpx t_d
        bcc :-
:       lda t_now
        sta t_last
        lda t_now+1
        sta t_last+1
        lda #0
        sta t_bal
        sta t_bal+1
        beq @render
@behind:
        lda t_bal+1             ; clamp the debt
        cmp #>MAX_LAG
        bcc :+
        lda #<MAX_LAG
        sta t_bal
        lda #>MAX_LAG
        sta t_bal+1
:       lda t_bal+1             ; more than one frame behind?
        cmp #>FRAME_TICKS
        bcc @render
        bne :+
        lda t_bal
        cmp #<FRAME_TICKS
        bcc @render
:       lda t_skip
        cmp #MAX_SKIP
        bcs @render
        inc t_skip
        lda #0
        sta r_on
        rts
@render:
        lda #0
        sta t_skip
        lda #1
        sta r_on
        rts

; t_now = CIA 1 timer A (counts down at 1 MHz), t_bnow = timer B low byte
; (counts timer A underflows), read without tearing.
timer_read:
        lda $DC06
        sta t_bnow
        lda $DC05
        sta t_now+1
        lda $DC04
        sta t_now
        lda $DC05
        cmp t_now+1
        bne timer_read
        lda $DC06
        cmp t_bnow
        bne timer_read
        rts

timer_init:
        lda #$FF
        sta $DC04
        sta $DC05
        sta $DC06
        sta $DC07
        lda #$11                ; timer A: start, continuous, load latch
        sta $DC0E
        lda #$51                ; timer B: count timer A underflows
        sta $DC0F
        jsr timer_read
        lda t_bnow
        sta t_blast
        lda t_now
        sta t_last
        lda t_now+1
        sta t_last+1
        lda #0
        sta t_bal
        sta t_bal+1
        sta t_skip
        rts

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

.segment "HICODE"            ; resident helpers for save games
; Push the command written to UCI_CMD, wait, drain the reply.
; C=1 if the status starts with "00".
uci_go:
        lda #$01                ; PUSH_CMD
        sta UCI_CTRL
:       lda UCI_CTRL            ; wait for a data state
        and #$20
        beq :-
:       lda UCI_CTRL            ; skip the data channel
        bpl :+
        lda UCI_DATA
        jmp :-
:       lda #0
        sta etmp
        sta etmp2
        lda UCI_CTRL
        and #$40
        beq :+
        lda UCI_STATUS
        sta etmp
        lda UCI_STATUS
        sta etmp2
:       lda #$02                ; accept
        sta UCI_CTRL
:       lda UCI_CTRL
        and #$30
        cmp #$10
        beq :-
        lda etmp
        cmp #'0'
        bne :+
        lda etmp2
        cmp #'0'
        bne :+
        sec
        rts
:       clc
        rts

; Write all cached cartridge RAM pages back to the REU.
sram_flush:
        ldy nslots
        dey
@s:     lda slot_khi,y
        cmp #REU_SRAM
        bcc @nx
        cmp #$FF
        beq @nx
        sta key_save+1
        lda slot_klo,y
        sta key_save
        sty etmp2
        lda slot_page,y
        jsr backend_store_page
        ldy etmp2
@nx:    dey
        bpl @s
        rts


.segment "BROWSER"           ; one-time set-up, runs from the overlay
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


.segment "CODE"

.include "cpu.s"
.include "mem.s"
.include "io.s"
.include "init.s"
.include "cgb.s"
.include "sound.s"
.include "render.s"
.include "browser.s"
.include "tables.s"
