# PowerPulse SoC: Verification IP (VIP) Architecture Specification

**Project:** PowerPulse — Adaptive Low-Power-Aware RISC-V System-on-Chip  
**Document Reference:** `docs/verification/VIP_ARCHITECTURE.md`  
**Verification Framework:** SystemVerilog & UVM-1.2 Compatible  

---

## 1. Overview and Verification Strategy

To verify the PowerPulse SoC across both unit-level blocks, interconnect fabrics, and full-chip core-in-loop simulations, a comprehensive suite of Verification IPs (VIPs) is deployed. Each VIP models the respective protocol, injects randomized and directed stimulus, checks timing and protocol assertions (SVA), and collects functional coverage.

The VIP architecture comprises **6 primary Verification IPs**:
1. **Clock & Reset Generation VIP (`pp_clk_rst_vip`)**
2. **AXI4 Full Master VIP (`pp_axi_master_vip`)**
3. **AXI4 Slave / Memory VIP (`pp_axi_slave_vip`)**
4. **UART Protocol VIP (`pp_uart_vip`)**
5. **GPIO Functional VIP (`pp_gpio_vip`)**
6. **Autonomous Power Management Monitor & SVA VIP (`pp_power_sva_vip`)**

```
+----------------------------------------------------------------------------------+
|                             UVM Verification Environment                         |
|                                                                                  |
|  +------------------+    +------------------+    +----------------------------+  |
|  |  CLK/RST VIP     |    |  UART VIP (BFM)  |    |  GPIO VIP                  |  |
|  |  (Configurable)  |    |  (115200 8N1)    |    |  (8-bit Stim/Mon)          |  |
|  +--------+---------+    +--------+---------+    +--------------+-------------+  |
|           |                       |                             |                |
|           v                       v                             v                |
|  ========================= DUT: powerpulse_soc =================================  |
|           |                       |                             |                |
|           +-----------------------+-----------------------------+                |
|                                   |                                              |
|                                   v                                              |
|  +----------------------------------------------------------------------------+  |
|  |            PowerPulse SVA & Power Management Monitor VIP                   |  |
|  |  - Inactivity Trackers   - State Machine Checker   - Wake Latency SVA       |  |
|  +----------------------------------------------------------------------------+  |
|                                   |                                              |
|                                   v                                              |
|  +----------------------------------------------------------------------------+  |
|  |                          UVM Scoreboard & Coverage                         |  |
|  +----------------------------------------------------------------------------+  |
+----------------------------------------------------------------------------------+
```

---

## 2. Detailed VIP Specifications

### 2.1. Clock & Reset VIP (`pp_clk_rst_vip`)
* **Interface Signals:** `clk`, `rst_n`.
* **Stimulus Capabilities:**
  * Configurable clock period (default: 20 ns / 50 MHz) with $\pm 500\text{ ps}$ random phase jitter.
  * Programmable reset duration (min 5 cycles, typical 20 cycles, stress 200 cycles).
  * Randomized asynchronous reset assertion during active bus transactions to verify clean flush and recovery.
* **Checks & Assertions:**
  * Checks clock frequency within acceptable tolerance.
  * Ensures reset deassertion is glitch-free and meets setup/hold to the next clock edge.

### 2.2. AXI4 Master VIP (`pp_axi_master_vip`)
* **Interface Channels:** AW, W, B, AR, R channels (32-bit and 64-bit configurations).
* **Stimulus Capabilities:**
  * Generates single-beat (`LEN=0`) and burst transactions (`INCR`, `WRAP`, `FIXED`) up to 256 beats.
  * Randomized byte-enable strobes (`WSTRB`).
  * Randomized inter-beat delays (0 to 10 idle cycles on `VALID` and `READY`).
  * Out-of-order response matching using transaction tags (`AxID`).
* **Checks & Protocol Assertions:**
  * Strict AXI4 handshake rules: Once `AxVALID`/`WVALID` is asserted, address/data must remain stable until `AxREADY`/`WREADY` is high.
  * Burst boundary checking: `WRAP` bursts do not cross cache-line boundaries.
  * ID ordering: Write responses (`BID`) and Read data (`RID`) match requested IDs.

### 2.3. AXI4 Slave / Memory VIP (`pp_axi_slave_vip`)
* **Interface:** Connects to slave ports on interconnect or simulates external memories.
* **Stimulus Capabilities:**
  * Configurable read and write latency (0 cycles for zero-wait-state RAM, up to 15 cycles for slow peripherals).
  * Error injection: Configurable to return `SLVERR` (2'b10) or `DECERR` (2'b11) on specified address regions.
  * Direct backdoor memory load (`$readmemh`) and dump for rapid firmware loading.
* **Checks:**
  * Verifies correct write strobe masking on memory bytes.
  * Asserts on unsupported burst types or access misalignments.

### 2.4. UART Protocol VIP (`pp_uart_vip`)
* **Interface Signals:** `uart_rx`, `uart_tx`.
* **Stimulus Capabilities:**
  * Transmit driver: Injects serial byte streams into `uart_rx` with configurable baud rate (115200 nominal).
  * Timing variation: Jittered bit period ($\pm 2\%$) to verify receiver tolerance.
  * Framing error injection: Missing stop bit, inverted start bit, parity injection for robustness testing.
* **Monitor & Scoreboard:**
  * Receiver monitor: Decodes `uart_tx` output bitstream into 8-bit bytes with start/stop verification.
  * Broadcasts received characters to UVM analysis ports for string/log checking in real-time.

### 2.5. GPIO Functional VIP (`pp_gpio_vip`)
* **Interface Signals:** `gpio_in[7:0]`, `gpio_out[7:0]`.
* **Stimulus Capabilities:**
  * Multi-bit pattern generator: Injects walking 1s, walking 0s, toggle patterns, and random bit masks.
  * Pulse generator: Injects microsecond-level glitches (< 1 clock cycle) and valid pulses (> 2 clock cycles) to verify 2-flop synchronizer filtering.
* **Monitor & Scoreboard:**
  * Compares written `GPIO_OUT` register values against physical `gpio_out` pin outputs within 2 clock cycles.
  * Verifies edge-triggered interrupt generation upon transitions on `gpio_in`.

### 2.6. Autonomous Power Management Monitor & SVA VIP (`pp_power_sva_vip`)
* **Monitored Nets:** `periph_activity[2:0]`, `periph_enable[2:0]`, `hap_idle[2:0]`, `periph_wake[2:0]`, `wakeup_req`, PPMC state register.
* **Key Assertions & Checks:**
  1. **Wakeup Latency SVA:**
     $$\text{assert property } (@(\text{posedge clk}) \ |periph\_wake \ \vert=> \ wakeup\_req);$$
     Verifies that any wake trigger on `periph_wake` produces a `wakeup_req` pulse within exactly 1 clock cycle.
  2. **Clock-Enable Restoration SVA:**
     $$\text{assert property } (@(\text{posedge clk}) \ wakeup\_req \ \vert=> \ (periph\_enable == 3'b111));$$
     Verifies that when `wakeup_req` asserts, `pp_ppmc` immediately restores all peripheral enables.
  3. **Zero Activity Advances During Low-Power SVA:**
     $$\text{assert property } (@(\text{posedge clk}) \ (periph\_enable[0] == 0) \ \vert=> \ \$stable(timer\_count));$$
     Verifies that gated peripherals hold their state completely stable without spurious toggles.

---

## 3. Mapping of VIPs to SoC Interfaces

| Interface Name | Connected VIP | VIP Role | Coverage Metrics |
|---|---|---|---|
| Master Clock & Reset | `pp_clk_rst_vip` | Active Driver | Frequency range, Reset pulse widths |
| VeeR EL2 Instruction Master | `pp_axi_master_vip` (M0) | Active Driver / Passive Monitor | Instruction fetch bursts, latency |
| VeeR EL2 Load/Store Master | `pp_axi_master_vip` (M1) | Active Driver / Passive Monitor | MMIO reads/writes, backpressure |
| VeeR EL2 System Bus Master | `pp_axi_master_vip` (M2) | Active Driver / Passive Monitor | DMA transfers, arbitration |
| On-Chip SRAM (IMEM/DMEM) | `pp_axi_slave_vip` | Passive Monitor / Backdoor Model | Address coverage, write strobes |
| UART Serial Interface | `pp_uart_vip` | Active Driver & Monitor | Baud accuracy, TX/RX framing |
| GPIO Parallel Pins | `pp_gpio_vip` | Active Driver & Monitor | Pin patterns, edge detection |
| Inter-IP Power Subsystem | `pp_power_sva_vip` | Passive Monitor & Formal SVA | FSM state coverage, wake latency |
