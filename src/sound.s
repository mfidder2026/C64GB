; ---------------------------------------------------------------------------
; Game Boy APU -> SID
;
; CH1 (pulse + sweep) -> voice 1, CH2 (pulse) -> voice 2, CH4 (noise) or,
; when it is silent, CH3 (wave, played as a triangle) -> voice 3.
; Channel volume (0-15) becomes the SID sustain level (attack, decay and
; release 0); a louder volume retriggers the gate. Envelopes, length
; counters and the CH1 sweep are stepped once per frame.
; ---------------------------------------------------------------------------

SID      = $D400
SID_VOL  = $D418

.segment "BSS"
snd_on:     .res 4      ; channel playing
snd_vol:    .res 4      ; current volume 0-15
snd_env:    .res 4      ; NRx2 (envelope) latched at trigger
snd_envc:   .res 4      ; envelope step counter (frames)
snd_len:    .res 4      ; length counter in 1/256 s (CH3: 0 = 256)
snd_svol:   .res 4      ; volume last written for the channel's voice
snd_swc:    .res 1      ; CH1 sweep counter (1/128 s)
snd_ch:     .res 1
v3_owner:   .res 1      ; GB channel (2 or 3) on voice 3, $FF = none
div_q:      .res 3      ; division: dividend in, quotient out
div_r:      .res 2
div_v:      .res 2
.segment "HICODE"

; Register offset $10-$23 -> channel * 8 + register (0-4); $FF = none
snd_regmap:
        .byte $00,$01,$02,$03,$04       ; NR10-NR14
        .byte $FF,$09,$0A,$0B,$0C       ; -, NR21-NR24
        .byte $10,$11,$12,$13,$14       ; NR30-NR34
        .byte $FF,$19,$1A,$1B,$1C       ; -, NR41-NR44
voice_base: .byte 0, 7, 14, 14          ; SID voice registers per GB channel
reg_base:   .byte $10, $15, $1A, $1F    ; NRx0 of each channel
snd_mask:   .byte $11, $22, $44, $88    ; NR51 bits per channel
wave_tab:   .byte $40, $40, $10, $80    ; pulse, pulse, triangle, noise
duty_pw:    .byte 2, 4, 8, 12           ; pulse width high nibble per duty
ch3_vol:    .byte 0, 15, 8, 4           ; NR32 output level -> volume
; noise: 557991 / divisor (0 -> 0.5), before >> (shift + 1)
noise_lo:   .byte <1115982, <557991, <278995, <185997, <139498, <111598, <92999, <79713
noise_mi:   .byte >1115982, >557991, >278995, >185997, >139498, >111598, >92999, >79713
noise_hi:   .byte ^1115982, ^557991, ^278995, ^185997, ^139498, ^111598, ^92999, ^79713

sound_init:
        lda #0
        ldx #24
:       sta SID,x
        dex
        bpl :-
        ldx #3
:       sta snd_on,x
        sta snd_svol,x
        dex
        bpl :-
        lda #$FF
        sta v3_owner
        jmp snd_master

; A register in $FF10-$FF3F was written (value already in IORAM), X = reg.
sound_write:
        cpx #$26
        bne :+
        and #$80                ; NR52 bit 7: power
        bne @r
        jsr sound_init
        lda #0
        sta SID_VOL
        rts
:       cpx #$24
        bcc :+
        bne @r                  ; NR51 panning applies on the next frame
        jmp snd_master
:       lda snd_regmap-$10,x
        bmi @r
        pha
        lsr
        lsr
        lsr
        tay                     ; Y = channel
        pla
        and #7
        beq @nr0
        cmp #2
        bcc @len
        beq @env
        cmp #3
        beq @freq
        lda IORAM,x             ; NRx4 bit 7: trigger
        bpl @freq
        jsr snd_trigger
@freq:  jmp snd_freq
@len:   lda IORAM,x             ; NRx1: length 64 - t (CH3: 256 - t)
        cpy #2
        beq :+
        and #$3F
        ora #$C0                ; 256 - (64 - t) ... negated below
:       eor #$FF
        clc
        adc #1
        sta snd_len,y
@r:     rts
@env:   cpy #2
        bne :+
        jmp snd_apply           ; NR32: CH3 output level
:       lda IORAM,x             ; NRx2 with the DAC off silences the channel
        and #$F8
        bne @r
        beq @off
@nr0:   cpy #2
        bne @r                  ; NR10: sweep, used per frame
        lda IORAM,x             ; NR30 bit 7: DAC
        bmi @r
@off:   lda #0
        sta snd_on,y
        jmp snd_apply

; NR50: master volume = the louder of the two sides (0-7 -> 1-15).
snd_master:
        lda IORAM+$24
        and #7
        sta etmp
        lda IORAM+$24
        lsr
        lsr
        lsr
        lsr
        and #7
        cmp etmp
        bcs :+
        lda etmp
:       asl
        ora #1
        sta SID_VOL
        rts

; Start channel Y.
snd_trigger:
        ldx reg_base,y
        lda #1
        sta snd_on,y
        lda #0
        sta snd_svol,y          ; forces a gate retrigger
        lda snd_len,y
        bne :+
        cpy #2
        beq :+                  ; CH3: 0 already means 256
        lda #64
        sta snd_len,y
:       cpy #2
        bne @env
        lda IORAM,x             ; CH3: DAC
        bmi @r
        lda #0
        sta snd_on,y
@r:     rts
@env:   lda IORAM+2,x           ; envelope and start volume
        sta snd_env,y
        and #7
        sta snd_envc,y
        lda IORAM+2,x
        lsr
        lsr
        lsr
        lsr
        sta snd_vol,y
        lda IORAM+2,x
        and #$F8
        bne :+
        sta snd_on,y            ; DAC off
:       cpy #0
        bne @r
        lda IORAM+$10           ; CH1 sweep period
        lsr
        lsr
        lsr
        and #$0E                ; period * 2 (counter steps by 1/128 s)
        sta snd_swc
        rts

; Program the SID frequency of channel Y from its registers.
snd_freq:
        sty snd_ch
        ldx reg_base,y
        cpy #3
        beq @noise
        sec                     ; div_v = 2048 - x
        lda #0
        sbc IORAM+3,x
        sta div_v
        lda IORAM+4,x
        and #7
        eor #$FF
        adc #8
        sta div_v+1
        lda snd_k               ; pulse: K / (2048 - x) (K = 2231950 on PAL)
        sta div_q
        lda snd_k+1
        sta div_q+1
        lda snd_k+2
        sta div_q+2
        cpy #2
        bne :+
        lsr div_q+2             ; wave: half the frequency
        ror div_q+1
        ror div_q
:       jsr divide
        jmp @set
@noise: lda IORAM+$22
        and #7
        tax
        lda noise_lo,x
        sta div_q
        lda noise_mi,x
        sta div_q+1
        lda noise_hi,x
        sta div_q+2
        lda IORAM+$22
        lsr
        lsr
        lsr
        lsr
        tax
        inx
:       lsr div_q+2
        ror div_q+1
        ror div_q
        dex
        bne :-
        lda div_q+2
        beq @set
        lda #$FF
        sta div_q
        sta div_q+1
@set:   ldy snd_ch
        jsr snd_voice           ; X = SID voice base, C=1 if not on a voice
        bcs :+
        lda div_q
        sta SID,x
        lda div_q+1
        sta SID+1,x
:       jmp snd_apply

; X = SID register base for channel Y; C=1 if the channel has no voice now.
snd_voice:
        ldx voice_base,y
        cpy #2
        bcc @ok
        cpy v3_owner
        bne @no
@ok:    clc
        rts
@no:    sec
        rts

; div_q (24 bit) / div_v (16 bit) -> div_q (saturated to 16 bits). Keeps Y.
divide:
        lda div_v+1             ; quotient would not fit 16 bits: saturate
        bne :+
        lda div_q+2
        cmp div_v
        bcc :+
        lda #$FF
        sta div_q
        sta div_q+1
        rts
:       lda #0
        sta div_r
        sta div_r+1
        ldx #24
@l:     asl div_q
        rol div_q+1
        rol div_q+2
        rol div_r
        rol div_r+1
        lda div_r
        sec
        sbc div_v
        pha
        lda div_r+1
        sbc div_v+1
        bcc @no
        sta div_r+1
        pla
        sta div_r
        inc div_q
        bne @nx                 ; (always: bit 0 was clear)
@no:    pla
@nx:    dex
        bne @l
        rts

; Once per frame: length counters, envelopes, CH1 sweep, voice 3 owner.
sound_frame:
        lda IORAM+$26
        bmi :+
        rts
:       ldy #3
@ch:    lda snd_on,y
        beq @nx
        ldx reg_base,y          ; length counter: 4 steps per frame
        lda IORAM+4,x
        and #$40
        beq @env
        lda snd_len,y
        bne :+
        lda #252                ; CH3: 0 means 256
        sta snd_len,y
        bne @env
:       sec
        sbc #4
        sta snd_len,y
        beq :+
        bcs @env
:       lda #0
        sta snd_on,y
        sta snd_len,y
        beq @nx
@env:   cpy #2
        beq @nx
        lda snd_env,y           ; envelope: one step every (NRx2 & 7) frames
        and #7
        beq @nx
        lda snd_envc,y
        sec
        sbc #1
        sta snd_envc,y
        bne @nx
        lda snd_env,y
        and #7
        sta snd_envc,y
        lda snd_env,y
        and #8
        beq @down
        lda snd_vol,y
        cmp #15
        beq @nx
        adc #1
        sta snd_vol,y
        bne @nx
@down:  lda snd_vol,y
        beq @nx
        sec
        sbc #1
        sta snd_vol,y
@nx:    dey
        bpl @ch

        lda IORAM+$10           ; CH1 sweep
        and #$70
        beq @own
        lda snd_on
        beq @own
        dec snd_swc
        dec snd_swc
        bpl @own
        lda IORAM+$10
        lsr
        lsr
        lsr
        and #$0E
        sta snd_swc
        jsr sweep_step

@own:   ldy #3                  ; voice 3: noise when playing, else wave
        lda snd_on+3
        bne :+
        dey
        lda snd_on+2
        bne :+
        ldy #$FF
:       cpy v3_owner
        beq @upd
        sty v3_owner
        cpy #$FF
        bne :+
        lda #0                  ; nothing left on voice 3: silence it
        sta SID+14+4
        beq @upd
:       lda #0
        sta snd_svol,y
        jsr snd_freq
@upd:   ldy #0
        jsr snd_apply
        ldy #1
        jsr snd_apply
        ldy v3_owner
        bmi @r
        jmp snd_apply
@r:     rts

; CH1 frequency sweep step.
sweep_step:
        lda IORAM+$10
        and #7
        beq @r
        tax
        lda IORAM+$13           ; delta = f >> shift
        sta div_q
        lda IORAM+$14
        and #7
        sta div_q+1
:       lsr div_q+1
        ror div_q
        dex
        bne :-
        lda IORAM+$10
        and #8
        bne @sub
        clc
        lda IORAM+$13
        adc div_q
        tax
        lda IORAM+$14
        and #7
        adc div_q+1
        cmp #8
        bcc @set
        lda #0                  ; overflow: channel off
        sta snd_on
        rts
@sub:   sec
        lda IORAM+$13
        sbc div_q
        tax
        lda IORAM+$14
        and #7
        sbc div_q+1
        bcc @r
@set:   sta div_q
        lda IORAM+$14
        and #$F8
        ora div_q
        sta IORAM+$14
        stx IORAM+$13
        ldy #0
        jmp snd_freq
@r:     rts

; Write channel Y's volume and waveform to its SID voice.
snd_apply:
        sty snd_ch
        jsr snd_voice
        bcs @r
        lda snd_on,y            ; effective volume -> etmp2
        beq @v
        lda IORAM+$25           ; panned to neither side: silent
        and snd_mask,y
        beq @v
        lda snd_vol,y
        cpy #2
        bne @v
        lda IORAM+$1C           ; CH3 output level
        lsr
        lsr
        lsr
        lsr
        lsr
        and #3
        tay
        lda ch3_vol,y
        ldy snd_ch
@v:     sta etmp2
        asl
        asl
        asl
        asl
        sta SID+6,x             ; sustain = volume, release 0
        lda #0
        sta SID+5,x             ; attack 0, decay 0
        cpy #2
        bcs @w
        lda reg_base,y          ; pulse width from the duty (NRx1 bits 7-6)
        tay
        lda IORAM+1,y
        rol
        rol
        rol
        and #3
        tay
        lda duty_pw,y
        sta SID+3,x
        ldy snd_ch
@w:     lda wave_tab,y
        sta etmp
        lda etmp2
        beq @off
        cmp snd_svol,y          ; louder than before: retrigger the gate
        beq @on
        bcc @on
        lda etmp
        sta SID+4,x
@on:    lda etmp
        ora #1
        sta SID+4,x
        lda etmp2
        sta snd_svol,y
@r:     rts
@off:   sta snd_svol,y
        lda etmp
        sta SID+4,x
        rts

; NR52 read: power bit and channel status.
sound_status:
        lda snd_on+3
        asl
        ora snd_on+2
        asl
        ora snd_on+1
        asl
        ora snd_on
        ora #$70
        sta etmp
        lda IORAM+$26
        and #$80
        ora etmp
        rts

.segment "CODE"
