# PowerPulse SoC: External Interfaces Specification

**Project:** PowerPulse — Adaptive Low-Power-Aware RISC-V System-on-Chip  
**Document Reference:** `docs/architecture/EXTERNAL_INTERFACES.md`  
**SoC Boundary Module:** `rtl/top/powerpulse_soc.sv`  

---

## 1. Overview

The PowerPulse SoC communicates with the external world through 4 distinct physical and logical interfaces across 20 package pins:
1. **System Clock & Reset Interface** (`clk`, `rst_n`) — 2 pins
2. **UART Serial Communication Interface** (`uart_rx`, `uart_tx`) — 2 pins
3. **General Purpose Input/Output (GPIO) Interface** (`gpio_in[7:0]`, `gpio_out[7:0]`) — 16 pins
4. **External Interrupt & Observability Interface** (`timer_irq`, `gpio_irq`) — 2 pins

This specification outlines the electrical specifications, timing diagrams, protocol framing, synchronization mechanisms, and verification hooks for each external interface.

---

## 2. System Clock & Reset Interface

### 2.1. Signal Definitions
* **`clk` (Input, 1-bit):** Single-ended CMOS input clock. Nominal frequency is **50 MHz** ($T_{\text{clk}} = 20\text{ ns}$). Supports operating range from 1 MHz to 100 MHz.
* **`rst_n` (Input, 1-bit):** Active-low master reset. Asynchronous assertion, synchronous de-assertion.

### 2.2. Electrical & Timing Characteristics
* **Clock Duty Cycle:** $50\% \pm 5\%$ ($45\%\text{--}55\%$).
* **Clock Rise/Fall Time ($t_r, t_f$):** $\le 2\text{ ns}$ (10% to 90%).
* **Reset Pulse Width ($t_{\text{rst_min}}$):** Minimum 5 clock cycles of `clk` must elapse while `rst_n` is asserted low (`0`).
* **Synchronous De-assertion:** Internally, `rst_n` is filtered through a standard dual-flop reset bridge to eliminate metastability on core release.

```
clk    : __/--\__/--\__/--\__/--\__/--\__/--\__/--\__/--\__
rst_n  : ------\________________________/-----------------
                <--- Min 5 Cycles ---->
Internal Reset: -------------------------\________/------- (Sync deassertion)
```

### 2.3. Reset State of SoC Peripherals
Upon release of `rst_n`:
* VeeR EL2 core begins instruction fetch at reset vector `0x8000_0000` (IMEM).
* All AXI channels are held in idle (`VALID` signals forced to `0`).
* HAP inactivity counters are initialized to zero.
* PPMC initializes to `STATE_ACTIVE` (`2'b00`) with `periph_enable[2:0] = 3'b111`.
* AWEC status register is cleared (`EVENT_ID = 0`).

---

## 3. UART Serial Interface

### 3.1. Signal Definitions
* **`uart_rx` (Input, 1-bit):** Serial input data line from external host or bridge.
* **`uart_tx` (Output, 1-bit):** Serial output data line to external terminal.

### 3.2. Protocol Framing & Signaling
* **Standard:** Universal Asynchronous Receiver-Transmitter (16550 compatible).
* **Framing Format:** **8-N-1** (1 Start bit, 8 Data bits, No Parity, 1 Stop bit).
* **Idle State:** Logic High (`1'b1`).
* **Start Bit:** Active Low transition (`1'b0`) for exactly 1 bit duration.
* **Data Bits:** 8 bits sent LSB first ($D0 \rightarrow D7$).
* **Stop Bit:** Logic High (`1'b1`) for minimum 1 bit duration.

```
UART Frame:
           Start                                Stop  Idle
Line:  111 | 0 | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | 1 | 111
```

### 3.3. Baud Rate Generation
The baud rate divisor register ($DL$) configures the bit period according to:
$$\text{Baud Rate} = \frac{f_{\text{clk}}}{16 \times DL}$$
* For $f_{\text{clk}} = 50\text{ MHz}$ and target baud of **115,200 bps**:
  $$DL = \text{round}\left(\frac{50\,000\,000}{16 \times 115\,200}\right) = \text{round}(27.1267) = 27 = 0x001B$$
* Actual baud rate: $50\,000\,000 / (16 \times 27) = 115\,740.7\text{ bps}$ ($+0.46\%$ error, well within the standard $\pm 2\%$ UART tolerance).

### 3.4. Metastability & Synchronization
* The incoming `uart_rx` asynchronous line passes through a 2-stage shift-register synchronizer clocked by `clk` before feeding the majority-voting receiver state machine.
* A 16x oversampling clock extracts data bits at the center of each bit period (sample point at cycle 8 of 16).

---

## 4. General Purpose Input/Output (GPIO) Interface

### 4.1. Signal Definitions
* **`gpio_in[7:0]` (Input, 8-bit):** Dedicated input port sampled from external physical switches, sensors, or test stimulus.
* **`gpio_out[7:0]` (Output, 8-bit):** Dedicated output port driving external LEDs, signals, or downstream hardware.

### 4.2. Input Architecture & Edge Detection
Each bit of `gpio_in[k]` is equipped with:
1. **Dual-Flop Synchronizer:** Mitigates metastability when asynchronous external pin changes occur near the active `clk` edge. Total sampling latency = 2 clock cycles ($40\text{ ns}$).
2. **Configurable Edge Detector:**
   * Programmable via `GPIO_INTEN` (Interrupt Enable) and `GPIO_INTTYPE` (0 = Level/Falling, 1 = Rising edge).
   * Generates a single-cycle pulse when the selected condition matches.
   * Feeds directly into:
     - The internal interrupt line `gpio_irq` to the CPU.
     - The autonomous power management wake signal `periph_wake[1]` to AWEC.

```
gpio_in[k] ---> [ Flop 1 ] ---> [ Flop 2 ] ---> [ Edge Detector ] ---> periph_wake[1]
                                     |                                   gpio_irq
                                     v
                            [ GPIO_IN Register ]
```

### 4.3. Output Register Architecture
* The `gpio_out[7:0]` port is driven by synchronous D-flip-flops updated via AXI4-Lite write transactions to `GPIO_OUT` (`0x4000_2004`).
* Slew rate and drive capacity: Standard 8 mA CMOS output drive cell compatible.

---

## 5. Interrupt & Observability Interface

### 5.1. Signal Definitions
* **`timer_irq` (Output, 1-bit):** Synchronous active-high interrupt output pulse from the hardware timer.
* **`gpio_irq` (Output, 1-bit):** Synchronous active-high interrupt output pulse from the GPIO module.

### 5.2. Functional Purpose
* **Core Interrupt Routing:** Internally, these interrupt lines, alongside AWEC's `wakeup_req`, feed the VeeR EL2 core's external interrupt controller (`ext_irq`).
* **External Board Observability:** Exposing these lines at the SoC boundary enables:
  1. Direct hookup to external Power Management ICs (PMICs) to exit deep sleep.
  2. Non-intrusive logic analyzer debugging without impacting bus traffic.
  3. Cycle-accurate performance and latency measurement in the verification testbench.

---

## 6. External Pin Summary Table

| Pin Name | Direction | Voltage Domain | Reset State | Drive Strength / Slew | Description |
|---|---|---|---|---|---|
| `clk` | Input | VDD_IO (3.3V / 1.8V) | N/A | High-Z (Schmitt trigger recommended) | Master 50 MHz input clock |
| `rst_n` | Input | VDD_IO | N/A | High-Z (Internal pull-up) | Active-low system reset |
| `uart_rx` | Input | VDD_IO | N/A | High-Z (Internal pull-up) | UART serial input |
| `uart_tx` | Output | VDD_IO | High (`1'b1`) | 4 mA, Fast slew | UART serial output |
| `gpio_in[7:0]` | Input | VDD_IO | N/A | High-Z | 8-bit digital inputs |
| `gpio_out[7:0]` | Output | VDD_IO | Low (`8'h00`)| 8 mA, Slew rate controlled | 8-bit digital outputs |
| `timer_irq` | Output | VDD_IO | Low (`1'b0`) | 4 mA | Timer overflow event pulse |
| `gpio_irq` | Output | VDD_IO | Low (`1'b0`) | 4 mA | GPIO edge event pulse |
