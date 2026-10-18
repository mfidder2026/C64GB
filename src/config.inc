; ---------------------------------------------------------------------------
; Memory layout per target. All GB memory regions are page aligned.
; ---------------------------------------------------------------------------

RMAP    = $0200         ; GB page -> C64 page for reads (0 = slow path)
WMAP    = $0300         ; GB page -> C64 page for writes (0 = slow path)

.ifdef TARGET_SIM
VRAM    = $4000         ; GB $8000-$9FFF
WRAM    = $6000         ; GB $C000-$DFFF
SRAM    = $8000         ; GB $A000-$BFFF (cartridge RAM, one bank)
IORAM   = $A000         ; GB $FF00-$FFFF (I/O registers, HRAM, IE)
OAMPG   = $A100         ; GB $FE00-$FEFF
FFPG    = $A200         ; page filled with $FF for unmapped reads
CSTACK  = $A400         ; cc65 parameter stack top (grows down into $A300)
.ifdef RENDER
SLOTS0  = $A400         ; ROM page cache, bitmap at $E000 for render benchmarks
NSLOTS0 = $E0 - $A4
BITMAP  = $E000
TOP_ROW = 3
.else
SLOTS0  = $A400         ; ROM page cache: one contiguous run of slots
NSLOTS0 = $FF - $A4     ; up to $FEFF ($FFxx is sim65 I/O)
.endif
NSLOTS1 = 0
SLOTS1  = 0
.endif

.ifdef TARGET_C64
VRAM    = $4000
WRAM    = $6000
SRAM    = $8000
SLOTS0  = $A000         ; ROM cache run 1: $A000-$BFFF
NSLOTS0 = 32
IORAM   = $C000
OAMPG   = $C100
FFPG    = $C200
SLOTS1  = $C300         ; ROM cache run 2: $C300-$CFFF
NSLOTS1 = 13
SCREEN  = $D000         ; VIC screen matrix, RAM under I/O (VIC bank 3 sees it)
BITMAP  = $E000         ; VIC bitmap (bank 3), $E000-$FF3F
TOP_ROW = 3             ; first bitmap cell row used by the GB screen
.endif

NSLOTS  = NSLOTS0 + NSLOTS1
