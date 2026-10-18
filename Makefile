# C64GB build
TOOLS   := tools/cc65-src/bin
CA65    := $(TOOLS)/ca65
LD65    := $(TOOLS)/ld65
SIM65   := $(TOOLS)/sim65
X64SC   := tools/vice/bin/x64sc
BUILD   := build
SRC     := $(wildcard src/*.s src/*.inc)
ROM     ?= tests/gb-test-roms/cpu_instrs/individual/06-ld\ r,r.gb

all: $(BUILD)/c64gb.prg $(BUILD)/c64gb-sim.bin

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/c64gb.prg: $(SRC) cfg/c64.cfg | $(BUILD)
	$(CA65) -I src -D TARGET_C64=1 -o $(BUILD)/c64.o -l $(BUILD)/c64.lst src/main_c64.s
	$(LD65) -C cfg/c64.cfg -o $@ -m $(BUILD)/c64.map -Ln $(BUILD)/c64.lbl $(BUILD)/c64.o

$(BUILD)/c64gb-sim.bin: $(SRC) cfg/sim.cfg | $(BUILD)
	$(CA65) -I src -D TARGET_SIM=1 -o $(BUILD)/sim.o -l $(BUILD)/sim.lst src/main_sim.s
	$(LD65) -C cfg/sim.cfg -o $@ -m $(BUILD)/sim.map -Ln $(BUILD)/sim.lbl $(BUILD)/sim.o

# Automated tests (sim65)
test: $(BUILD)/c64gb-sim.bin
	tests/run_blargg.sh tests/gb-test-roms/cpu_instrs/individual/*.gb tests/gb-test-roms/instr_timing/instr_timing.gb

# Run in VICE with ROM loaded into a 16 MB REU
run: $(BUILD)/c64gb.prg
	tools/mkreu.sh "$(ROM)" $(BUILD)/rom.reu
	$(X64SC) -autostartprgmode 1 -reu -reusize 16384 -reuimage $(BUILD)/rom.reu +reuimagerw -autostart $(BUILD)/c64gb.prg

# Send the PRG to a C64 Ultimate over the network: make deploy U64=192.168.1.64
deploy: $(BUILD)/c64gb.prg
	curl -sS -X POST --data-binary @$(BUILD)/c64gb.prg "http://$(U64)/v1/runners:run_prg"

clean:
	rm -rf $(BUILD)

.PHONY: all test run deploy clean

# Benchmark: C64 cycles per GB M-cycle (CPU only, and with rendering every frame)
BENCH_ROM ?= tests/roms/dmg-acid2.gb
bench: | $(BUILD)
	$(CA65) -I src -D TARGET_SIM=1 -D SIM_FRAMES=120 -o $(BUILD)/bench.o src/main_sim.s
	$(LD65) -C cfg/sim.cfg -o $(BUILD)/bench.bin $(BUILD)/bench.o
	$(CA65) -I src -D TARGET_SIM=1 -D SIM_FRAMES=120 -D RENDER=1 -o $(BUILD)/benchr.o src/main_sim.s
	$(LD65) -C cfg/sim.cfg -o $(BUILD)/benchr.bin $(BUILD)/benchr.o
	tests/bench.sh "$(BENCH_ROM)"

# Cycle profile per routine: make profile PROFILE_ROM=game.gb [PROFILE_ARGS="60 2 render"]
PROFILE_ROM ?= tests/roms/dmg-acid2.gb
PROFILE_ARGS ?= 60 2 render
profile:
	python3 tools/profile.py "$(PROFILE_ROM)" $(PROFILE_ARGS)

.PHONY: bench profile
