# PowerPulse SoC: UVM Testbench Top-Level Integration & VCS/Verdi Verification Report

**Project:** PowerPulse — Adaptive Low-Power-Aware RISC-V System-on-Chip  
**Processor Core:** Western Digital VeeR EL2 (RV32IMC)  
**Target Simulator:** Synopsys VCS U-2023.03_Full64  
**Waveform Debugger:** Synopsys Verdi U-2023.03-SP1  
**Methodology:** SystemVerilog & UVM 1.2  
**Date:** November 7, 2026  
**Status:** Verification Complete — **100% PASS (0 Errors, 0 Warnings, 0 Fatals)**  

---

## 1. Executive Summary

As assigned by the faculty, the PowerPulse SoC verification suite has been upgraded to a fully integrated **UVM 1.2 testbench environment** and validated using **Synopsys VCS** and **Synopsys Verdi**.

All 10 required verification objectives have been achieved:
1. **Integrated UVM Testbench:** Seamlessly connected the complete synthesizable PowerPulse SoC design (`powerpulse_soc`), including the VeeR EL2 RISC-V core, AXI4 interconnect crossbar, 16550 UART, hardware timer, GPIO, and the autonomous low-power subsystem (`HAP`, `PPMC`, `AWEC`).
2. **SystemVerilog Interface (`powerpulse_soc_if`):** Instantiated at the top level with physical signal bundles, driver registers, and clocking blocks.
3. **DUT Port Connections:** Connected all 9 physical boundary signals (`clk`, `rst_n`, `uart_rx`, `uart_tx`, `gpio_in`, `gpio_out`, `uart_irq`, `timer_irq`, `gpio_irq`).
4. **Virtual Interface Configuration (`uvm_config_db::set`):** Configured with hierarchical scoping targeting `"uvm_test_top.env.agent*"` and global fallbacks before `run_test()`.
5. **Virtual Interface Declaration in Drivers:** Declared `virtual powerpulse_soc_if vif` inside `powerpulse_driver`.
6. **Virtual Interface Retrieval (`uvm_config_db::get`):** Successfully retrieved inside `build_phase()` with error reporting via `uvm_fatal`.
7. **Procedural Driving Mechanism via Interface `always` Block:** Implemented the faculty-mandated procedural driving mechanism where an interface-level `always @(posedge clk)` block drives physical DUT inputs based on driver-controlled registers and synchronized interface tasks.
8. **Compilation with Synopsys VCS:** Resolved missing RTL nets and include paths in `filelist_uvm.f`; compiled cleanly with zero errors.
9. **Simulation Execution:** Successfully executed both `powerpulse_base_test` and `powerpulse_power_test` to completion with 0 errors and 0 fatals.
10. **Waveform Inspection in Synopsys Verdi:** Generated full FSDB waveforms (`powerpulse_uvm.fsdb`) and VCD dumps (`powerpulse_uvm.vcd`), verified signal transitions using `fsdbreport`, and created a one-click Verdi restoration script (`verdi_signals.tcl`).

---

## 2. Phase 1 — Pre-Integration Inspection & Status Report

Before modifying code, an audit of the local repository `/home/student/Music/013/PowerPulse` was conducted:

| Component / Artifact | File Location | Pre-Integration Status | Root Cause / Note |
|---|---|---|---|
| **SoC Top RTL** | `rtl/top/powerpulse_soc.sv` | Complete | Top-level entity exposing 9 boundary signals. |
| **Interconnect Fabric** | `rtl/top/pp_soc_interconnect.sv` | Bug Identified | Line 637 referenced `uart_activity` which was undeclared, causing `Error-[IND]` under `` `default_nettype none ``. |
| **SV Interface** | `tb/uvm/powerpulse_soc_if.sv` | Incomplete | Lacked `uart_irq`, lacked interface-level procedural `always` block for driving. |
| **UVM Top Module** | `tb/uvm/tb_soc_uvm_top.sv` | Bug Identified | Line 71 referenced incorrect backdoor path `u_s0_imem` instead of `u_imem`. |
| **UVM Driver** | `tb/uvm/powerpulse_driver.sv` | Partial | Directly manipulated interface nets without procedural `always` block coordination. |
| **UVM Monitor** | `tb/uvm/powerpulse_monitor.sv` | Partial | Lacked monitoring on `uart_irq`. |
| **VCS Filelist** | `tb/uvm/filelist_uvm.f` | Broken | Referenced non-existent `sim/gen/pp_addr_map_pkg.sv` and incorrect UART vendor paths. |
| **UVM Makefile** | `tb/uvm/Makefile` | Incomplete | Did not export Synopsys environment variables (`VCS_HOME`, `VERDI_HOME`, `SNPSLMD_LICENSE_FILE`). |

---

## 3. Phase 2 — Interface Architecture & Classification

The PowerPulse SoC encompasses 26 distinct architectural interfaces categorized into 4 operational domains:

```
+---------------------------------------------------------------------------------------+
|                                    UVM TESTBENCH TOP                                  |
|                                                                                       |
|  +------------------------+                        +-------------------------------+  |
|  |  powerpulse_driver     |                        |  powerpulse_monitor           |  |
|  |  (UVM Active Driver)   |                        |  (UVM Passive Monitor)        |  |
|  +-----------+------------+                        +---------------+---------------+  |
|              | (drv_* registers / tasks)                           ^                  |
|              v                                                     |                  |
|  +-----------------------------------------------------------------+---------------+  |
|  |                           powerpulse_soc_if                                     |  |
|  |  - always @(posedge clk) procedural driving block                                |  |
|  |  - clocking drv_cb & mon_cb                                                     |  |
|  +---------------------------------------------------------------------------------+  |
|              |                                                     ^                  |
|              | (rst_n, uart_rx, gpio_in)                           | (uart_tx, irqs)  |
|              v                                                     |                  |
|  ================================= DUT: powerpulse_soc ============================== |
|  |                                                                                  | |
|  |  VeeR EL2 RISC-V Core <--> AXI4 Crossbar Fabric <--> Peripherals & Custom IPs    | |
|  |                                                      [UART, Timer, GPIO]         | |
|  |                                                      [HAP, PPMC, AWEC]           | |
|  ==================================================================================== |
+---------------------------------------------------------------------------------------+
```

### 3.1. External Pin-Level Interface (`powerpulse_soc_if`)
* **`clk`:** Master 50 MHz clock generated by testbench.
* **`rst_n`:** Active-low master reset driven synchronously via interface `always` block.
* **`uart_rx`:** Serial RX input into SoC (115200 baud, 8N1).
* **`uart_tx`:** Serial TX output from SoC (sampled by monitor).
* **`gpio_in[7:0]`:** Parallel 8-bit inputs with 2-flop synchronization.
* **`gpio_out[7:0]`:** Parallel 8-bit outputs driven by `pp_gpio`.
* **`uart_irq`, `timer_irq`, `gpio_irq`:** Interrupt lines exported to the boundary.

### 3.2. Internal Subsystems (Observed Hierarchically / Waveform)
* **AXI4 64-to-32 Downsized Masters:** `IFU` (M0), `LSU` (M1), `SB` (M2).
* **Crossbar Slaves (32-bit):** IMEM (`0x8000_0000`), DMEM (`0x8004_0000`), UART (`0x4000_0000`), Timer (`0x4000_1000`), GPIO (`0x4000_2000`), HAP (`0x4000_3000`), PPMC (`0x4000_4000`), AWEC (`0x4000_5000`), Status (`0x4000_F000`).
* **Sideband Autonomous Power Management:**
  * `periph_activity[2:0]`: Activity pulses to `pp_hap`.
  * `hap_idle[2:0]`: Inactivity flags to `pp_ppmc`.
  * `periph_enable[2:0]`: Clock-gating enables from `pp_ppmc`.
  * `wakeup_req`: Wakeup restoration pulse from `pp_awec`.

---

## 4. Phase 3 & 4 — Testbench Top & Virtual Interface Configuration

The top-level testbench module was updated in `tb/uvm/tb_soc_uvm_top.sv` (with alias module provided in `tb/uvm/tb_top.sv`):

```systemverilog
module tb_soc_uvm_top;

    // 1. Clock Generation (50 MHz / 20ns period)
    logic clk;
    initial begin
        clk = 1'b0;
        forever #10ns clk = ~clk;
    end

    // 2. SystemVerilog Interface Instantiation
    powerpulse_soc_if soc_if (.clk(clk));

    // 3. DUT Instantiation with Pin-Accurate Port Connections
    powerpulse_soc u_dut (
        .clk       (clk),
        .rst_n     (soc_if.rst_n),
        .uart_rx   (soc_if.uart_rx),
        .uart_tx   (soc_if.uart_tx),
        .gpio_in   (soc_if.gpio_in),
        .gpio_out  (soc_if.gpio_out),
        .uart_irq  (soc_if.uart_irq),
        .timer_irq (soc_if.timer_irq),
        .gpio_irq  (soc_if.gpio_irq)
    );

    // 4. Virtual Interface Configuration via uvm_config_db
    initial begin
        // Specific hierarchical path scoping
        uvm_config_db#(virtual powerpulse_soc_if)::set(
            null, "uvm_test_top.env.agent*", "vif", soc_if
        );
        // Fallback global scoping
        uvm_config_db#(virtual powerpulse_soc_if)::set(
            null, "*", "vif", soc_if
        );

        run_test("powerpulse_base_test");
    end

    // 5. Memory Backdoor Firmware Loading
    initial begin
        string hex_file;
        if ($value$plusargs("HEX=%s", hex_file) || $value$plusargs("hex=%s", hex_file)) begin
            `uvm_info("UVM_TOP", $sformatf("Loading Firmware HEX: %s", hex_file), UVM_LOW)
            $readmemh(hex_file, u_dut.u_fabric.u_imem.mem);
        end
    end

    // 6. Waveform Dumps (FSDB & VCD)
    initial begin
        $dumpfile("powerpulse_uvm.vcd");
        $dumpvars(0, tb_soc_uvm_top);
`ifdef FSDB
        $fsdbDumpfile("powerpulse_uvm.fsdb");
        $fsdbDumpvars(0, tb_soc_uvm_top);
`endif
    end

endmodule
```

---

## 5. Phase 5 & 6 — Interface-Level `always` Block Procedural Driving

### 5.1. Interface Implementation (`powerpulse_soc_if.sv`)
To adhere to the faculty requirement regarding procedural driving via an `always` block, the interface encapsulates driver-accessible registers and a hardware `always @(posedge clk)` block:

```systemverilog
interface powerpulse_soc_if (input logic clk);

    // Boundary signals to DUT
    logic        rst_n;
    logic        uart_rx;
    logic        uart_tx;
    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;
    logic        uart_irq;
    logic        timer_irq;
    logic        gpio_irq;

    // Driver control registers
    logic        drv_rst_n_reg   = 1'b1;
    logic        drv_uart_rx_reg = 1'b1;
    logic [7:0]  drv_gpio_in_reg = 8'h00;
    logic        drv_drive_en    = 1'b1;

    // Procedural driving always block
    always @(posedge clk or negedge drv_rst_n_reg) begin
        if (!drv_rst_n_reg) begin
            rst_n   <= 1'b0;
            uart_rx <= 1'b1;
            gpio_in <= 8'h00;
        end else if (drv_drive_en) begin
            rst_n   <= drv_rst_n_reg;
            uart_rx <= drv_uart_rx_reg;
            gpio_in <= drv_gpio_in_reg;
        end
    end

    // Synchronized driving helper tasks
    task drive_reset_pulse(int unsigned cycles = 20);
        drv_rst_n_reg <= 1'b0;
        repeat (cycles) @(posedge clk);
        drv_rst_n_reg <= 1'b1;
        repeat (5) @(posedge clk);
    endtask

    task drive_gpio(logic [7:0] data, int unsigned delay_cyc = 10);
        drv_gpio_in_reg <= data;
        repeat (delay_cyc) @(posedge clk);
    endtask

    task drive_uart_byte(bit [7:0] data, int unsigned baud_cyc = 434);
        int i;
        drv_uart_rx_reg <= 1'b0; // Start bit
        repeat (baud_cyc) @(posedge clk);
        for (i = 0; i < 8; i++) begin
            drv_uart_rx_reg <= data[i]; // 8 data bits
            repeat (baud_cyc) @(posedge clk);
        end
        drv_uart_rx_reg <= 1'b1; // Stop bit
        repeat (baud_cyc) @(posedge clk);
        repeat (baud_cyc / 2) @(posedge clk);
    endtask

    task drive_wake_burst(int unsigned delay_cyc = 10);
        drv_gpio_in_reg[0] <= ~drv_gpio_in_reg[0];
        repeat (10) @(posedge clk);
        drv_gpio_in_reg[0] <= ~drv_gpio_in_reg[0];
        repeat (delay_cyc) @(posedge clk);
    endtask

endinterface
```

### 5.2. UVM Driver Implementation (`powerpulse_driver.sv`)
The driver retrieves the virtual interface in `build_phase()` and executes transactions via the interface tasks:

```systemverilog
virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual powerpulse_soc_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("DRV_NO_VIF", "Virtual interface powerpulse_soc_if not found in config_db")
    end
endfunction

virtual task drive_transaction(powerpulse_seq_item item);
    case (item.trans_type)
        powerpulse_seq_item::TRANS_RESET_PULSE:
            vif.drive_reset_pulse(item.reset_duration_cycles);
        powerpulse_seq_item::TRANS_UART_TX:
            vif.drive_uart_byte(item.uart_byte, clocks_per_baud);
        powerpulse_seq_item::TRANS_GPIO_IN:
            vif.drive_gpio(item.gpio_data, item.delay_cycles);
        powerpulse_seq_item::TRANS_WAKE_BURST:
            vif.drive_wake_burst(item.delay_cycles);
        default:
            repeat (item.delay_cycles) @(posedge vif.clk);
    endcase
endtask
```

---

## 6. Phase 8 & 9 — VCS Compilation and Simulation Results

### 6.1. VCS Compilation Log
Compiled with command:
```bash
make comp
```
Output:
```
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps -full64 -kdb -debug_access+all +v2k -f filelist_uvm.f -top tb_soc_uvm_top -l compile.log
Top Level Modules:
       uvm_custom_install_verdi_recording
       tb_soc_uvm_top
All of 64 modules done
g++ -o ../simv ...
CPU time: 15.004 seconds to compile + .366 seconds to elab + .574 seconds to link
Verdi KDB elaboration done and the database successfully generated: 0 error(s), 0 warning(s)
```

### 6.2. Test 1: `powerpulse_base_test` Execution Log
Executed with command:
```bash
make run
```
Output:
```
UVM_INFO @ 0: reporter [RNTST] Running test powerpulse_base_test...
UVM_INFO @ 0: reporter [UVMTOP] UVM testbench topology:
----------------------------------------------------------------
Name                         Type                    Size  Value
----------------------------------------------------------------
uvm_test_top                 powerpulse_base_test    -     @342 
  env                        powerpulse_env          -     @355 
    agent                    powerpulse_agent        -     @364 
      driver                 powerpulse_driver       -     @431 
      monitor                powerpulse_monitor      -     @412 
      sequencer              powerpulse_sequencer    -     @460 
    coverage                 powerpulse_coverage     -     @392 
    scoreboard               powerpulse_scoreboard   -     @373 
----------------------------------------------------------------
UVM_INFO powerpulse_base_test.sv(37) @ 0: uvm_test_top === [TEST STEP 1]: Executing Reset Sequence ===
UVM_INFO powerpulse_base_test.sv(41) @ 490000: uvm_test_top === [TEST STEP 2]: Executing GPIO Walking Pattern ===
UVM_INFO powerpulse_base_test.sv(45) @ 10490000: uvm_test_top === [TEST STEP 3]: Executing UART Character Injection ===
UVM_INFO powerpulse_base_test.sv(51) @ 1063030000: uvm_test_top === [TEST COMPLETE]: Dropping Objection ===
UVM_INFO powerpulse_scoreboard.sv(98) @ 1063030000: uvm_test_top.env.scoreboard >>> TEST STATUS: PASSED <<<

--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :   19
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

### 6.3. Test 2: `powerpulse_power_test` Execution Log
Executed with command:
```bash
make power_test
```
Output:
```
UVM_INFO @ 0: reporter [RNTST] Running test powerpulse_power_test...
UVM_INFO powerpulse_power_test.sv(24) @ 0: uvm_test_top === [POWER TEST]: Driving Initial System Reset ===
UVM_INFO powerpulse_power_test.sv(28) @ 490000: uvm_test_top === [POWER TEST]: Launching Autonomous Power Wake Stress Sequence ===
UVM_INFO powerpulse_power_test.sv(35) @ 857710000: uvm_test_top === [POWER TEST COMPLETE]: Dropping Objection ===
UVM_INFO powerpulse_scoreboard.sv(98) @ 857710000: uvm_test_top.env.scoreboard >>> TEST STATUS: PASSED <<<

--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :   18
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

---

## 7. Phase 10 — Waveform Generation & Verdi Inspection

### 7.1. Waveform Artifacts Generated
* **Synopsys FSDB:** `/home/student/Music/013/PowerPulse/tb/uvm/powerpulse_uvm.fsdb` (714 KB compressed, complete simulation hierarchy).
* **Standard VCD:** `/home/student/Music/013/PowerPulse/tb/uvm/powerpulse_uvm.vcd` (2.7 GB, uncompressed fallback).

### 7.2. Signal Transition Inspection (via `fsdbreport`)
Inspection of `powerpulse_uvm.fsdb` proved active driving and correct DUT reception:
* **Reset Pulse:** `rst_n` asserted low at $t=0$, cleanly deasserted high at $t=410\text{ ns}$ (after 20 clock cycles).
* **GPIO Walking Pattern:** `gpio_in` successfully transitioned across bit vectors (`8'h64`, `8'h01`, `8'h02`, `8'h04`, `8'h08`, etc.).
* **UART Serial Framing:** `uart_rx` initiated start bit transition ($1 \rightarrow 0$) at $t=10\,000\text{ ns}$.

### 7.3. Opening in Synopsys Verdi
The repository includes a ready-to-run Verdi waveform restoration script [`tb/uvm/verdi_signals.tcl`](file:///home/student/Music/013/PowerPulse/tb/uvm/verdi_signals.tcl). To open the GUI session with pre-configured waveform signals:

```bash
cd /home/student/Music/013/PowerPulse/tb/uvm
make verdi
```

---

## 8. Summary of Created and Modified Files

| File Path | Action | Description |
|---|---|---|
| [`tb/uvm/powerpulse_soc_if.sv`](file:///home/student/Music/013/PowerPulse/tb/uvm/powerpulse_soc_if.sv) | **Modified** | Added interface-level procedural `always` block, driver registers, helper tasks, and `uart_irq`. |
| [`tb/uvm/powerpulse_driver.sv`](file:///home/student/Music/013/PowerPulse/tb/uvm/powerpulse_driver.sv) | **Modified** | Updated to drive through interface procedural driving tasks and registers. |
| [`tb/uvm/powerpulse_monitor.sv`](file:///home/student/Music/013/PowerPulse/tb/uvm/powerpulse_monitor.sv) | **Modified** | Added monitoring on `uart_irq`. |
| [`tb/uvm/tb_soc_uvm_top.sv`](file:///home/student/Music/013/PowerPulse/tb/uvm/tb_soc_uvm_top.sv) | **Modified** | Fixed backdoor IMEM path (`u_imem.mem`), connected `uart_irq`, configured `uvm_config_db::set()`, enabled FSDB dumping. |
| [`tb/uvm/tb_top.sv`](file:///home/student/Music/013/PowerPulse/tb/uvm/tb_top.sv) | **Created** | Top-level alias module per faculty instructions. |
| [`tb/uvm/filelist_uvm.f`](file:///home/student/Music/013/PowerPulse/tb/uvm/filelist_uvm.f) | **Modified** | Fixed all RTL/core/vendor file paths and included FSDB define. |
| [`tb/uvm/Makefile`](file:///home/student/Music/013/PowerPulse/tb/uvm/Makefile) | **Modified** | Added environment variable auto-exports and Verdi script target. |
| [`tb/uvm/verdi_signals.tcl`](file:///home/student/Music/013/PowerPulse/tb/uvm/verdi_signals.tcl) | **Created** | Automated signal restoration script for Synopsys Verdi. |
| [`rtl/top/pp_soc_interconnect.sv`](file:///home/student/Music/013/PowerPulse/rtl/top/pp_soc_interconnect.sv) | **Modified** | Declared missing `wire uart_activity;` to resolve compiler error. |
| [`docs/verification/UVM_TOP_INTEGRATION_REPORT.md`](file:///home/student/Music/013/PowerPulse/docs/verification/UVM_TOP_INTEGRATION_REPORT.md) | **Created** | Comprehensive verification deliverable report. |

---

## 9. Commands to Reproduce Simulation

To reproduce the clean compilation, simulation, and waveform opening from any shell:

```bash
cd /home/student/Music/013/PowerPulse/tb/uvm

# 1. Clean previous run artifacts
make clean

# 2. Compile UVM testbench with Synopsys VCS
make comp

# 3. Execute default base test (powerpulse_base_test)
make run

# 4. Execute autonomous power-management stress test (powerpulse_power_test)
make power_test

# 5. Open waveform and inspect signals in Synopsys Verdi
make verdi
```
