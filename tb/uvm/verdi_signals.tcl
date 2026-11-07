# ==============================================================================
# Synopsys Verdi Waveform Restoration & Inspection Script
# PowerPulse SoC UVM Testbench Environment
# ==============================================================================

# 1. Load Design and Knowledge Database (KDB)
debImport "-sv" "-f" "filelist_uvm.f" "-top" "tb_soc_uvm_top"

# 2. Open FSDB Waveform File
debLoadSimResult "powerpulse_uvm.fsdb"

# 3. Create Waveform Window
wvCreateWindow

# 4. Add Top-Level Testbench and Interface Signals
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/clk"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/rst_n"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/uart_rx"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/uart_tx"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/gpio_in[7:0]"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/gpio_out[7:0]"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/uart_irq"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/timer_irq"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/soc_if/gpio_irq"

# 5. Add Internal Autonomous Power Management Signals
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/u_dut/u_fabric/periph_activity[2:0]"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/u_dut/u_fabric/hap_idle[2:0]"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/u_dut/u_fabric/periph_enable[2:0]"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/u_dut/u_fabric/wakeup_req"
wvAddSignal -win $_nWave2 "/tb_soc_uvm_top/u_dut/u_fabric/wakeup_source_id[1:0]"

# 6. Zoom to full simulation range
wvZoomAll -win $_nWave2
