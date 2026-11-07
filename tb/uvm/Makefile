# ==============================================================================
# PowerPulse SoC: VCS UVM Makefile
# Usage:
#   make comp               # Compile design and UVM environment
#   make run                # Run default test (powerpulse_base_test)
#   make power_test         # Run power management stress test
#   make verdi              # Open waveform in Synopsys Verdi
#   make clean              # Remove simulation artifacts
# ==============================================================================

SHELL := /bin/bash

# Toolchain configuration (matches lab setup)
VCS_HOME              ?= /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME            ?= /home/student/snps_tools_target/verdi/U-2023.03-SP1
SNPSLMD_LICENSE_FILE  ?= 27021@14.139.1.126

export VCS_HOME VERDI_HOME SNPSLMD_LICENSE_FILE
export PATH := $(VCS_HOME)/bin:$(VERDI_HOME)/bin:$(PATH)
export LD_LIBRARY_PATH := /usr/lib64:$(VCS_HOME)/lib:$(VCS_HOME)/linux64/lib:$(LD_LIBRARY_PATH)

VCS        = vcs
VCS_FLAGS  = -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps -full64 -kdb -debug_access+all +v2k
FILELIST   = filelist_uvm.f
TOP        = tb_soc_uvm_top
TEST       = powerpulse_base_test
VERBOSITY  = UVM_LOW

.PHONY: all comp run power_test verdi clean

all: comp run

comp:
	$(VCS) $(VCS_FLAGS) -f $(FILELIST) -top $(TOP) -l compile.log

run:
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) +DUMP -l sim_$(TEST).log

power_test:
	./simv +UVM_TESTNAME=powerpulse_power_test +UVM_VERBOSITY=$(VERBOSITY) +DUMP -l sim_power_test.log

verdi:
	$(VERDI_HOME)/bin/verdi -ssf powerpulse_uvm.fsdb -sswr powerpulse_signals.rc &

clean:
	rm -rf simv* csrc *.daidir *.log ucli.key *.vcd *.fsdb DVEfiles verdiLog novas.* fsdbreportLog *.txt
