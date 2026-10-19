; ---------------------------------------------------------------------------
; Machine detection and the diagnostics screen (key D in the ROM browser).
; Resident in the $C300 area.
; ---------------------------------------------------------------------------

.segment "BSS"
rtc_buf:     .res 48            ; clock state block for save files
ntsc:        .res 1             ; 1 = NTSC machine
frame_ticks: .res 2             ; CIA ticks per GB frame
snd_k:       .res 3             ; pulse frequency constant for this machine
dg_val:      .res 2
dg_row:      .res 1
dg_buf:      .res 7
.segment "HICODE"

; PAL or NTSC: the last raster line is 311 (PAL) or 262 (NTSC). Sets ntsc,
; frame_ticks and the sound frequency constant.
video_detect:
        lda #0
        sta etmp
:       bit $D011               ; wait for raster lines 256+
        bpl :-
:       lda $D012               ; highest low byte seen in 256+
        cmp etmp
        bcc :+
        sta etmp
:       bit $D011
        bmi :--
        ldx #0
        lda etmp
        cmp #$20
        bcs :+
        inx                     ; last line below 288: NTSC
:       stx ntsc
        lda frame_lo,x
        sta frame_ticks
        lda frame_hi,x
        sta frame_ticks+1
        lda sndk_lo,x
        sta snd_k
        lda sndk_mi,x
        sta snd_k+1
        lda sndk_hi,x
        sta snd_k+2
        rts
frame_lo: .byte <FRAME_PAL, <FRAME_NTSC
frame_hi: .byte >FRAME_PAL, >FRAME_NTSC
; SID value for a GB pulse channel = K / (2048 - x), K = 131072 * 2^24 / clock
sndk_lo: .byte <2231950, <2150176
sndk_mi: .byte >2231950, >2150176
sndk_hi: .byte ^2231950, ^2150176

.segment "DIAG"

.ifdef AUTOLOAD
; Test builds: load a ROM from /Temp/C64GB without the browser UI
; (AUTOLOAD = 1 dmg-acid2, 2 libbet, 3 ucity).
autoload:
        lda #0
        sta sav_name
        sta sav_loaded
        jsr text_init
        lda #$04
        sta UCI_CTRL
        lda #$08
        sta UCI_CTRL
        lda #$02
        sta UCI_CTRL
        lda #<(al_dir-1)
        sta b_ptr
        lda #>(al_dir-1)
        sta b_ptr+1
        jsr chdir_entry
        lda #<(al_rom-1)
        sta b_ptr
        lda #>(al_rom-1)
        sta b_ptr+1
        jmp load_entry
al_dir: .byte "/Temp/C64GB", 0
.if AUTOLOAD = 1
al_rom: .byte "dmg-acid2.gb", 0
.elseif AUTOLOAD = 2
al_rom: .byte "libbet.gb", 0
.else
al_rom: .byte "ucity.gbc", 0
.endif
.endif

; From the browser's input loop: D opens the diagnostics screen.
diag_key:
        lda #$FB                ; column 2, row 2 = D
        sta $DC00
        lda $DC01
        ldx #$FF
        stx $DC00
        and #$04
        beq :+
        rts
:       jsr diag
        jsr text_init
        jsr show_path
        jmp draw_list

diag:
        jsr timer_init          ; CIA 1 timer A free running from $FFFF
        jsr text_init
        lda #<dg_title
        ldx #>dg_title
        ldy #2
        jsr print_at
        ldx ntsc                ; video standard
        lda dg_vid_lo,x
        pha
        lda dg_vid_hi,x
        tax
        pla
        ldy #4
        jsr print_at
        lda $D031               ; turbo register present?
        cmp #$FF
        jsr dg_yesno_ne
        lda #<dg_turbo
        ldx #>dg_turbo
        ldy #5
        jsr dg_flag
        lda #$55                ; REU: its address register reads back
        sta $DF02
        lda $DF02
        cmp #$55
        jsr dg_yesno_eq
        lda #<dg_reu
        ldx #>dg_reu
        ldy #6
        jsr dg_flag
        lda UCI_CMD             ; Ultimate Command Interface
        and #$7F
        cmp #$49
        jsr dg_yesno_eq
        lda #<dg_uci
        ldx #>dg_uci
        ldy #7
        jsr dg_flag

        ; CPU: 320-cycle RAM-only blocks from raster line 0 to line 256
        ; (256 lines: 16128 cycles PAL, 16640 NTSC at 1 MHz).
        ; Tenths of MHz = blocks * 3200 / cycles.
        lda #0
        sta div_r
        sta div_r+1
:       bit $D011               ; wait for lines 256+, then line 0
        bpl :-
:       bit $D011
        bmi :-
@blk:   ldx #64
:       dex
        bne :-
        inc div_r
        bne :+
        inc div_r+1
:       bit $D011
        bpl @blk
        lda div_r               ; div_q = blocks * 25 * 128 = blocks * 3200
        sta div_q               ; (dg_buf = blocks, then blocks * 8)
        sta dg_buf
        lda div_r+1
        sta div_q+1
        sta dg_buf+1
        lda #0
        sta div_q+2
        sta dg_buf+2
        ldx #3
:       asl dg_buf
        rol dg_buf+1
        rol dg_buf+2
        dex
        bne :-
        jsr @add                ; q = b + 8b
        asl dg_buf
        rol dg_buf+1
        rol dg_buf+2
        jsr @add                ; q = b + 8b + 16b = 25b
        ldx #7
:       asl div_q
        rol div_q+1
        rol div_q+2
        dex
        bne :-
        lda #<16128
        ldx #>16128
        ldy ntsc
        beq :+
        lda #<16640
        ldx #>16640
:       sta div_v
        stx div_v+1
        jsr divide
        lda #<dg_cpu
        ldx #>dg_cpu
        ldy #9
        sec
        jsr dg_num
        jmp @cia
@add:   clc                     ; div_q += dg_buf
        lda div_q
        adc dg_buf
        sta div_q
        lda div_q+1
        adc dg_buf+1
        sta div_q+1
        lda div_q+2
        adc dg_buf+2
        sta div_q+2
        rts
@cia:
        ; CIA ticks during one video frame (19656 PAL / 17095 NTSC at 1 MHz)
        jsr dg_sync
        jsr timer_read
        jsr dg_mark
:       lda $D012
        cmp #$80
        bne :-
        jsr dg_elapsed
        lda #<dg_cia
        ldx #>dg_cia
        ldy #10
        clc
        jsr dg_num

        ; REU DMA of 8 KB into the cache area at $A000 (unused before a game)
        jsr timer_read
        jsr dg_mark
        lda #0
        sta $DF02
        sta $DF04
        sta $DF05
        sta $DF06
        sta $DF07
        sta $DF0A
        lda #$A0
        sta $DF03
        lda #$20
        sta $DF08
        lda #$91
        sta $DF01
        jsr dg_elapsed
        lda #<dg_dma
        ldx #>dg_dma
        ldy #11
        clc
        jsr dg_num

        lda #<dg_fire
        ldx #>dg_fire
        ldy #14
        jsr print_at
        jmp wait_fire

; Wait for raster line $80 and for it to pass: one frame until it returns.
dg_sync:
:       lda $D012
        cmp #$80
        bne :-
:       lda $D012
        cmp #$80
        beq :-
        rts

dg_mark:
        lda t_now
        sta t_last
        lda t_now+1
        sta t_last+1
        rts

; div_q = CIA ticks since dg_mark
dg_elapsed:
        jsr timer_read
        sec
        lda t_last
        sbc t_now
        sta div_q
        lda t_last+1
        sbc t_now+1
        sta div_q+1
        rts

dg_yesno_ne:                    ; Z=1 -> "no"
        beq dg_no
dg_yes: lda #<dg_s_yes
        ldx #>dg_s_yes
        bne dg_set
dg_yesno_eq:                    ; Z=1 -> "yes"
        beq dg_yes
dg_no:  lda #<dg_s_no
        ldx #>dg_s_no
dg_set: sta dg_val
        stx dg_val+1
        rts

; Label A/X on row Y, then the yes/no string in column 20.
dg_flag:
        sty dg_row
        jsr print_at
        lda dg_val
        ldx dg_val+1
        ldy dg_row
        jmp print_at_col2_20

; Label A/X on row Y, then div_q in decimal in column 20 (C=1: one decimal).
dg_num:
        php
        sty dg_row
        jsr print_at
        jsr dec5
        plp
        bcc :+
        lda dg_buf+4            ; insert a decimal point
        sta dg_buf+5
        lda #'.'
        sta dg_buf+4
        lda #0
        sta dg_buf+6
:       lda #<dg_buf
        ldx #>dg_buf
        ldy dg_row
        jmp print_at_col2_20

; div_q (16 bit) -> 5 decimal digits in dg_buf.
dec5:
        ldy #0
@d:     ldx #'0'
@s:     lda div_q
        sec
        sbc dec_lo,y
        pha
        lda div_q+1
        sbc dec_hi,y
        bcc @n
        sta div_q+1
        pla
        sta div_q
        inx
        bne @s
@n:     pla
        txa
        sta dg_buf,y
        iny
        cpy #5
        bne @d
        lda #0
        sta dg_buf+5
        rts
dec_lo: .byte <10000, <1000, <100, <10, <1
dec_hi: .byte >10000, >1000, >100, >10, >1

dg_title: .byte "C64GB diagnostics", 0
dg_pal:   .byte "Video: PAL", 0
dg_ntsc:  .byte "Video: NTSC", 0
dg_vid_lo: .byte <dg_pal, <dg_ntsc
dg_vid_hi: .byte >dg_pal, >dg_ntsc
dg_turbo: .byte "Turbo register:", 0
dg_reu:   .byte "REU:", 0
dg_uci:   .byte "Command Interface:", 0
dg_cpu:   .byte "CPU (MHz):", 0
dg_cia:   .byte "CIA ticks/frame:", 0
dg_dma:   .byte "REU 8 KB (ticks):", 0
dg_fire:  .byte "Press fire or RETURN", 0
dg_s_yes: .byte "yes", 0
dg_s_no:  .byte "no", 0

.segment "HICODE"
