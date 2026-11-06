# PowerPulse SoC: External vs. Internal Signals Classification

**Project:** PowerPulse — Adaptive Low-Power-Aware RISC-V SoC  
**Target Design:** `rtl/top/powerpulse_soc.sv`  
**Classification Scope:** Boundary Pins (External) vs. Inter-Module / Bus / Sideband Signals (Internal)

---

## 1. Executive Summary

The PowerPulse SoC boundary separates the internal synthesizable system logic from external world interfaces (board traces, external pads, test harnesses, and VIPs). This document provides an exhaustive, pin-accurate classification of all signals into:
1. **External Boundary Signals:** Signals crossing the `powerpulse_soc` module boundary to physical package pins or top-level verification environments.
2. **Internal Signals:** Signals interconnecting the RISC-V VeeR EL2 core, AXI interconnect fabric, memory controllers, peripherals, and custom autonomous power management blocks (HAP, PPMC, AWEC).

---

## 2. External Boundary Signals (`powerpulse_soc`)

These are the primary I/O ports defined on the top-level entity `powerpulse_soc` in [powerpulse_soc.sv](file:///C:/Users/Logins/Desktop/honours/PowerPulse/rtl/top/powerpulse_soc.sv).

| Pin Name | Direction | Width | Domain / Polarity | Category | Description & Protocol |
|---|---|---|---|---|---|
| `clk` | Input | 1-bit | System Clock (Rising) | Clocking | Primary SoC master clock (nominal 50 MHz in simulation/FPGA). Feeds core, interconnect, memories, and all peripheral synchronizers. |
| `rst_n` | Input | 1-bit | Asynchronous active-low | Reset | Master system reset. Active-low (`0` = assert reset, `1` = normal operational state). Synchronized internally to `clk` before driving registers. |
| `uart_rx` | Input | 1-bit | Async serial (115200 8N1) | Comm Interface | UART receive serial data pin. Synchronized by 2-flop synchronizer in UART controller; framed with 1 start bit, 8 data bits, 1 stop bit. |
| `uart_tx` | Output | 1-bit | Async serial (115200 8N1) | Comm Interface | UART transmit serial data pin. Driven by UART baud generator; idle state is high (`1'b1`). |
| `gpio_in[7:0]` | Input | 8-bit | Synchronous sampled | General Purpose I/O | External digital input lines from external sensors/buttons. Each bit is sampled through a 2-flop synchronizer and edge-detection filter in `pp_gpio`. |
| `gpio_out[7:0]` | Output | 8-bit | Synchronous registered | General Purpose I/O | External digital output lines to LEDs, actuators, or board peripherals. Directly driven by the `pp_gpio` output data register. |
| `timer_irq` | Output | 1-bit | Synchronous active-high pulse | Interrupt / Observability | Hardware timer expiration/overflow interrupt pin. Exported externally to allow board-level power management ICs (PMICs) or logic analyzers to trigger on timer tick. |
| `gpio_irq` | Output | 1-bit | Synchronous active-high pulse | Interrupt / Observability | GPIO edge-detection interrupt pin. Asserts when any enabled GPIO input pin experiences a configured rising or falling edge. |

---

## 3. Internal Signals Breakdown

### 3.1. Processor Core Interfaces (VeeR EL2 to Fabric)

The VeeR EL2 processor exposes three 64-bit AXI4 master interfaces.

| Signal Group | Direction (Core $\rightarrow$ Fabric) | Width | Channel | Description |
|---|---|---|---|---|
| `m0_axi_aw*` | Output (AWADDR: 32, AWID: 8, AWLEN: 8, AWSIZE: 3, AWBURST: 2, AWVALID: 1) | Var | Write Address | IFU (Instruction Fetch Unit) Write Address Channel (typically unused / tied for instruction-only fetch). |
| `m0_axi_w*` | Output (WDATA: 64, WSTRB: 8, WLAST: 1, WVALID: 1) | Var | Write Data | IFU Write Data Channel. |
| `m0_axi_b*` | Input (BRESP: 2, BID: 8, BVALID: 1), Output (BREADY: 1) | Var | Write Response | IFU Write Response Channel. |
| `m0_axi_ar*` | Output (ARADDR: 32, ARID: 8, ARLEN: 8, ARSIZE: 3, ARBURST: 2, ARVALID: 1) | Var | Read Address | IFU Read Address Channel (primary instruction cache fill stream). |
| `m0_axi_r*` | Input (RDATA: 64, RID: 8, RRESP: 2, RLAST: 1, RVALID: 1), Output (RREADY: 1) | Var | Read Data | IFU Read Data Channel (delivers 64-bit double-words to L1 instruction cache). |
| `m1_axi_aw*` | Output (AWADDR: 32, AWID: 8, AWLEN: 8, AWSIZE: 3, AWBURST: 2, AWVALID: 1) | Var | Write Address | LSU (Load-Store Unit) Write Address Channel for data stores. |
| `m1_axi_w*` | Output (WDATA: 64, WSTRB: 8, WLAST: 1, WVALID: 1) | Var | Write Data | LSU Write Data Channel for memory writes and peripheral MMIO writes. |
| `m1_axi_b*` | Input (BRESP: 2, BID: 8, BVALID: 1), Output (BREADY: 1) | Var | Write Response | LSU Write Response Channel. |
| `m1_axi_ar*` | Output (ARADDR: 32, ARID: 8, ARLEN: 8, ARSIZE: 3, ARBURST: 2, ARVALID: 1) | Var | Read Address | LSU Read Address Channel for loads from DMEM or MMIO peripherals. |
| `m1_axi_r*` | Input (RDATA: 64, RID: 8, RRESP: 2, RLAST: 1, RVALID: 1), Output (RREADY: 1) | Var | Read Data | LSU Read Data Channel. |
| `m2_axi_*` | Master | Var | All Channels | SB (System Bus) Master Interface for DMA/secondary memory requests. |

### 3.2. Width Downsizer and Adaptation Signals

Between the 64-bit VeeR EL2 core masters and the 32-bit interconnect crossbar:

| Signal Group | Width | Source $\rightarrow$ Dest | Purpose |
|---|---|---|---|
| `m0_32_axi_*` | 32-bit data / 32-bit addr | `pp_axi_downsize` $\rightarrow$ Interconnect M0 | Converts 64-bit IFU transactions into 32-bit AXI4 bursts. |
| `m1_32_axi_*` | 32-bit data / 32-bit addr | `pp_axi_downsize` $\rightarrow$ Interconnect M1 | Converts 64-bit LSU transactions into 32-bit AXI4 bursts. |
| `m2_32_axi_*` | 32-bit data / 32-bit addr | `pp_axi_downsize` $\rightarrow$ Interconnect M2 | Converts 64-bit SB transactions into 32-bit AXI4 bursts. |

### 3.3. Interconnect Crossbar Slave Interfaces (32-bit AXI4 / AXI4-Lite)

The crossbar decodes addresses and routes them to 9 slave slots:

| Slave Slot | Base Address | Size | Protocol | Connected Module |
|---|---|---|---|---|
| `S0_IMEM` | `0x8000_0000` | 256 KiB | AXI4 (32-bit) | `pp_axi_ram` (Instruction Memory) |
| `S1_DMEM` | `0x8004_0000` | 256 KiB | AXI4 (32-bit) | `pp_axi_ram` (Data Memory) |
| `S2_UART` | `0x4000_0000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `axi_uart` (16550-compatible UART) |
| `S3_TIMER` | `0x4000_1000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `pp_timer` (Hardware Timer) |
| `S4_GPIO` | `0x4000_2000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `pp_gpio` (General Purpose I/O) |
| `S5_HAP` | `0x4000_3000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `pp_hap` (Hardware Activity Profiler) |
| `S6_PPMC` | `0x4000_4000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `pp_ppmc` (Peripheral Power Controller) |
| `S7_AWEC` | `0x4000_5000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `pp_awec` (Autonomous Wake-up Controller) |
| `S8_STATUS`| `0x4000_F000` | 4 KiB | AXI4-Lite (via `pp_axi4_to_axil`) | `pp_sim_status_dev` (Sim Pass/Fail & Watchdog) |

### 3.4. Autonomous Power Management Sideband Signals

These dedicated point-to-point hardware wires implement the autonomous power control loop without processor intervention.

```
+------------+   periph_activity[2:0]   +------------+   hap_idle[2:0]   +------------+
| Periphs    | -----------------------> |   PP_HAP   | ----------------> |  PP_PPMC   |
| UART,TIM,  | <----------------------- | (Activity) |                   |  (Power)   |
| GPIO       |     periph_enable[2:0]   +------------+                   +------------+
+------------+                                                                 ^
       |                                                                       |
       | periph_wake[2:0]               +------------+   wakeup_req            |
       +------------------------------> |  PP_AWEC   | ------------------------+
                                        |  (Wakeup)  | ------------------------> Core ext_irq
                                        +------------+
```

| Signal Name | Width | Driver | Receiver | Description |
|---|---|---|---|---|
| `periph_activity[0]` | 1-bit | `pp_timer` | `pp_hap` | Asserts when timer registers are accessed or timer countdown ticks. |
| `periph_activity[1]` | 1-bit | `pp_gpio` | `pp_hap` | Asserts when GPIO pins change or GPIO registers are written/read. |
| `periph_activity[2]` | 1-bit | `axi_uart` | `pp_hap` | Asserts when UART TX/RX activity or register access occurs. |
| `hap_idle[0]` | 1-bit | `pp_hap` | `pp_ppmc` | Asserts when Timer inactivity counter exceeds `HAP_IDLE_TH0`. |
| `hap_idle[1]` | 1-bit | `pp_hap` | `pp_ppmc` | Asserts when GPIO inactivity counter exceeds `HAP_IDLE_TH1`. |
| `hap_idle[2]` | 1-bit | `pp_hap` | `pp_ppmc` | Asserts when UART inactivity counter exceeds `HAP_IDLE_TH2`. |
| `periph_enable[0]` | 1-bit | `pp_ppmc` | `pp_timer` | Clock-enable gate for Timer (`1` = normal, `0` = gated/low-power). |
| `periph_enable[1]` | 1-bit | `pp_ppmc` | `pp_gpio` | Clock-enable gate for GPIO (`1` = normal, `0` = gated/low-power). |
| `periph_enable[2]` | 1-bit | `pp_ppmc` | `axi_uart` | Clock-enable gate for UART (`1` = normal, `0` = gated/low-power). |
| `periph_wake[0]` | 1-bit | `pp_timer` | `pp_awec` | Wake-up trigger from Timer overflow/compare match. |
| `periph_wake[1]` | 1-bit | `pp_gpio` | `pp_awec` | Wake-up trigger from GPIO edge detection. |
| `periph_wake[2]` | 1-bit | `axi_uart` | `pp_awec` | Wake-up trigger from incoming UART start bit. |
| `wakeup_req` | 1-bit | `pp_awec` | `pp_ppmc` & Core | Fast wake pulse to restore all peripherals to `ACTIVE` mode and interrupt CPU. |

---

## 4. Verification View: Signal Classification Matrix

| Classification | Total Count | Primary Verification Approach |
|---|---|---|
| **External Inputs** | 10 pins (`clk`, `rst_n`, `uart_rx`, `gpio_in[7:0]`) | Driven by UVM Agents (Clock/Reset VIP, UART VIP, GPIO VIP). |
| **External Outputs** | 10 pins (`uart_tx`, `gpio_out[7:0]`, `timer_irq`) | Monitored by UVM Scoreboard and Protocol Checkers. |
| **Internal Bus Signals** | > 250 nets (AXI4/AXI4-Lite AW, W, B, AR, R channels) | Monitored by `pp_axi_checker` and SVA Assertion Monitors. |
| **Internal Sidebands** | 13 nets (Activity, Idle, Enable, Wakeup, IRQs) | Monitored by `pp_power_monitor` in UVM Scoreboard. |
