// ==============================================================================
// PowerPulse SoC: VCS UVM Filelist
// Target Simulator: Synopsys VCS / Verdi
// ==============================================================================

// Include Directories
+incdir+../../sim/gen
+incdir+../../rtl/core/veer_el2/include
+incdir+../../rtl/vendor/verilog-axi/rtl
+incdir+../../rtl/vendor/axi-lite-uart/rtl
+incdir+../../tb/uvm

// Preprocessor Defines
+define+PP_SIM=1
+define+RV_EXT_DATAWIDTH=64

// Generated Configuration Packages
../../sim/gen/pp_soc_cfg_pkg.sv
../../sim/gen/pp_addr_map_pkg.sv

// Bus Adapters & RAM
../../rtl/bus/pp_axi_downsize.v
../../rtl/bus/pp_axi4_to_axil.v
../../rtl/mem/pp_axi_ram.sv

// Peripherals & Custom Low-Power IPs
../../rtl/vendor/axi-lite-uart/rtl/uart.v
../../rtl/vendor/axi-lite-uart/rtl/axi_uart.v
../../rtl/ip/timer/pp_timer.sv
../../rtl/ip/gpio/pp_gpio.sv
../../rtl/ip/hap/pp_hap.sv
../../rtl/ip/ppmc/pp_ppmc.sv
../../rtl/ip/awec/pp_awec.sv
../../tb/common/pp_sim_status_dev.sv

// Top & Core
../../rtl/core/pp_veer_core.sv
../../rtl/top/pp_soc_interconnect.sv
../../rtl/top/powerpulse_soc.sv

// UVM Verification Environment
powerpulse_soc_if.sv
powerpulse_uvm_pkg.sv
tb_soc_uvm_top.sv
