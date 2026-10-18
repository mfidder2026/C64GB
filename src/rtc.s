; ---------------------------------------------------------------------------
; MBC3 real-time clock
;
; Registers $08-$0C (selected through the RAM bank register): seconds,
; minutes, hours, day counter low, day high (bit 0 day bit 8, bit 6 halt,
; bit 7 day counter carry). Writing $00 then $01 to $6000-$7FFF latches the
; running clock into the readable copy. The clock runs on emulated time:
; bit 20 of the M-cycle counter toggles once per second (2^20 M-cycles).
; ---------------------------------------------------------------------------

.segment "BSS"
rtc_reg:    .res 5          ; running clock: S, M, H, DL, DH
rtc_lat:    .res 5          ; latched copy (what the game reads)
rtc_lprev:  .res 1          ; last value written to the latch register
rtc_secb:   .res 1          ; mclk bit 20 at the last tick
has_rtc:    .res 1          ; cartridge has an MBC3 timer
.segment RTCSEG

; C=1 and Y = register index if an RTC register is selected and enabled.
rtc_sel:
        lda has_rtc
        and ram_en
        beq @no
        lda ram_bank
        sec
        sbc #8
        cmp #5
        bcs @no
        tay
        sec
        rts
@no:    clc
        rts

; Read from $A000-$BFFF with no RAM mapped: C=1, A = latched register.
rtc_read:
        jsr rtc_sel
        bcc :+
        lda rtc_lat,y
:       rts

; Write A to $A000-$BFFF with no RAM mapped: sets the running register.
rtc_write:
        pha
        jsr rtc_sel
        pla
        bcc :+
        and rtc_mask,y          ; unused bits read back as 0
        sta rtc_reg,y
:       rts
rtc_mask: .byte $3F, $3F, $1F, $FF, $C1

; Write A to $6000-$7FFF: $00 -> $01 latches the clock.
rtc_latch:
        pha
        jsr sync                ; bring the clock up to this exact cycle
        jsr rtc_tick
        pla
        tax
        lda rtc_lprev
        bne :++
        cpx #1
        bne :++
        ldy #4
:       lda rtc_reg,y
        sta rtc_lat,y
        dey
        bpl :-
:       stx rtc_lprev
        rts

; Once per frame: advance the clock by the whole seconds that have passed.
rtc_tick:
        lda has_rtc
        beq @r
        lda mclk+2
        and #$10
        cmp rtc_secb
        beq @r
        sta rtc_secb
        lda rtc_reg+4           ; halted?
        and #$40
        bne @r
        ldx #0                  ; seconds, minutes, hours: at the limit wrap
@u:     inc rtc_reg,x           ; to 0 and carry; an out-of-range value
        lda rtc_reg,x           ; counts on to its bit width and wraps
        cmp rtc_lim,x           ; without a carry
        beq :+
        cmp rtc_wrap,x
        bne @r
        lda #0
        sta rtc_reg,x
        rts
:       lda #0
        sta rtc_reg,x
        inx
        cpx #3
        bne @u
        inc rtc_reg+3           ; days (9 bits, then the carry flag)
        bne @r
        lda rtc_reg+4
        eor #1
        tax
        and #1
        bne :+
        txa
        ora #$80                ; day 511 -> 0: set the carry
        tax
:       stx rtc_reg+4
@r:     rts
rtc_lim:  .byte 60, 60, 24
rtc_wrap: .byte 64, 64, 32

.segment "CODE"
