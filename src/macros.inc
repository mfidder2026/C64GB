; ---------------------------------------------------------------------------
; Core macros
; ---------------------------------------------------------------------------

; Continue with the next GB instruction.
.macro NEXT
        jmp loop
.endmacro

; Fetch the byte at GB PC into A and advance PC. Clobbers X, Y.
.macro FETCH
        .local ok
        ldy pcl
        lda (pcb),y
        inc pcl
        bne ok
        jsr pc_cross
ok:
.endmacro

; A = byte at (HL). Clobbers X, Y.
.macro READ_HL
        .local slow, done
        ldx rH
        lda RMAP,x
        beq slow
        sta mp+1
        ldy rL
        lda (mp),y
        jmp done
slow:   jsr rd_hl
done:
.endmacro

; Subtract extra M-cycles (taken branches etc.)
.macro CYCLES n
        lda budget
        sec
        sbc #n
        sta budget
.endmacro
