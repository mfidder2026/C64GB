; ---------------------------------------------------------------------------
; Dispatch tables
; ---------------------------------------------------------------------------

.segment "RODATA"

; Base M-cycles per opcode (conditional jumps: not-taken count).
cyctab:
        ;     0 1 2 3 4 5 6 7 8 9 A B C D E F
        .byte 1,3,2,2,1,1,2,1,5,2,2,2,1,1,2,1   ; 0x
        .byte 1,3,2,2,1,1,2,1,3,2,2,2,1,1,2,1   ; 1x
        .byte 2,3,2,2,1,1,2,1,2,2,2,2,1,1,2,1   ; 2x
        .byte 2,3,2,2,3,3,3,1,2,2,2,2,1,1,2,1   ; 3x
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; 4x
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; 5x
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; 6x
        .byte 2,2,2,2,2,2,1,2,1,1,1,1,1,1,2,1   ; 7x
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; 8x
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; 9x
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; Ax
        .byte 1,1,1,1,1,1,2,1,1,1,1,1,1,1,2,1   ; Bx
        .byte 2,3,3,4,3,4,2,4,2,4,3,2,3,6,2,4   ; Cx
        .byte 2,3,3,1,3,4,2,4,2,4,3,1,3,1,2,4   ; Dx
        .byte 3,3,2,1,1,4,2,4,4,1,4,1,1,1,2,4   ; Ex
        .byte 3,3,2,1,1,4,2,4,3,2,4,1,1,1,2,4   ; Fx

optab_lo:
.repeat 256, I
        .byte <.ident(.sprintf("op_%02X", I))
.endrep
optab_hi:
.repeat 256, I
        .byte >.ident(.sprintf("op_%02X", I))
.endrep

.define CBOPS cb_rlc, cb_rrc, cb_rl, cb_rr, cb_sla, cb_sra, cb_swap, cb_srl, cb_bit0, cb_bit1, cb_bit2, cb_bit3, cb_bit4, cb_bit5, cb_bit6, cb_bit7, cb_res0, cb_res1, cb_res2, cb_res3, cb_res4, cb_res5, cb_res6, cb_res7, cb_set0, cb_set1, cb_set2, cb_set3, cb_set4, cb_set5, cb_set6, cb_set7
cbtab_lo:
        .lobytes CBOPS
cbtab_hi:
        .hibytes CBOPS

.segment "BSS"

slot_page:  .res NSLOTS         ; C64 page of each cache slot
slot_klo:   .res NSLOTS         ; REU page number held by the slot
slot_khi:   .res NSLOTS         ; ($FF = empty)
slot_gb:    .res NSLOTS         ; GB page currently mapped to the slot ($FF = none)

.segment "CODE"
