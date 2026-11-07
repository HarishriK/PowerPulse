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

# 4. Group 2: Interface Procedural Driving (UVM Driver Output)
wvAddGroup -win $_nWave2 "2. UVM_Driver_Output"
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/drv_drive_en}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/drv_gpio_in_reg[7:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/drv_uart_rx_reg}

# 5. Group 3: DUT External Pin Interfaces (Stimulus & Response)
wvAddGroup -win $_nWave2 "3. DUT_Pin_Interface"
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/gpio_in[7:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/uart_rx}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/uart_tx}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/gpio_out[7:0]}

# 6. Group 4: Inside DUT Design (Hardware Reception & Sync)
wvAddGroup -win $_nWave2 "4. Inside_DUT_Design"
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/u_dut/u_fabric/u_gpio/in_sync2[7:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/u_dut/u_fabric/u_gpio/pp_activity_o}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/u_dut/u_fabric/u_uart/u_uart_ip/data_rx_controller_fifo[7:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/u_dut/u_fabric/u_uart/u_uart_ip/push_controller_rx_fifo}
wvAddSignal -win $_nWave2 -radix bin {/tb_soc_uvm_top/u_dut/u_fabric/periph_activity[2:0]}

# 7. Group 5: UVM Monitor Captured (Passive Monitor Observation Tap)
wvAddGroup -win $_nWave2 "5. UVM_Monitor_Captured"
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/mon_gpio_in_sampled[7:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/mon_gpio_in_valid}
wvAddSignal -win $_nWave2 -radix hex {/tb_soc_uvm_top/soc_if/mon_uart_rx_byte[7:0]}
wvAddSignal -win $_nWave2 {/tb_soc_uvm_top/soc_if/mon_uart_rx_valid}

# 8. Zoom to GPIO walking pattern region (0 to 12 us)
wvSetCursor -win $_nWave2 530000.000000
wvZoom -win $_nWave2 0.000000 12000000.000000
