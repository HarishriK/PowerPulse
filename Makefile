# =============================================================================
# PowerPulse -- single entry point for everything
#
#   make help              what every target does
#   make list              the tests that exist and their groups
#   make gen               regenerate everything derived from the config
#   make run  T=<test>     do whatever is stale, then simulate, then print PASS/FAIL
#   make wave T=<test>     open that run's waveform in Verdi
#   make regress G=<grp>   run a group, print a summary table
#   make hex  T=<test> HEX=<path>   run an externally built hex image
#   make clean T=<test>    delete one run folder
#   make clean-all         delete all build output
#
# Optional variables:
#   T=<test>       which test (omit T and the last run is reused)
#   G=<group>      regression group, or `all`
#   SEED=<n>       run with a specific seed (repeatable: any failure reproduces)
#   SEEDS=1,2,3    sweep seeds in a regression
#   CONFIG=<path>  alternative config file (default config/soc_config.yaml)
#   FORCE=1        rebuild even if nothing looks stale
#
# There is deliberately no waves on/off switch: the waveform is always dumped,
# and `make wave` opens it.
# =============================================================================

SHELL     := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
ROOT      := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

PYTHON    ?= python3
CONFIG    ?= config/soc_config.yaml
FORCE     ?= 0

# Everything below is either a tool on PATH or a parameter from the config.
# The /opt toolchain path and every address come from config/soc_config.yaml and
# are never written here.
VCS       ?= vcs
VERDI     ?= verdi

TOOLS     := $(ROOT)/tools
SIM       := $(ROOT)/sim
RUNS      := $(SIM)/runs
LATEST    := $(SIM)/latest

GEN_STAMP := $(SIM)/gen/.stamp

.DEFAULT_GOAL := help
.PHONY: help list gen run wave regress hex clean clean-all lint toolchain

# -----------------------------------------------------------------------------
help:
	@echo ""
	@echo "PowerPulse -- adaptive low-power-aware RISC-V SoC on VeeR EL2"
	@echo ""
	@echo "USAGE"
	@echo "  make <target> [T=<test>] [G=<group>] [SEED=<n>] [SEEDS=1,2,3]"
	@echo ""
	@echo "TARGETS"
	@echo "  gen                 regenerate the interconnect, the VeeR core config,"
	@echo "                      the C/SV memory-map headers, the linker script and"
	@echo "                      the UART macro prelude from \$$CONFIG"
	@echo "  run T=<test>        do whatever is stale (gen, compile, software build)"
	@echo "                      then simulate and print PASS/FAIL"
	@echo "  wave T=<test>       open that run's waveform in Verdi"
	@echo "  regress G=<group>   run a regression group (or G=all) and print a table"
	@echo "  hex T=<test> HEX=<path>"
	@echo "                      run an externally built hex image instead of the"
	@echo "                      built-in software flow"
	@echo "  list                list tests and groups"
	@echo "  toolchain           print the toolchain the config selects"
	@echo "  clean T=<test>      delete one test's run folder"
	@echo "  clean-all           delete every build and run artefact"
	@echo ""
	@echo "VARIABLES"
	@echo "  T=<test>            test name (see 'make list'); omit to reuse the last run"
	@echo "  G=<group>           regression group: smoke | bus | uart | sw | adapter | all"
	@echo "  SEED=<n>            run with one specific seed"
	@echo "  SEEDS=1,2,3         sweep seeds inside a regression"
	@echo "  CONFIG=<path>       alternative config file (default $(CONFIG))"
	@echo "  FORCE=1             rebuild even if nothing looks stale"
	@echo ""
	@echo "EXAMPLES"
	@echo "  make gen"
	@echo "  make run T=bus_decode_map"
	@echo "  make wave T=bus_decode_map"
	@echo "  make regress G=smoke"
	@echo "  make regress G=bus SEEDS=1,2,3"
	@echo ""

# -----------------------------------------------------------------------------
list:
	@$(PYTHON) $(TOOLS)/testenv.py --json CONFIG=$(CONFIG) 2>/dev/null || \
	 $(PYTHON) $(TOOLS)/testenv.py

toolchain:
	@$(PYTHON) -c "import sys; sys.path.insert(0, '$(TOOLS)'); \
	from soc_config import load_config; c = load_config('$(CONFIG)'); \
	print('toolchain : %s/%s%s' % (c.sw_toolchain_path, c.sw_toolchain_prefix, 'gcc')); \
	print('ISA/ABI   : %s / %s' % (c.sw_isa, c.sw_abi)); \
	print('march/mabi: %s / %s' % (c.sw_march, c.sw_mabi)); \
	print('image     : clock %d Hz, baud %d (divisor %d)' % (c.clock_freq_hz, c.uart_baud, c.uart_divisor))"

# -----------------------------------------------------------------------------
# Generation.  Every generated artefact lives under sim/gen and is git-ignored;
# the generators and the config are the only committed inputs.
gen:
	@$(PYTHON) $(TOOLS)/gen_interconnect.py $(CONFIG)
	@$(PYTHON) $(TOOLS)/gen_veer_config.py
	@$(PYTHON) $(TOOLS)/gen_uart_defines.py
	@$(PYTHON) -c "import hashlib,os,sys; \
	sys.path.insert(0,'$(TOOLS)'); \
	import run_test; \
	os.makedirs('$(SIM)/gen', exist_ok=True); \
	open('$(GEN_STAMP)','w').write(run_test.gen_inputs_hash())"
	@echo "gen: done -- sim/gen/ is up to date"

# -----------------------------------------------------------------------------
run:
	@if [ -z "$(strip $(T))" ]; then \
	   T=$$($(PYTHON) $(TOOLS)/last_test.py); \
	   if [ -z "$$T" ]; then echo "run: no T=<test> given and no previous run; try 'make list'"; exit 2; fi; \
	   echo "run: no T given, reusing the last run ($$T)"; \
	 fi; \
	 $(PYTHON) $(TOOLS)/run_test.py --test $$T $(if $(SEED),--seed $(SEED),) $(if $(filter 1,$(FORCE)),--force,)

wave:
	@if [ -z "$(strip $(T))" ]; then \
	   T=$$($(PYTHON) $(TOOLS)/last_test.py); \
	   if [ -z "$$T" ]; then echo "wave: no T=<test> given and no previous run"; exit 2; fi; \
	 fi; \
	 RUN=$$($(PYTHON) $(TOOLS)/run_dir.py $$T $(SEED)); \
	 if [ ! -f "$$RUN/waves/dump.vpd" ]; then \
	   echo "wave: no waveform in $$RUN -- run 'make run T=$$T' first"; exit 1; \
	 fi; \
	 echo "wave: opening $$RUN/waves/dump.vpd"; \
	 $(PYTHON) $(TOOLS)/open_wave.py "$$RUN"

regress:
	@$(PYTHON) $(TOOLS)/regress.py --group $(if $(G),$(G),all) $(if $(SEEDS),--seeds $(SEEDS),) $(if $(filter 1,$(FORCE)),--force,)

hex:
	@if [ -z "$(strip $(T))" ] || [ -z "$(strip $(HEX))" ]; then \
	   echo "usage: make hex T=<test> HEX=<path/to/image.hex>"; exit 2; \
	 fi; \
	 $(PYTHON) $(TOOLS)/run_test.py --test $$T --hex $(HEX) $(if $(SEED),--seed $(SEED),) $(if $(filter 1,$(FORCE)),--force,)

# -----------------------------------------------------------------------------
clean:
	@if [ -z "$(strip $(T))" ]; then \
	   echo "usage: make clean T=<test>   (or 'make clean-all')"; exit 2; \
	 fi; \
	 $(PYTHON) $(TOOLS)/clean.py --test $$T
	@echo "clean: removed the run folder for $$T"

clean-all:
	@$(PYTHON) $(TOOLS)/clean.py --all
	@echo "clean-all: removed sim/"
