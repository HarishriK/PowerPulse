// ==============================================================================
// PowerPulse SoC: VCS UVM Filelist
// Target Simulator: Synopsys VCS / Verdi
// ==============================================================================

// Include Directories
+incdir+../../sim/gen/veer
+incdir+../../rtl/core/veer_el2/design/include
+incdir+../../rtl/core/veer_el2/design/lib
+incdir+../../sim/gen/uart
+incdir+../../rtl/vendor/axi-lite-uart/src/include
+incdir+../../rtl/vendor/axi-lite-uart/src/rtl
+incdir+../../sim/gen
+incdir+../../tb/common
+incdir+../../sw/common
+incdir+../../tb/uvm

// Preprocessor Defines
+define+PP_SIM=1
+define+RV_EXT_DATAWIDTH=64
+define+FSDB=1

// 1. VeeR EL2 RISC-V Core Design Files
../../rtl/core/veer_el2/design/include/el2_def.sv
../../rtl/core/veer_el2/design/lib/el2_assert.sv
../../rtl/core/veer_el2/design/el2_mubi_pkg.sv
../../rtl/core/veer_el2/design/el2_veer_wrapper.sv
../../rtl/core/veer_el2/design/el2_lockstep_pkg.sv
../../rtl/core/veer_el2/design/el2_veer_lockstep.sv
../../rtl/core/veer_el2/design/el2_mem.sv
../../rtl/core/veer_el2/design/el2_pic_ctrl.sv
../../rtl/core/veer_el2/design/el2_veer.sv
../../rtl/core/veer_el2/design/el2_dma_ctrl.sv
../../rtl/core/veer_el2/design/el2_pmp.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_aln_ctl.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_compress_ctl.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_ifc_ctl.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_bp_ctl.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_ic_mem.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_mem_ctl.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu_iccm_mem.sv
../../rtl/core/veer_el2/design/ifu/el2_ifu.sv
../../rtl/core/veer_el2/design/dec/el2_dec_decode_ctl.sv
../../rtl/core/veer_el2/design/dec/el2_dec_gpr_ctl.sv
../../rtl/core/veer_el2/design/dec/el2_dec_ib_ctl.sv
../../rtl/core/veer_el2/design/dec/el2_dec_pmp_ctl.sv
../../rtl/core/veer_el2/design/dec/el2_dec_tlu_ctl.sv
../../rtl/core/veer_el2/design/dec/el2_dec_trigger.sv
../../rtl/core/veer_el2/design/dec/el2_dec.sv
../../rtl/core/veer_el2/design/exu/el2_exu_alu_ctl.sv
../../rtl/core/veer_el2/design/exu/el2_exu_mul_ctl.sv
../../rtl/core/veer_el2/design/exu/el2_exu_div_ctl.sv
../../rtl/core/veer_el2/design/exu/el2_exu.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_clkdomain.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_addrcheck.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_lsc_ctl.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_stbuf.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_bus_buffer.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_bus_intf.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_ecc.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_dccm_mem.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_dccm_ctl.sv
../../rtl/core/veer_el2/design/lsu/el2_lsu_trigger.sv
../../rtl/core/veer_el2/design/dbg/el2_dbg.sv
../../rtl/core/veer_el2/design/dmi/dmi_mux.v
../../rtl/core/veer_el2/design/dmi/dmi_wrapper.v
../../rtl/core/veer_el2/design/dmi/dmi_jtag_to_core_sync.v
../../rtl/core/veer_el2/design/dmi/rvjtag_tap.v
../../rtl/core/veer_el2/design/lib/el2_lib.sv
../../rtl/core/veer_el2/design/lib/el2_mem_if.sv
../../rtl/core/veer_el2/design/lib/el2_prim_generic_buf.sv
../../rtl/core/veer_el2/design/lib/el2_prim_buf.sv
-v ../../rtl/core/veer_el2/design/lib/beh_lib.sv
-v ../../rtl/core/veer_el2/design/lib/mem_lib.sv
../../rtl/core/veer_el2/design/lib/ahb_to_axi4.sv
../../rtl/core/veer_el2/design/lib/axi4_to_ahb.sv

// 2. Vendor AXI Infrastructure & 16550 UART IP
../../rtl/vendor/verilog-axi/priority_encoder.v
../../rtl/vendor/verilog-axi/arbiter.v
../../sim/gen/uart/pp_uart_prelude.sv
../../rtl/vendor/axi-lite-uart/src/rtl/axi_internal_fifo.v
../../rtl/vendor/axi-lite-uart/src/rtl/uart_parity_bit_compute.v
../../rtl/vendor/axi-lite-uart/src/rtl/uart_receiver.v
../../rtl/vendor/axi-lite-uart/src/rtl/uart_transmitter.v
../../rtl/vendor/axi-lite-uart/src/rtl/uart_controller.v
../../rtl/vendor/axi-lite-uart/src/rtl/axi_uart_top.v

// 3. Generated Config Package & Crossbar Interconnect
../../sim/gen/pp_soc_cfg_pkg.sv
../../sim/gen/bus/pp_axi_interconnect.sv

// 4. Bus Adapters & RAM Subsystem
../../rtl/bus/pp_axi_downsize.v
../../rtl/bus/pp_axi4_to_axil.v
../../rtl/ip/stub/pp_axi_stub_slave.v
../../rtl/mem/pp_axi_ram.sv

// 5. Peripherals & Custom Low-Power IPs
../../rtl/ip/uart/pp_uart.sv
../../rtl/ip/timer/pp_timer.sv
../../rtl/ip/gpio/pp_gpio.sv
../../rtl/ip/hap/pp_hap.sv
../../rtl/ip/ppmc/pp_ppmc.sv
../../rtl/ip/awec/pp_awec.sv
../../tb/common/pp_sim_status_dev.sv

// 6. Core Wrapper, Fabric & SoC Top
../../rtl/core/pp_veer_core.sv
../../rtl/top/pp_soc_interconnect.sv
../../rtl/top/powerpulse_soc.sv

// 7. UVM Verification Environment
powerpulse_soc_if.sv
powerpulse_uvm_pkg.sv
tb_soc_uvm_top.sv
tb_top.sv
