; ---------------------------------------------------------------------------
; ROM file browser using the Ultimate Command Interface (UCI), DOS target.
; Lists directories and .gb/.gbc files from USB/SD, loads the chosen ROM
; straight into the REU with DOS_CMD_LOAD_REU.
;
; Runs before the emulator, so it borrows the renderer's zero page and keeps
; its directory listing in the (not yet used) GB memory area.
; ---------------------------------------------------------------------------

UCI_CTRL   = $DF1C      ; write: control, read: status
UCI_CMD    = $DF1D      ; write: command data, read: identification ($C9)
UCI_DATA   = $DF1E
UCI_STATUS = $DF1F

TXTSCR     = $0400
ENTRIES    = $4000      ; 64 bytes per entry: attr, name (0-terminated)
MAXENT     = 255
LISTROW    = 3
LISTLEN    = 20

b_scr   = r_dst         ; 2: screen pointer
b_ptr   = r_map         ; 2: entry pointer
b_cnt   = r_fine        ; number of entries
b_sel   = r_mx          ; selected entry
b_top   = r_col         ; first visible entry
b_row   = r_end
b_key   = r_lo          ; current input bits
b_old   = r_hi          ; previous input bits
b_rep   = r_t           ; key repeat counter
b_len   = r_n

; input bits
IN_UP   = 1
IN_DOWN = 2
IN_FIRE = 4
IN_BACK = 8

.segment "BROWSER"

; Buffers in GB memory that is not used before the emulator starts
cmdbuf   = VRAM1                ; 72
respbuf  = VRAM1+$100           ; 256

; Returns C=1 when a ROM was loaded (or one is assumed to be in the REU).
browser:
        lda #0                  ; no save file until a ROM is loaded
        sta sav_name
        sta sav_loaded
        jsr text_init
        lda UCI_CMD
        and #$7F
        cmp #$49
        beq @uci
.ifdef DIAGTEST
        jsr diag
.endif
        lda #<msg_nouci         ; no UCI: run the ROM already in the REU,
        ldx #>msg_nouci         ; if there is one (Nintendo logo at $0104)
        ldy #10
        jsr print_at
@chk:   jsr reu_has_rom
        bcs :+
        lda #<msg_noreu
        ldx #>msg_noreu
        ldy #12
        jsr print_at
        lda #<msg_noreu2
        ldx #>msg_noreu2
        ldy #13
        jsr print_at
        jsr wait_fire
        jmp @chk
:       rts
@uci:   lda #$04                ; abort anything left over, clear errors
        sta UCI_CTRL
        lda #$08
        sta UCI_CTRL
        lda #$02
        sta UCI_CTRL
        lda #$17                ; go to the home directory set in the menu
        jsr dos_simple

@reload:
        jsr read_dir
        lda #0
        sta b_sel
        sta b_top
@redraw:
        jsr draw_list
@input: jsr get_input
        lda b_key
        and #IN_DOWN
        beq :+
        ldx b_sel
        inx
        cpx b_cnt
        bcs @input
        stx b_sel
        jmp @scroll
:       lda b_key
        and #IN_UP
        beq :+
        lda b_sel
        beq @input
        dec b_sel
        jmp @scroll
:       lda b_key
        and #IN_BACK
        beq :+
        lda #0                  ; entry 0 is always ".."
        sta b_sel
        jmp @open
:       lda b_key
        and #IN_FIRE
        beq @input
@open:  lda b_sel
        jsr entry_ptr
        ldy #0
        lda (b_ptr),y
        and #$10                ; directory
        beq @file
        jsr chdir_entry
        jmp @reload
@file:  jsr load_entry
        bcc @redraw             ; load failed: message shown, stay
        sec
        rts
@scroll:
        lda b_sel               ; keep the selection visible
        cmp b_top
        bcs :+
        sta b_top
:       lda b_top
        clc
        adc #LISTLEN-1
        cmp b_sel
        bcs :+
        lda b_sel
        sec
        sbc #LISTLEN-1
        sta b_top
:       jmp @redraw

; C=1 if the REU holds a Game Boy ROM (checks the first logo bytes).
reu_has_rom:
        lda #<respbuf
        sta $DF02
        lda #>respbuf
        sta $DF03
        lda #$00
        sta $DF04
        sta $DF06
        sta $DF08
        sta $DF0A
        lda #$01
        sta $DF05               ; REU $000100
        lda #8
        sta $DF07
        lda #$91
        sta $DF01
        lda respbuf+4
        cmp #$CE
        bne :+
        lda respbuf+5
        cmp #$ED
        bne :+
        sec
        rts
:       clc
        rts

; ---- UCI protocol ---------------------------------------------------------

; Push X bytes of cmdbuf and wait until the reply (data state) is ready.
uci_send:
        ldy #0
:       lda cmdbuf,y
        sta UCI_CMD
        iny
        dex
        bne :-
        lda #$01                ; PUSH_CMD
        sta UCI_CTRL
uci_wait:
:       lda UCI_CTRL
        and #$20                ; state 10/11 = data last/more
        beq :-
        rts

; Read the data channel into respbuf (zero terminated). Y = length.
uci_data:
        ldy #0
:       lda UCI_CTRL
        bpl :+
        lda UCI_DATA
        sta respbuf,y
        iny
        cpy #255
        bne :-
:       lda #0
        sta respbuf,y
        rts

; Read the status channel into respbuf. Returns Z=1 when it starts with "00".
uci_status:
        ldy #0
:       lda UCI_CTRL
        and #$40
        beq :+
        lda UCI_STATUS
        sta respbuf,y
        iny
        cpy #255
        bne :-
:       lda #0
        sta respbuf,y
        lda respbuf
        cmp #'0'
        bne :+
        lda respbuf+1
        cmp #'0'
:       rts

; Accept the current reply. Returns Z=1 when the protocol is idle again.
uci_accept:
        lda #$02                ; DATA_ACC
        sta UCI_CTRL
:       lda UCI_CTRL
        and #$30
        cmp #$10                ; busy: wait for the next packet
        beq :-
        cmp #0
        rts

; DOS command with no arguments: A = command. Returns Z=1 on "00,OK".
dos_simple:
        ldx #2
dos_cmd:                        ; cmdbuf+2.. already filled, X = total length
        sta cmdbuf+1
        lda #$01                ; DOS target
        sta cmdbuf
        jsr uci_send
        jsr uci_data
        jsr uci_status
        php
        jsr uci_accept
        plp
        rts

; DOS command A with the name in respbuf-independent string at (b_ptr)+1.
; Extra bytes before the name: cmdbuf+2 .. +2+Y-1 already set, Y = count.
dos_name_cmd:
        pha
        tya
        clc
        adc #2
        tax                     ; X = cmdbuf index for the name
        ldy #1
:       lda (b_ptr),y
        sta cmdbuf,x
        beq :+
        inx
        iny
        cpy #64
        bne :-
:       pla
        jmp dos_cmd             ; X = length (without the terminator)

; ---- directory ----------------------------------------------------------------

read_dir:
        lda #0
        sta b_cnt
        lda #0                  ; entry 0: ".."
        jsr entry_ptr
        ldy #0
        lda #$10
        sta (b_ptr),y
        iny
        lda #'.'
        sta (b_ptr),y
        iny
        sta (b_ptr),y
        iny
        lda #0
        sta (b_ptr),y
        inc b_cnt

        jsr show_path
        lda #$13                ; open directory
        jsr dos_simple
        lda #$14                ; read directory: one packet per entry
        sta cmdbuf+1
        lda #$01
        sta cmdbuf
        ldx #2
        jsr uci_send
@next:  jsr uci_data
        cpy #2
        bcc @skip
        jsr keep_entry
        bcc @skip
        lda b_cnt
        jsr entry_ptr
        ldy #0
:       lda respbuf,y
        sta (b_ptr),y
        beq :+
        iny
        cpy #63
        bne :-
        lda #0
        sta (b_ptr),y
:       inc b_cnt
        lda b_cnt
        cmp #MAXENT
        bcs @done
@skip:  jsr uci_accept
        bne @next
        rts
@done:  lda #$04                ; too many entries: abort the transfer
        sta UCI_CTRL
        jmp uci_accept

; C=1 if respbuf (attr, name) is a directory or a .gb/.gbc file.
keep_entry:
        lda respbuf
        and #$10
        bne @yes
        dey                     ; Y = length; check the extension
        lda respbuf,y
        ora #$20
        cmp #'c'
        bne :+
        dey
        lda respbuf,y
        ora #$20
:       cmp #'b'
        bne @no
        dey
        lda respbuf,y
        ora #$20
        cmp #'g'
        bne @no
        dey
        lda respbuf,y
        cmp #'.'
        bne @no
@yes:   sec
        rts
@no:    clc
        rts

chdir_entry:
        lda #$11
        ldy #0
        jmp dos_name_cmd

show_path:
        lda #$12                ; get path
        sta cmdbuf+1
        lda #$01
        sta cmdbuf
        ldx #2
        jsr uci_send
        jsr uci_data
        jsr uci_status
        jsr uci_accept
        ldx #1
        jsr clear_row
        lda #<respbuf
        ldx #>respbuf
        ldy #1
        jmp print_at

; Open the selected file and load it into the REU at address 0.
load_entry:
        ldx #24
        jsr clear_row
        lda #<msg_loading
        ldx #>msg_loading
        ldy #24
        jsr print_at
        lda #$01                ; FA_READ
        sta cmdbuf+2
        lda #$02                ; open the ROM
        ldy #1
        jsr dos_name_cmd
        bne @fail
        lda #0                  ; ROM -> REU $000000
        jsr load_open
        bne @fail
        jsr sram_clear          ; clean RAM area (also when the save is short)
        jsr make_savname        ; save file next to it? -> REU $FE0000
        lda #<(sav_name-1)
        sta b_ptr
        lda #>(sav_name-1)
        sta b_ptr+1
        lda #$01
        sta cmdbuf+2
        lda #$02
        ldy #1
        jsr dos_name_cmd
        bne @ok                 ; no save file yet
        lda #REU_SRAM
        jsr load_open
        bne @ok
        lda #1
        sta sav_loaded
@ok:    sec
        rts
@fail:  ldx #24
        jsr clear_row
        lda #<respbuf
        ldx #>respbuf
        ldy #24
        jsr print_at
        clc
        rts

; Load the opened file into the REU at bank A, offset 0, and close it.
; Z=1 on success.
load_open:
        pha
        lda #$07                ; file info: size in bytes 0-3
        sta cmdbuf+1
        lda #$01
        sta cmdbuf
        ldx #2
        jsr uci_send
        jsr uci_data
        lda respbuf
        sta cmdbuf+6
        lda respbuf+1
        sta cmdbuf+7
        lda respbuf+2
        sta cmdbuf+8
        lda #0
        sta cmdbuf+9
        jsr uci_status
        jsr uci_accept
        pla
        sta cmdbuf+4            ; REU address bank:00:00
        lda #0
        sta cmdbuf+2
        sta cmdbuf+3
        sta cmdbuf+5
        lda #$21                ; load REU
        ldx #10
        jsr dos_cmd
        php
        lda #$03                ; close file
        jsr dos_simple
        plp
        rts

; b_ptr = ENTRIES + A * 64
entry_ptr:
        pha
        lsr
        lsr
        clc
        adc #>ENTRIES
        sta b_ptr+1
        pla
        and #3
        lsr
        ror
        ror
        sta b_ptr
        rts

; ---- screen -------------------------------------------------------------------

text_init:
        lda #$1B
        sta $D011
        lda #$08
        sta $D016
        lda $DD02
        ora #3
        sta $DD02
        lda $DD00
        ora #3                  ; VIC bank 0
        sta $DD00
        lda #$16                ; screen $0400, lower case characters
        sta $D018
        lda #11
        sta $D020
        lda #0
        sta $D021
        lda #>TXTSCR
        sta ptr+1
        lda #$20
        ldx #4
        jsr fill_pages
        lda #$D8
        sta ptr+1
        lda #15
        ldx #4
        jsr fill_pages
        lda #<msg_title
        ldx #>msg_title
        ldy #0
        jsr print_at
        lda #<msg_help
        ldx #>msg_help
        ldy #23
        jmp print_at

draw_list:
        lda #0
        sta b_row
@row:   lda b_row
        clc
        adc #LISTROW
        tax
        jsr clear_row
        lda b_row
        clc
        adc b_top
        cmp b_cnt
        bcs @nx
        pha
        jsr entry_ptr
        lda b_ptr
        clc
        adc #1
        ldx b_ptr+1
        bcc :+
        inx
:       pha
        lda b_row
        clc
        adc #LISTROW
        tay
        pla
        jsr print_at_col2
        pla
        cmp b_sel
        bne @nx
        ldy #39                 ; highlight the selection (reverse video)
:       lda (b_scr),y
        ora #$80
        sta (b_scr),y
        dey
        bpl :-
@nx:    inc b_row
        lda b_row
        cmp #LISTLEN
        bne @row
        rts

; X = row: clear it and leave b_scr pointing at it.
clear_row:
        jsr row_ptr
        lda #$20
        ldy #39
:       sta (b_scr),y
        dey
        bpl :-
        rts

row_ptr:
        lda #0
        sta b_scr+1
        txa
        sta b_scr               ; row * 40 = row * 32 + row * 8
        asl
        asl
        asl
        sta etmp
        lda b_scr
        asl
        asl
        asl
        asl
        rol b_scr+1
        asl
        rol b_scr+1
        clc
        adc etmp
        sta b_scr
        lda b_scr+1
        adc #>TXTSCR
        sta b_scr+1
        rts

; Print the ASCII string at A/X on row Y (column 0 or 2).
print_at:
        sta ptr2
        stx ptr2+1
        tya
        tax
        jsr row_ptr
        ldy #0
        beq print_str
print_at_col2_20:               ; row Y, column 20
        sta ptr2
        stx ptr2+1
        tya
        tax
        jsr row_ptr
        ldy #20
        bne print_str
print_at_col2:
        sta ptr2
        stx ptr2+1
        tya
        tax
        jsr row_ptr
        ldy #2
print_str:
        sty b_len
        ldy #0
@c:     lda (ptr2),y
        beq @r
        jsr ascii_to_screen
        sty etmp
        ldy b_len
        cpy #40
        bcs @r
        sta (b_scr),y
        inc b_len
        ldy etmp
        iny
        bne @c
@r:     rts

ascii_to_screen:
        cmp #$60
        bcc :+
        and #$1F                ; a-z -> 1-26
        rts
:       cmp #$40
        bcc :+
        cmp #$41
        bcc @at
        cmp #$5B
        bcc :+                  ; A-Z stay (upper case in this charset)
@at:    and #$1F
:       rts

; ---- input --------------------------------------------------------------------

; Wait for the next frame, then return b_key with new presses / repeats.
get_input:
@wait:  lda $D012               ; one frame
        cmp #250
        bne @wait
:       lda $D012
        cmp #250
        beq :-
        jsr diag_key
        jsr scan_input
        cmp b_old
        beq @held
        sta b_old
        lda #20                 ; initial repeat delay
        sta b_rep
        lda b_old
        sta b_key
        rts
@held:  lda #0
        sta b_key
        lda b_old
        and #IN_UP|IN_DOWN
        beq @wait
        dec b_rep
        bne @wait
        lda #3
        sta b_rep
        lda b_old
        and #IN_UP|IN_DOWN
        sta b_key
        rts

; A = input bits from joystick 2 and keyboard.
scan_input:
        lda #$FF
        sta $DC02
        lda #0
        sta $DC03
        lda #$FF
        sta $DC00
        lda $DC00
        eor #$FF
        tax
        lda #0
        sta etmp
        txa
        and #1
        beq :+
        lda #IN_UP
        sta etmp
:       txa
        and #2
        beq :+
        lda etmp
        ora #IN_DOWN
        sta etmp
:       txa
        and #$10
        beq :+
        lda etmp
        ora #IN_FIRE
        sta etmp
:       lda #$FE                ; column 0: RETURN (row 1), CRSR DOWN (row 7)
        sta $DC00
        lda $DC01
        tax
        and #$02
        bne :+
        lda etmp
        ora #IN_FIRE
        sta etmp
:       txa
        and #$80
        bne @nodn
        lda #$FD                ; with left SHIFT: up
        sta $DC00
        lda $DC01
        and #$80
        bne :+
        lda etmp
        ora #IN_UP
        sta etmp
        jmp @nodn
:       lda etmp
        ora #IN_DOWN
        sta etmp
@nodn:  lda #$7F                ; column 7: <- (row 1) = parent directory
        sta $DC00
        lda $DC01
        and #$02
        bne :+
        lda etmp
        ora #IN_BACK
        sta etmp
:       lda #$FF
        sta $DC00
        lda etmp
        rts

wait_fire:
:       jsr scan_input
        and #IN_FIRE
        bne :-
:       jsr scan_input
        and #IN_FIRE
        beq :-
        rts

msg_title:   .byte "C64GB - Game Boy emulator - choose a ROM", 0
msg_help:    .byte "joy/crsr: move  fire/return: open  ", $5F, ": up", 0
msg_loading: .byte "Loading ROM into REU...", 0
msg_nouci:   .byte "No Ultimate Command Interface found.", 0
msg_noreu:   .byte "Enable it in the Ultimate menu, or load", 0
msg_noreu2:  .byte "a ROM into the REU, then press fire.", 0

.segment "CODE"

.segment "HICODE"              ; (resident; keeps the overlay within 2 KB)
; sav_name = name of the selected entry with its extension replaced by "sav".
make_savname:
        ldx #$FF                ; position of the last "."
        ldy #1
@c:     lda (b_ptr),y
        sta sav_name-1,y
        beq @end
        cmp #'.'
        bne :+
        tya
        tax
:       iny
        cpy #58
        bne @c
@end:   cpx #$FF
        bne :+
        tya                     ; no extension: append "."
        tax
        lda #'.'
        sta sav_name-1,x
:       lda #'s'
        sta sav_name,x
        lda #'a'
        sta sav_name+1,x
        lda #'v'
        sta sav_name+2,x
        lda #0
        sta sav_name+3,x
        rts

.segment "CODE"
