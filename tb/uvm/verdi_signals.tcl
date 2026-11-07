# ==============================================================================
# Synopsys Verdi Waveform Restoration Script
# PowerPulse SoC UVM Verification Environment
# ==============================================================================

# 1. Open FSDB Simulation Result
debLoadSimResult "powerpulse_uvm.fsdb"

# 2. Open Waveform Window
wvCreateWindow

# 3. Group 1: TB Control & Reset
wvAddGroup -win $_nWave2 "1. TB_Control"
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/clk}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/rst_n}

# 4. Group 2: Interface Procedural Driving (Faculty Assignment Requirement)
wvAddGroup -win $_nWave2 "2. Procedural_Driving"
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/drv_drive_en}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/drv_uart_rx_reg}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/drv_gpio_in_reg[7:0]}

# 5. Group 3: DUT External Pin Interfaces (Stimulus & Response)
wvAddGroup -win $_nWave2 "3. DUT_Interfaces"
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/uart_rx}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/uart_tx}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/gpio_in[7:0]}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/gpio_out[7:0]}

# 6. Group 4: Interrupts & Power Subsystem
wvAddGroup -win $_nWave2 "4. Interrupts_and_Power"
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/uart_irq}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/timer_irq}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/gpio_irq}
wvAddSignal -win $_nWave2 -radix bin {/tb_soc_uvm_top/u_dut/u_fabric/periph_activity[2:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/u_dut/u_fabric/wakeup_req}

# 7. Zoom to active region
wvZoomAll -win $_nWave2
