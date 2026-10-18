; ---------------------------------------------------------------------------
; Memory layout per target. All GB memory regions are page aligned.
; ---------------------------------------------------------------------------

RMAP    = $0200         ; GB page -> C64 page for reads (0 = slow path)
WMAP    = $0300         ; GB page -> C64 page for writes (0 = slow path)
LOWTAB  = $0400         ; cache slot tables and GBC palette tables (1 KB)
MAXSLOTS = 128

VRAM    = $4000         ; GB $8000-$9FFF, VRAM bank 0
WRAM    = $6000         ; GB $C000-$DFFF ($7000 = switchable bank on GBC)
VRAM1   = $8000         ; GBC: VRAM bank 1. DMG: extra ROM cache slots

.ifdef TARGET_SIM
IORAM   = $A000         ; GB $FF00-$FFFF (I/O registers, HRAM, IE)
OAMPG   = $A100         ; GB $FE00-$FEFF
FFPG    = $A200         ; page filled with $FF for unmapped reads
CSTACK  = $A400         ; cc65 parameter stack top (grows down into $A300)
SLOTS0  = $A400         ; ROM page cache run
.ifdef RENDER
NSLOTS0 = $C8 - $A4     ; render benchmark: room for screen, tables and bitmap
SCREEN  = $C800
COLRAM  = $CC00
RTAB    = $D000         ; renderer tables
BITMAP  = $E000
TOP_ROW = 3
.else
NSLOTS0 = $DF - $A4
SRAM_RES = $DF00        ; cartridge RAM kept resident (one bank, no REU in sim65)
.endif
NSLOTS1 = 0
SLOTS1  = 0
.endif

.ifdef TARGET_C64
SLOTS0  = $A000         ; ROM cache run 1: $A000-$BFFF
NSLOTS0 = 32
IORAM   = $C000
OAMPG   = $C100
FFPG    = $C200
HICODE  = $C300         ; extra resident code (sound), $C300-$C7FF
SLOTS1  = $C800         ; ROM cache run 2: $C800-$CFFF
NSLOTS1 = 8
SCREEN  = $D000         ; VIC screen matrix, RAM under I/O (VIC bank 3 sees it)
COLRAM  = $D800
RTAB    = $D400         ; renderer tables, RAM under I/O ($D400-$DFFF)
BITMAP  = $E000         ; VIC bitmap (bank 3), $E000-$FF3F
TOP_ROW = 3             ; first bitmap cell row used by the GB screen
SRAM_CACHED = 1         ; cartridge RAM lives in the REU, paged through the cache
WRAM_BANKS = 1          ; GBC WRAM banks 1-7 swapped through the REU
.endif

NSLOTS_A = NSLOTS0 + NSLOTS1    ; slots available in every mode
NSLOTS_B = 32                   ; $8000-$9FFF, DMG mode only

; REU layout: ROM at 0, GBC WRAM banks at $FC0000, cartridge RAM at $FE0000
REU_WRAM = $FC
REU_SRAM = $FE

; LOWTAB layout
slot_page = LOWTAB + $000       ; C64 page of each cache slot
slot_klo  = LOWTAB + $080       ; REU page number held by the slot
slot_khi  = LOWTAB + $100       ; ($FF = empty)
slot_gb   = LOWTAB + $180       ; GB page mapped to the slot ($FF = none)
palram    = LOWTAB + $200       ; GBC palette RAM: 64 bytes BG, 64 bytes OBJ
pal_c64   = LOWTAB + $280       ; nearest C64 color per palette entry (64)
pal_scr   = LOWTAB + $2C0       ; BG palette -> screen RAM byte (8)
pal_col   = LOWTAB + $2C8       ; BG palette -> color RAM nibble (8)
c64rgb    = LOWTAB + $2D0       ; C64 palette, 5-bit R,G,B (48)
cs1       = LOWTAB + $300       ; GBC: C64 colors of the current cell row's slots 1-3 (40 each)
cs2       = LOWTAB + $328
cs3       = LOWTAB + $350
sqtab_lo  = LOWTAB + $3C0       ; squares 0..31 (32 + 32)
sqtab_hi  = LOWTAB + $3E0
