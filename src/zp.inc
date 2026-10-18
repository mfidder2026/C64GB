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

; GB PC: pcl/pcpg are the operand of the zero page dispatcher's first
; instruction (see cpu.s, segment ZPCODE at $BC)
pcl      = $BD
pcpg     = $BE
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


; GBC state and misc
nslots   = $70          ; cache slots in use
cgb      = $71          ; 1 = running in Game Boy Color mode
dspeed   = $72          ; 1 = CGB double speed
vbk      = $73          ; VRAM bank (0/1)
svbk     = $74          ; WRAM bank at $D000 (1-7)
hdma_src = $75          ; 2 bytes
hdma_dst = $77          ; 2 bytes
hdma_len = $79          ; HBlank DMA blocks left - 1 ($FF = inactive)
pal_dirty = $7A         ; GBC palettes changed since the last conversion
vb_half  = $7B          ; double speed: first half of a VBlank line done
gbg0     = $7C          ; C64 color used for GBC color 0 (global background)
key_save = $7D          ; 2 bytes: key of a page being written back
hptr     = $7F          ; 2 bytes: HDMA source
hptr2    = $81          ; 2 bytes: HDMA destination
r_amap   = $83          ; 2 bytes: GBC attribute map row pointer
r_a      = $85          ; GBC tile attributes
r_prio   = $86          ; sprite pixel priority (bit 7: behind BG colors 1-3)
n_r      = $87          ; color conversion
n_g      = $88
n_b      = $89
n_d      = $8A          ; 2 bytes
n_t      = $8C          ; 2 bytes
n_bd     = $8E          ; 2 bytes
n_bc     = $90
n_i      = $91
r_pc     = $92          ; 2 bytes: conv table pointer
s_ly17   = $94          ; GBC cell color selection
s_r0     = $95
s_r1     = $96
s_um     = $97
s_ox     = $98
s_left   = $99
s_right  = $9A
s_pal    = $9B
s_c      = $9C
s_col    = $9D
s_t      = $9E
s_cell   = $9F
s_j      = $A0
s_u      = $A1
s_tc     = $A2
s_m      = $A3
s_r      = $A4
s_by     = $A5
s_mp     = $A6          ; 2 bytes
s_aa     = $A8
s_pm     = $A9
s_n      = $AA
s_lcell  = $AB          ; sprite pixel color cache
s_lcol   = $AC
s_lbp    = $AD
r_cnt    = $AE          ; columns left
r_finef  = $AF          ; tile row offset for Y-flipped tiles
spal     = $B0          ; sprite color 1-3 -> bit pair (spal+1..spal+3)
trow     = $B3          ; GBC: dist16 rows of sprite colors 1-3 (trow+1..trow+3)
r_cellx  = $B7          ; cell of the current sprite pixel
ev_op    = $BB          ; opcode fetched when an event became due

; $BC-$EF: zero page dispatcher (segment ZPCODE)

csp      = $F0          ; cc65 parameter stack pointer (sim65 paravirt)
