; ---------------------------------------------------------------------------
; Zero page variables
; ---------------------------------------------------------------------------

; GB registers, ordered by the 3-bit register index used in opcodes:
; 0=B 1=C 2=D 3=E 4=H 5=L 6=(HL) 7=A
R       = $02
rB      = R+0
rC      = R+1
rD      = R+2
rE      = R+3
rH      = R+4
rL      = R+5
rA      = R+7

; Flags (lazy): Z is set when zv == 0, others are set when nonzero.
; fc is always 0 or 1.
zv      = $0A
fn      = $0B
fh      = $0C
fc      = $0D

sp_lo   = $0E
sp_hi   = $0F

pcl     = $10           ; GB PC low byte
pcb     = $11           ; 2 bytes: pointer to C64 page holding the PC page (lo=0)
pc_page = $13           ; GB PC high byte

budget  = $14           ; M-cycles left until next event (signed, event when < 0)
slice   = $15           ; value budget had at the last sync

mp      = $16           ; 2 bytes: scratch page pointer (lo always 0)
ml      = $18           ; GB address for rd/wr
mh      = $19

tmp     = $1A
tmp2    = $1B
tmp3    = $1C
tmp4    = $1D

ime     = $1E
halted  = $1F
ei_pend = $20

mclk    = $21           ; 3 bytes: total M-cycles (wraps)
divc    = $24           ; 2 bytes: internal divider in M-cycles (DIV = divc >> 6)

ppu_mode = $26
ly      = $27
ppu_left = $28          ; M-cycles until next PPU mode change (signed)

elapsed = $29

bank_lo  = $2A          ; 2 bytes: ROM bank mapped at $0000-$3FFF
bank_hi  = $2C          ; 2 bytes: ROM bank mapped at $4000-$7FFF
bank_msk = $2E          ; 2 bytes: ROM bank mask
mbc_type = $30          ; 0 none, 1 MBC1, 2 MBC2, 3 MBC3, 5 MBC5
ram_en   = $31
ram_bank = $32
mbc1_mode = $33
mbc1_hi  = $34          ; MBC1 upper 2 bank bits
mbc_lo   = $35          ; selected low bank bits (MBC1 5 bits / MBC3 7 / MBC5 8)
has_sram = $36

clock    = $37          ; cache replacement hand
key_lo   = $38          ; REU page number being looked up
key_hi   = $39

joy_dirs = $3A          ; active high: bit0 R, 1 L, 2 U, 3 D
joy_btns = $3B          ; active high: bit0 A, 1 B, 2 Select, 3 Start

ptr      = $3C          ; 2 bytes general pointer
ptr2     = $3E          ; 2 bytes general pointer

cbop     = $40
cbreg    = $41
cbval    = $42

frame_cnt = $43
frame_skip = $44
bgp_cache = $45         ; BGP value the conversion table was built for
lcdc_old  = $46

miss_pg  = $47          ; rom_miss: GB page being resolved
miss_slot = $48
tmp_b    = $49
etmp     = $4A          ; temporaries for event/io code (never touched by handlers)
etmp2    = $4B
tsub     = $4C          ; 2 bytes: timer sub-counter (divc mod period)
mtmp     = $4E          ; MBC write temporary
sram_cur = $4F          ; cartridge RAM bank currently held in C64 memory
fd_rom   = $50          ; 2 bytes (sim): ROM file descriptor
frames   = $52          ; 2 bytes: frame counter

; renderer (C64 target)
r_dst   = $58           ; 2: bitmap pointer for the current column
r_map   = $5A           ; 2: tile map row pointer
r_tp    = $5C           ; 2: tile data pointer
r_fine  = $5E           ; tile row * 2
r_mx    = $5F           ; tile map column (0-31)
r_col   = $60           ; screen column (0-19)
r_end   = $61           ; last screen column + 1
r_lo    = $62
r_hi    = $63
r_on    = $64           ; render this frame
r_winln = $65           ; window line counter
r_wcol  = $66           ; screen column where the window starts (20 = none)
r_t     = $67
r_line  = $68           ; 2: bitmap address of the current line
r_n     = $6A           ; sprite count
r_pal   = $6B
r_attr  = $6C
r_x     = $6D
r_px    = $6E
r_bg0   = $6F           ; shade of BG color 0 (for sprite priority)
r_q     = $54           ; scratch


csp      = $F0          ; cc65 parameter stack pointer (sim65 paravirt)
