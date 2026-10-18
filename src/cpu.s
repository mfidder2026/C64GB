; ---------------------------------------------------------------------------
; LR35902 (Game Boy CPU) interpreter
;
; Handlers are entered with X = opcode and the instruction's base cycle count
; already subtracted from budget. Every handler ends with NEXT (jmp loop).
; ---------------------------------------------------------------------------

; ---- main dispatch loop ---------------------------------------------------

loop:
        bit budget
        bmi @event
        ldy pcl
        lda (pcb),y
        inc pcl
        beq @cross
@go:    tax
        lda budget
        sec
        sbc cyctab,x
        sta budget
        lda optab_lo,x
        sta @jmp+1
        lda optab_hi,x
        sta @jmp+2
@jmp:   jmp $0000
@cross: jsr pc_cross
        jmp @go
@event: jmp do_event

; PC low byte wrapped: move to the next GB page. Preserves A.
pc_cross:
        pha
        inc pc_page
        jsr pc_resolve
        pla
        rts

; Point pcb at the C64 page holding GB page pc_page. Clobbers A, X, Y.
pc_resolve:
        ldx pc_page
        lda RMAP,x
        bne @set
        cpx #$80
        bcc @rom
        cpx #$FF
        bne @ff
        lda #>IORAM             ; code in HRAM (e.g. the OAM DMA routine)
        bne @set
@ff:    lda #>FFPG
        bne @set
@rom:   jsr rom_miss
@set:   sta pcb+1
        rts

; Jump to the GB address in tmp (lo) / tmp2 (hi).
goto_t:
        lda tmp
        sta pcl
        lda tmp2
        cmp pc_page
        beq @r
        sta pc_page
        jmp pc_resolve
@r:     rts

; ---- stack ------------------------------------------------------------------

; Push tmp2 (hi) / tmp (lo).
push16:
        lda sp_lo
        bne :+
        dec sp_hi
:       dec sp_lo
        lda sp_lo
        sta ml
        lda sp_hi
        sta mh
        lda tmp2
        jsr wr
        lda sp_lo
        bne :+
        dec sp_hi
:       dec sp_lo
        lda sp_lo
        sta ml
        lda sp_hi
        sta mh
        lda tmp
        jmp wr

; Pop into tmp (lo) / tmp2 (hi).
pop16:
        lda sp_lo
        sta ml
        lda sp_hi
        sta mh
        jsr rd
        sta tmp
        inc sp_lo
        bne :+
        inc sp_hi
:       lda sp_lo
        sta ml
        lda sp_hi
        sta mh
        jsr rd
        sta tmp2
        inc sp_lo
        bne :+
        inc sp_hi
:       rts

push_pc:
        lda pcl
        sta tmp
        lda pc_page
        sta tmp2
        jmp push16

; ---- helpers for the handlers -------------------------------------------------

; Relative jump by the signed offset in A.
jr_do:
        tax
        clc
        adc pcl
        sta pcl
        txa
        bmi @neg
        bcc @same
        inc pc_page
        jsr pc_resolve
        NEXT
@neg:   bcs @same
        dec pc_page
        jsr pc_resolve
@same:  NEXT

; Fetch a 16-bit immediate into tmp3 (lo) / tmp4 (hi).
fetch16:
        FETCH
        sta tmp3
        FETCH
        sta tmp4
        rts

; Call tmp3/tmp4.
do_call:
        jsr push_pc
        lda tmp3
        sta tmp
        lda tmp4
        sta tmp2
        jsr goto_t
        NEXT

do_ret:
        jsr pop16
        jsr goto_t
        NEXT

; ---- 8-bit increments / decrements ------------------------------------------

.macro INC8 reg
        inc reg
        lda reg
        sta zv
        and #$0F
        cmp #1                  ; C=0 iff low nibble became 0 (half carry)
        lda #0
        sbc #0
        sta fh
        lda #0
        sta fn
        NEXT
.endmacro

.macro DEC8 reg
        dec reg
        lda reg
        sta zv
        and #$0F
        cmp #$0F                ; C=1 iff low nibble became $F (half borrow)
        lda #0
        rol
        sta fh
        lda #1
        sta fn
        NEXT
.endmacro

.macro INC16 lo, hi
        inc lo
        bne :+
        inc hi
:       NEXT
.endmacro

.macro DEC16 lo, hi
        lda lo
        bne :+
        dec hi
:       dec lo
        NEXT
.endmacro

.macro ADDHL lo, hi
        clc
        lda rL
        adc lo
        sta rL
        lda rH
        sta tmp
        adc hi
        sta rH
        eor tmp
        eor hi
        and #$10
        sta fh
        lda #0
        rol
        sta fc
        lda #0
        sta fn
        NEXT
.endmacro

.macro LDRR16 lo, hi
        FETCH
        sta lo
        FETCH
        sta hi
        NEXT
.endmacro

; ---- opcodes $00-$3F --------------------------------------------------------

op_00:  NEXT                                    ; NOP
op_01:  LDRR16 rC, rB                           ; LD BC,d16
op_02:  lda rC                                  ; LD (BC),A
        sta ml
        lda rB
        sta mh
        lda rA
        jsr wr
        NEXT
op_03:  INC16 rC, rB
op_04:  INC8 rB
op_05:  DEC8 rB
op_06:  FETCH                                   ; LD B,d8
        sta rB
        NEXT
op_07:  lda rA                                  ; RLCA
        cmp #$80
        rol
        sta rA
rot_a_flags:
        lda #0
        rol
        sta fc
        lda #1
        sta zv
        lda #0
        sta fn
        sta fh
        NEXT
op_08:  jsr fetch16                             ; LD (a16),SP
        lda tmp3
        sta ml
        lda tmp4
        sta mh
        lda sp_lo
        jsr wr
        inc ml
        bne :+
        inc mh
:       lda sp_hi
        jsr wr
        NEXT
op_09:  ADDHL rC, rB
op_0A:  lda rC                                  ; LD A,(BC)
        sta ml
        lda rB
        sta mh
        jsr rd
        sta rA
        NEXT
op_0B:  DEC16 rC, rB
op_0C:  INC8 rC
op_0D:  DEC8 rC
op_0E:  FETCH
        sta rC
        NEXT
op_0F:  lda rA                                  ; RRCA
        lsr
        lda rA
        ror
        sta rA
        jmp rot_a_flags

op_10:  FETCH                                   ; STOP (treated as NOP)
        NEXT
op_11:  LDRR16 rE, rD
op_12:  lda rE                                  ; LD (DE),A
        sta ml
        lda rD
        sta mh
        lda rA
        jsr wr
        NEXT
op_13:  INC16 rE, rD
op_14:  INC8 rD
op_15:  DEC8 rD
op_16:  FETCH
        sta rD
        NEXT
op_17:  lda fc                                  ; RLA
        lsr
        lda rA
        rol
        sta rA
        jmp rot_a_flags
op_18:  FETCH                                   ; JR e
.ifdef TARGET_SIM
        cmp #$FE                                ; "jr -2" = test finished
        bne :+
        jmp sim_done
:
.endif
        jmp jr_do
op_19:  ADDHL rE, rD
op_1A:  lda rE                                  ; LD A,(DE)
        sta ml
        lda rD
        sta mh
        jsr rd
        sta rA
        NEXT
op_1B:  DEC16 rE, rD
op_1C:  INC8 rE
op_1D:  DEC8 rE
op_1E:  FETCH
        sta rE
        NEXT
op_1F:  lda fc                                  ; RRA
        lsr
        lda rA
        ror
        sta rA
        jmp rot_a_flags

op_20:  FETCH                                   ; JR NZ
        ldx zv
        beq :+
        jmp jr_taken
:       NEXT
jr_taken:
        dec budget
        jmp jr_do
op_21:  LDRR16 rL, rH
op_22:  lda rA                                  ; LD (HL+),A
        jsr wr_hl
        INC16 rL, rH
op_23:  INC16 rL, rH
op_24:  INC8 rH
op_25:  DEC8 rH
op_26:  FETCH
        sta rH
        NEXT
op_27:  lda fn                                  ; DAA
        bne @sub
        lda fc
        bne @a60
        lda rA
        cmp #$9A
        bcc @c6
@a60:   lda rA
        clc
        adc #$60
        sta rA
        lda #1
        sta fc
@c6:    lda fh
        bne @a6
        lda rA
        and #$0F
        cmp #$0A
        bcc @done
@a6:    lda rA
        clc
        adc #6
        sta rA
        jmp @done
@sub:   lda fc
        beq @s6
        lda rA
        sec
        sbc #$60
        sta rA
@s6:    lda fh
        beq @done
        lda rA
        sec
        sbc #6
        sta rA
@done:  lda rA
        sta zv
        lda #0
        sta fh
        NEXT
op_28:  FETCH                                   ; JR Z
        ldx zv
        bne :+
        jmp jr_taken
:       NEXT
op_29:  clc                                     ; ADD HL,HL
        lda rL
        adc rL
        sta rL
        lda rH
        adc rH
        sta rH
        and #$10
        sta fh
        lda #0
        rol
        sta fc
        lda #0
        sta fn
        NEXT
op_2A:  READ_HL                                 ; LD A,(HL+)
        sta rA
        INC16 rL, rH
op_2B:  DEC16 rL, rH
op_2C:  INC8 rL
op_2D:  DEC8 rL
op_2E:  FETCH
        sta rL
        NEXT
op_2F:  lda rA                                  ; CPL
        eor #$FF
        sta rA
        lda #1
        sta fn
        sta fh
        NEXT

op_30:  FETCH                                   ; JR NC
        ldx fc
        bne :+
        jmp jr_taken
:       NEXT
op_31:  LDRR16 sp_lo, sp_hi
op_32:  lda rA                                  ; LD (HL-),A
        jsr wr_hl
        DEC16 rL, rH
op_33:  INC16 sp_lo, sp_hi
op_34:  READ_HL                                 ; INC (HL)
        clc
        adc #1
        sta zv
        tax
        and #$0F
        cmp #1
        lda #0
        sbc #0
        sta fh
        lda #0
        sta fn
        txa
        jsr wr_hl
        NEXT
op_35:  READ_HL                                 ; DEC (HL)
        sec
        sbc #1
        sta zv
        tax
        and #$0F
        cmp #$0F
        lda #0
        rol
        sta fh
        lda #1
        sta fn
        txa
        jsr wr_hl
        NEXT
op_36:  FETCH                                   ; LD (HL),d8
        jsr wr_hl
        NEXT
op_37:  lda #1                                  ; SCF
        sta fc
        lda #0
        sta fn
        sta fh
        NEXT
op_38:  FETCH                                   ; JR C
        ldx fc
        beq :+
        jmp jr_taken
:       NEXT
op_39:  ADDHL sp_lo, sp_hi
op_3A:  READ_HL                                 ; LD A,(HL-)
        sta rA
        DEC16 rL, rH
op_3B:  DEC16 sp_lo, sp_hi
op_3C:  INC8 rA
op_3D:  DEC8 rA
op_3E:  FETCH
        sta rA
        NEXT
op_3F:  lda fc                                  ; CCF
        eor #1
        sta fc
        lda #0
        sta fn
        sta fh
        NEXT

; ---- opcodes $40-$7F: LD r,r' -----------------------------------------------

.repeat 64, I
.ident(.sprintf("op_%02X", $40+I)):
  .if $40+I = $76
        jmp op_halt
  .elseif (I .mod 8) = 6
        READ_HL
        sta R + (I / 8)
        NEXT
  .elseif (I / 8) = 6
        lda R + (I .mod 8)
        jsr wr_hl
        NEXT
  .else
        lda R + (I .mod 8)
        sta R + (I / 8)
        NEXT
  .endif
.endrep

op_halt:
        lda IORAM+$FF
        and IORAM+$0F
        and #$1F
        bne @nohalt
        lda #1
        sta halted
        jmp do_event
@nohalt:
        jsr force_event
        NEXT

; ---- opcodes $80-$BF: ALU A,r -----------------------------------------------

.repeat 64, I
.ident(.sprintf("op_%02X", $80+I)):
  .if (I .mod 8) = 6
        READ_HL
  .else
        lda R + (I .mod 8)
  .endif
  .if (I / 8) = 0
        jmp alu_add
  .elseif (I / 8) = 1
        jmp alu_adc
  .elseif (I / 8) = 2
        jmp alu_sub
  .elseif (I / 8) = 3
        jmp alu_sbc
  .elseif (I / 8) = 4
        jmp alu_and
  .elseif (I / 8) = 5
        jmp alu_xor
  .elseif (I / 8) = 6
        jmp alu_or
  .else
        jmp alu_cp
  .endif
.endrep

alu_add:
        sta tmp
        clc
        adc rA
alu_addsub_flags:
        tax
        eor rA
        eor tmp
        and #$10
        sta fh
        lda #0
        rol
        sta fc
        stx rA
        stx zv
        lda #0
        sta fn
        NEXT

alu_adc:
        sta tmp
        lda fc
        lsr
        lda rA
        adc tmp
        jmp alu_addsub_flags

alu_sub:
        sta tmp
        lda rA
        sec
        sbc tmp
alu_sub_flags:
        tax
        eor rA
        eor tmp
        and #$10
        sta fh
        lda #0
        rol
        eor #1
        sta fc
        stx rA
        stx zv
        lda #1
        sta fn
        NEXT

alu_sbc:
        sta tmp
        lda fc
        eor #1
        lsr
        lda rA
        sbc tmp
        jmp alu_sub_flags

alu_and:
        and rA
        sta rA
        sta zv
        lda #0
        sta fn
        sta fc
        lda #1
        sta fh
        NEXT

alu_xor:
        eor rA
        jmp alu_logic

alu_or:
        ora rA
alu_logic:
        sta rA
        sta zv
        lda #0
        sta fn
        sta fh
        sta fc
        NEXT

alu_cp:
        sta tmp
        lda rA
        sec
        sbc tmp
        tax
        eor rA
        eor tmp
        and #$10
        sta fh
        lda #0
        rol
        eor #1
        sta fc
        stx zv
        lda #1
        sta fn
        NEXT

; ---- opcodes $C0-$FF ----------------------------------------------------------

ret_taken:
        CYCLES 3
        jmp do_ret

op_C0:  lda zv                                  ; RET NZ
        beq :+
        jmp ret_taken
:       NEXT
op_C1:  jsr pop16                               ; POP BC
        lda tmp
        sta rC
        lda tmp2
        sta rB
        NEXT
op_C2:  jsr fetch16                             ; JP NZ
        lda zv
        beq :+
        jmp jp_taken
:       NEXT
jp_taken:
        dec budget
op_jp_t34:
        lda tmp3
        sta tmp
        lda tmp4
        sta tmp2
        jsr goto_t
        NEXT
op_C3:  jsr fetch16                             ; JP a16
        jmp op_jp_t34
op_C4:  jsr fetch16                             ; CALL NZ
        lda zv
        beq :+
        jmp call_taken
:       NEXT
call_taken:
        CYCLES 3
        jmp do_call
op_C5:  lda rC                                  ; PUSH BC
        sta tmp
        lda rB
        sta tmp2
        jsr push16
        NEXT
op_C6:  FETCH
        jmp alu_add

.macro RST vec
        jsr push_pc
        lda #vec
        sta tmp
        lda #0
        sta tmp2
        jsr goto_t
        NEXT
.endmacro

op_C7:  RST $00
op_C8:  lda zv                                  ; RET Z
        bne :+
        jmp ret_taken
:       NEXT
op_C9:  jmp do_ret
op_CA:  jsr fetch16                             ; JP Z
        lda zv
        bne :+
        jmp jp_taken
:       NEXT
op_CB:  jmp cb_prefix
op_CC:  jsr fetch16                             ; CALL Z
        lda zv
        bne :+
        jmp call_taken
:       NEXT
op_CD:  jsr fetch16
        jmp do_call
op_CE:  FETCH
        jmp alu_adc
op_CF:  RST $08

op_D0:  lda fc                                  ; RET NC
        bne :+
        jmp ret_taken
:       NEXT
op_D1:  jsr pop16
        lda tmp
        sta rE
        lda tmp2
        sta rD
        NEXT
op_D2:  jsr fetch16                             ; JP NC
        lda fc
        bne :+
        jmp jp_taken
:       NEXT
op_D4:  jsr fetch16                             ; CALL NC
        lda fc
        bne :+
        jmp call_taken
:       NEXT
op_D5:  lda rE
        sta tmp
        lda rD
        sta tmp2
        jsr push16
        NEXT
op_D6:  FETCH
        jmp alu_sub
op_D7:  RST $10
op_D8:  lda fc                                  ; RET C
        beq :+
        jmp ret_taken2
:       NEXT
ret_taken2:
        jmp ret_taken
op_D9:  lda #1                                  ; RETI
        sta ime
        jsr pop16
        jsr goto_t
        jsr force_event
        NEXT
op_DA:  jsr fetch16                             ; JP C
        lda fc
        beq :+
        jmp jp_taken2
:       NEXT
jp_taken2:
        jmp jp_taken
op_DC:  jsr fetch16                             ; CALL C
        lda fc
        beq :+
        jmp call_taken2
:       NEXT
call_taken2:
        jmp call_taken
op_DE:  FETCH
        jmp alu_sbc
op_DF:  RST $18

op_E0:  FETCH                                   ; LDH (a8),A
        tax
ldh_store:
        bpl @io
        cpx #$FF
        beq @io
        lda rA
        sta IORAM,x
        NEXT
@io:    lda rA
        jsr io_write_x
        NEXT
op_E1:  jsr pop16
        lda tmp
        sta rL
        lda tmp2
        sta rH
        NEXT
op_E2:  ldx rC                                  ; LD (C),A
        jmp ldh_store
op_E5:  lda rL
        sta tmp
        lda rH
        sta tmp2
        jsr push16
        NEXT
op_E6:  FETCH
        jmp alu_and
op_E7:  RST $20
op_E8:  jsr sp_plus_e                           ; ADD SP,e
        stx sp_lo
        sta sp_hi
        NEXT
op_E9:  lda rL                                  ; JP HL
        sta tmp
        lda rH
        sta tmp2
        jsr goto_t
        NEXT
op_EA:  jsr fetch16                             ; LD (a16),A
        lda tmp3
        sta ml
        lda tmp4
        sta mh
        lda rA
        jsr wr
        NEXT
op_EE:  FETCH
        jmp alu_xor
op_EF:  RST $28

op_F0:  FETCH                                   ; LDH A,(a8)
        tax
ldh_load:
        bpl @io
        lda IORAM,x
        sta rA
        NEXT
@io:    jsr io_read_x
        sta rA
        NEXT
op_F1:  jsr pop16                               ; POP AF
        lda tmp2
        sta rA
        lda tmp
        and #$80
        eor #$80
        sta zv
        lda tmp
        and #$40
        sta fn
        lda tmp
        and #$20
        sta fh
        lda tmp
        lsr
        lsr
        lsr
        lsr
        and #1
        sta fc
        NEXT
op_F2:  ldx rC                                  ; LD A,(C)
        jmp ldh_load
op_F3:  lda #0                                  ; DI
        sta ime
        sta ei_pend
        NEXT
op_F5:  jsr pack_f                              ; PUSH AF
        sta tmp
        lda rA
        sta tmp2
        jsr push16
        NEXT
op_F6:  FETCH
        jmp alu_or
op_F7:  RST $30
op_F8:  jsr sp_plus_e                           ; LD HL,SP+e
        stx rL
        sta rH
        NEXT
op_F9:  lda rL                                  ; LD SP,HL
        sta sp_lo
        lda rH
        sta sp_hi
        NEXT
op_FA:  jsr fetch16                             ; LD A,(a16)
        lda tmp3
        sta ml
        lda tmp4
        sta mh
        jsr rd
        sta rA
        NEXT
op_FB:  lda ime                                 ; EI
        bne :+
        lda #1
        sta ei_pend
        jsr force_event
:       NEXT
op_FE:  FETCH
        jmp alu_cp
op_FF:  RST $38

op_ill:                                         ; undefined opcode: CPU locks up
.ifdef TARGET_SIM
        jmp sim_illegal
.else
        dec pcl                                 ; spin on the same opcode
        NEXT
.endif
op_D3 = op_ill
op_DB = op_ill
op_DD = op_ill
op_E3 = op_ill
op_E4 = op_ill
op_EB = op_ill
op_EC = op_ill
op_ED = op_ill
op_F4 = op_ill
op_FC = op_ill
op_FD = op_ill

; SP + signed immediate -> X (lo), A (hi), with ADD SP,e flags.
sp_plus_e:
        FETCH
        sta tmp
        clc
        adc sp_lo
        tax
        eor sp_lo
        eor tmp
        and #$10
        sta fh
        lda #0
        rol
        sta fc
        lda tmp
        and #$80
        beq :+
        lda #$FF
:       sta tmp
        lda fc
        lsr
        lda sp_hi
        adc tmp
        ldy #1
        sty zv
        ldy #0
        sty fn
        rts

; Pack the flags into an F register value in A.
pack_f:
        lda #0
        ldx zv
        bne :+
        ora #$80
:       ldx fn
        beq :+
        ora #$40
:       ldx fh
        beq :+
        ora #$20
:       ldx fc
        beq :+
        ora #$10
:       rts

; ---- CB prefix --------------------------------------------------------------

cb_prefix:
        FETCH
        sta cbop
        and #7
        cmp #6
        beq @hl
        tay
        sty cbreg
        lda a:R,y
        jsr cb_exec
        ldy cbreg
        sta a:R,y
        NEXT
@hl:    READ_HL
        ldx cbop
        cpx #$40
        bcc @rw
        cpx #$80
        bcs @rw
        jsr cb_exec                             ; BIT n,(HL): read only
        dec budget
        NEXT
@rw:    jsr cb_exec
        jsr wr_hl
        CYCLES 2
        NEXT

; A = operand, cbop = opcode. Returns the result in A.
cb_exec:
        sta cbval
        lda cbop
        lsr
        lsr
        lsr
        tax
        lda cbtab_lo,x
        sta @j+1
        lda cbtab_hi,x
        sta @j+2
        lda cbval
@j:     jmp $0000

; Common flag tail for shifts/rotates: A = result, C = carry out.
cb_fl:  tax
        lda #0
        rol
        sta fc
        lda #0
        sta fn
        sta fh
        stx zv
        txa
        rts

cb_rlc: cmp #$80
        rol
        jmp cb_fl
cb_rrc: lsr
        lda cbval
        ror
        jmp cb_fl
cb_rl:  lda fc
        lsr
        lda cbval
        rol
        jmp cb_fl
cb_rr:  lda fc
        lsr
        lda cbval
        ror
        jmp cb_fl
cb_sla: asl
        jmp cb_fl
cb_sra: cmp #$80
        ror
        jmp cb_fl
cb_swap:
        asl
        adc #$80
        rol
        asl
        adc #$80
        rol
        clc
        jmp cb_fl
cb_srl: lsr
        jmp cb_fl

.repeat 8, B
.ident(.sprintf("cb_bit%d", B)):
        and #(1 << B)
        sta zv
        lda #0
        sta fn
        lda #1
        sta fh
        lda cbval
        rts
.ident(.sprintf("cb_res%d", B)):
        and #<~(1 << B)
        rts
.ident(.sprintf("cb_set%d", B)):
        ora #(1 << B)
        rts
.endrep
