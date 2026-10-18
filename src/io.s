; ---------------------------------------------------------------------------
; Timing, I/O registers, PPU state machine and interrupts
;
; Time is counted in M-cycles (1.048576 MHz). budget counts down to the next
; scheduled event; elapsed time since the last sync is slice - budget.
; Event code only uses etmp/etmp2 so it can run in the middle of a handler.
; ---------------------------------------------------------------------------

; Account for the cycles executed since the last sync. Clobbers A, X, Y.
sync:
        lda slice
        sec
        sbc budget
        beq @r
        sta elapsed
        lda budget
        sta slice
        clc
        lda mclk
        adc elapsed
        sta mclk
        bcc :+
        inc mclk+1
        bne :+
        inc mclk+2
:       jsr timer_adv
        jmp ppu_adv
@r:     rts

; Make the main loop call do_event before the next instruction.
force_event:
        jsr sync
        lda #$FF
        sta budget
        sta slice
        rts

; ---- event handler ------------------------------------------------------------

do_event:
        jsr sync
        lda ei_pend
        beq @noei
        cmp #1
        bne @ei2
        inc ei_pend             ; EI takes effect after the next instruction
        lda #0
        sta budget
        sta slice
        jmp loop
@ei2:   lda #0
        sta ei_pend
        lda #1
        sta ime
@noei:  lda IORAM+$FF
        and IORAM+$0F
        and #$1F
        beq @noint
        ldx #0
        stx halted              ; any pending interrupt ends HALT
        ldx ime
        beq @resched
        jsr service_int
        jsr schedule
        CYCLES 5
        jmp loop
@noint: lda halted
        beq @resched
        jsr schedule            ; halted: skip straight to the next event
        lda #$FF
        sta budget
        jmp do_event
@resched:
        jsr schedule
        jmp loop

; A = pending interrupt bits. Dispatch the highest priority one.
service_int:
        ldx #0
:       lsr
        bcs :+
        inx
        bne :-
:       lda IORAM+$0F
        and int_clear,x
        sta IORAM+$0F
        lda #0
        sta ime
        txa
        asl
        asl
        asl
        ora #$40
        pha
        jsr push_pc
        pla
        sta pcl
        lda #0
        cmp pc_page
        beq :+
        sta pc_page
        jmp pc_resolve
:       rts

int_clear:
        .byte $FE, $FD, $FB, $F7, $EF

; Set budget/slice to the cycles until the next PPU or timer event.
schedule:
        lda ppu_left
        sta etmp
        lda IORAM+$07
        and #4
        beq @set
        ; cycles to TIMA overflow = (256 - TIMA) << shift - tsub
        lda IORAM+$05
        beq @set                ; 256 ticks: always beyond the PPU event
        eor #$FF
        clc
        adc #1
        sta etmp2               ; remaining ticks (1..255)
        lda IORAM+$07
        and #3
        tax
        lda #0
        ldy tac_shift,x
:       asl etmp2
        rol
        dey
        bne :-
        tay                     ; Y = hi byte
        lda etmp2
        sec
        sbc tsub
        bcs :+
        dey
:       cpy #0
        bne @set
        cmp etmp
        bcs @set
        sta etmp
@set:   ldx etmp
        dex
        stx budget
        stx slice
        rts

; ---- timer --------------------------------------------------------------------

timer_adv:
        clc
        lda divc
        adc elapsed
        sta divc
        bcc :+
        inc divc+1
:       lda IORAM+$07
        and #4
        beq @r
        clc
        lda tsub
        adc elapsed
        sta tsub
        lda tsub+1
        adc #0
        sta etmp2
        lda IORAM+$07
        and #3
        tax
        ldy tac_shift,x
        lda tsub
:       lsr etmp2
        ror
        dey
        bne :-
        tay                     ; Y = ticks
        lda tsub
        and tac_mask,x
        sta tsub
        lda #0
        sta tsub+1
        tya
        beq @r
        clc
        adc IORAM+$05
        bcc @nov
        clc                     ; overflow: reload from TMA, request interrupt
        adc IORAM+$06
        sta IORAM+$05
        lda IORAM+$0F
        ora #4
        sta IORAM+$0F
@r:     rts
@nov:   sta IORAM+$05
        rts

tac_shift:
        .byte 8, 2, 4, 6
tac_mask:
        .byte $FF, $03, $0F, $3F

; ---- PPU timing ---------------------------------------------------------------

ppu_adv:
        lda ppu_left
        sec
        sbc elapsed
        sta ppu_left
@chk:   beq @step
        bmi @step
        rts
@step:  lda IORAM+$40
        bmi @on
        lda ppu_left            ; LCD off: nothing happens
        clc
        adc #114
        sta ppu_left
        jmp @chk
@on:    ldx ppu_mode
        beq @m0
        dex
        beq @m1
        dex
        beq @m2
        ; mode 3 (transfer) -> mode 0 (hblank)
        lda #0
        sta ppu_mode
        lda #51
        jsr @add
        lda IORAM+$41
        and #$08
        beq :+
        jsr stat_irq
:       jsr hblank_hook
        lda cgb
        beq @next
        jsr hdma_hblank
        jmp @next
@m2:    lda #3                  ; OAM scan -> transfer
        sta ppu_mode
        lda #43
        jsr @add
        jmp @next
@m0:    inc ly                  ; hblank -> next line
        lda ly
        cmp #144
        bne @tom2
        lda #1
        sta ppu_mode
        lda #114
        jsr @add1
        lda IORAM+$0F
        ora #1
        sta IORAM+$0F
        lda IORAM+$41
        and #$10
        beq :+
        jsr stat_irq
:       jsr lyc_check
        jsr vblank_hook
        jmp @next
@m1:    lda dspeed              ; double speed: a line is 2 x 114 CPU cycles
        beq :+
        lda vb_half
        eor #1
        sta vb_half
        beq :+
        lda #114
        jsr @add1
        jmp @next
:       inc ly                  ; vblank line
        lda ly
        cmp #154
        beq @frame
        lda #114
        jsr @add1
        jsr lyc_check
        jmp @next
@frame: lda #0
        sta ly
@tom2:  lda #2
        sta ppu_mode
        lda #20
        jsr @add
        lda IORAM+$41
        and #$20
        beq :+
        jsr stat_irq
:       jsr lyc_check
@next:  lda ppu_left
        jmp @chk
@add:   ldx dspeed              ; mode lengths double in CPU cycles
        beq @add1
        asl
@add1:  clc
        adc ppu_left
        sta ppu_left
        rts

lyc_check:
        lda ly
        cmp IORAM+$45
        bne :+
        lda IORAM+$41
        and #$40
        beq :+
stat_irq:
        lda IORAM+$0F
        ora #2
        sta IORAM+$0F
:       rts

; ---- I/O register reads: X = register ($00-$7F), returns A ---------------------

io_read_x:
        cpx #$44
        beq @ly
        cpx #$41
        beq @stat
        cpx #$00
        beq @joyp
        cpx #$04
        beq @div
        cpx #$05
        beq @tima
        cpx #$0F
        beq @if
        cpx #$4D
        bcc :+
        lda cgb
        beq :+
        jmp cgb_io_read
:       lda IORAM,x
        rts
@ly:    jsr sync
        lda ly
        rts
@stat:  jsr sync
        lda IORAM+$40
        bpl @off
        ldx #0
        lda ly
        cmp IORAM+$45
        bne :+
        ldx #4
:       txa
        ora ppu_mode
        sta etmp
        lda IORAM+$41
        and #$78
        ora etmp
        ora #$80
        rts
@off:   lda IORAM+$41
        and #$78
        ora #$80
        rts
@div:   jsr sync
        lda divc+1
        sta etmp
        lda divc
        asl
        rol etmp
        asl
        rol etmp
        lda etmp
        rts
@tima:  jsr sync
        lda IORAM+$05
        rts
@if:    jsr sync
        lda IORAM+$0F
        ora #$E0
        rts
@joyp:  lda #$0F
        sta etmp
        lda IORAM+$00
        and #$10
        bne :+
        lda joy_dirs
        eor #$FF
        and etmp
        sta etmp
:       lda IORAM+$00
        and #$20
        bne :+
        lda joy_btns
        eor #$FF
        and etmp
        sta etmp
:       lda IORAM+$00
        and #$30
        ora #$C0
        ora etmp
        rts

; ---- I/O register writes: X = register ($00-$7F or $FF), A = value ------------

io_write_x:
        cpx #$40
        bcs :+
        jmp @low
:       bne :+
        jmp @lcdc
:       cpx #$41
        bne :+
        jmp @stat
:
        cpx #$44
        beq @r
        cpx #$45
        bne :+
        jmp @lyc
:       cpx #$46
        bne :+
        jmp oam_dma
:       cpx #$47
        bne :+
        jmp palette_write
:       cpx #$FF
        beq @ie
        cpx #$4D
        bcc @store
        ldy cgb
        beq @store
        jmp cgb_io_write
@store: sta IORAM,x
@r:     rts
@low:   cpx #$0F
        beq @if
        cpx #$00
        beq @joyp
        cpx #$02
        beq @sc
        cpx #$04
        beq @div
        cpx #$08
        bcs @sound
        cpx #$05
        bcc @store
        pha                     ; TIMA/TMA/TAC
        txa
        pha
        jsr sync
        pla
        tax
        pla
        cpx #$07
        bne :+
        ora #$F8
        sta IORAM,x
        and #3                  ; new period: realign the sub-counter
        tax
        lda divc
        and tac_mask,x
        sta tsub
        lda #0
        sta tsub+1
        jmp force_event
:       sta IORAM,x
        jmp force_event
@sound: sta IORAM,x
        jmp sound_write
@ie:    sta IORAM+$FF
        jmp force_event
@if:    ora #$E0
        sta IORAM+$0F
        jmp force_event
@joyp:  and #$30
        sta IORAM+$00
        rts
@sc:    sta IORAM+$02
        and #$80
        beq @r
        jsr serial_out
        lda #$01
        sta IORAM+$02
        lda IORAM+$0F
        ora #8
        sta IORAM+$0F
        rts
@div:   jsr sync
        lda #0
        sta divc
        sta divc+1
        sta tsub
        sta tsub+1
        jmp force_event
@stat:  and #$78
        sta etmp
        lda IORAM+$41
        and #$87
        ora etmp
        sta IORAM+$41
        rts
@lyc:   pha
        jsr sync
        pla
        sta IORAM+$45
        jsr lyc_check
        jmp force_event
@lcdc:  pha
        jsr sync
.ifdef TRACE
        jsr trace_lcdc
.endif
        pla
        sta etmp
        eor IORAM+$40
        bpl @lstore             ; display enable bit unchanged
        lda #0
        sta ly
        lda etmp
        bmi @lon
        lda #0                  ; display off
        sta ppu_mode
        lda #114
        sta ppu_left
        bne @lstore
@lon:   lda #2                  ; display on: restart at line 0
        sta ppu_mode
        lda #20
        sta ppu_left
        lda etmp
        sta IORAM+$40
        jsr lyc_check
        jmp force_event
@lstore:
        lda etmp
        sta IORAM+$40
        jmp force_event

; OAM DMA: copy 160 bytes from (A << 8) to OAM.
oam_dma:
        sta IORAM+$46
        tax
        lda RMAP,x
        bne :+
        jsr map_page
        beq @r                  ; unmapped source
:       sta ptr+1
        lda #0
        sta ptr
        ldy #159
:       lda (ptr),y
        sta OAMPG,y
        dey
        cpy #$FF
        bne :-
@r:     rts
