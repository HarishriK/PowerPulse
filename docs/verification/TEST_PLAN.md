# PowerPulse SoC Verification Test Plan

**Project:** PowerPulse — Adaptive Low-Power-Aware RISC-V System-on-Chip  
**Core:** Western Digital VeeR EL2 (RV32IMC)  
**Target Simulator:** Synopsys VCS / Verdi (with UVM-1.2 & SystemVerilog SVA)  
**Status:** Complete & Sign-off Ready  

---

## 1. Overview and Verification Strategy

The PowerPulse verification environment utilizes a multi-layered verification strategy:
1. **Unit-Level Verification:** Standalone directed and constrained-random testbenches for each custom IP (HAP, PPMC, AWEC, Timer, GPIO, Adapters).
2. **Core-less Bus Integration Verification:** Standalone AXI master models driving the exact interconnect fabric to prove address decoding, arbitration, width conversions, and error responses without processor boot dependencies.
3. **Core-in-Loop Software Verification:** The real VeeR EL2 core running compiled RISC-V C firmware from hex images, communicating with peripherals and reporting PASS/FAIL via the status device.
4. **Autonomous Power Management Scenarios:** Closed-loop verification of the hardware activity profiling, inactivity threshold detection, clock-enable gating, and autonomous wake-up event restoration.
5. **UVM Constrained-Random Environment:** UVM testbench architecture with sequence items, drivers, monitors, scoreboards, and functional coverage models to stress interfaces under backpressure and random timing delays.

---

## 2. Test Plan Matrix

| Test ID | Test Name | Level | Type | Description | Key Checkpoints | Target Module | Pass Criteria |
|---|---|---|---|---|---|---|---|
| **TR-BUS-01** | `bus_decode_map` | SoC | Direct / Core-less | Verify reachability of all 9 slave slots at configured base addresses | All slaves respond with `OKAY` (2'b00); correct data read back | Interconnect crossbar | All base addresses return expected data |
| **TR-BUS-02** | `bus_unmapped_error` | SoC | Negative | Access unmapped regions and reserved gaps | Crossbar returns `DECERR` (2'b11); no bus hangs; watchdog clean | Default Stub Slave | `DECERR` returned within timeout |
| **TR-BUS-03** | `bus_arbitration` | SoC | Random / Core-less | Simultaneous requests from M0 (IFU), M1 (LSU), and M2 (SB) to same slave | Round-robin grant order; no master starvation; correct ID routing | Interconnect Arbiter | All 3 masters finish; zero data corruption |
| **TR-BUS-04** | `adapter_unit` | Unit | Direct / Random | 64-bit to 32-bit downsizer and AXI4-to-AXI4-Lite bridge verification | Correct lane routing; strobe byte-enables; burst splitting | Downsizer & Bridge | Read-back data matches written across widths |
| **TR-UART-01** | `uart_reg_rw` | Unit/SoC | Direct | Register access and reset values of UART IP | Reset values match 16550 spec; RW semantics | UART IP | All register reads match specification |
| **TR-UART-02** | `uart_tx_frame` | SoC | Direct | Character transmission at 115200 baud | Start bit, 8 data bits, stop bit framed properly; correct baud timing | UART Transmitter | UART BFM decodes exact transmitted bytes |
| **TR-UART-03** | `uart_rx_echo` | SoC | Direct | External injection of characters into `uart_rx` | Character latched in RBR; DATA_READY flag asserts; echo intact | UART Receiver | Received byte matches injected byte |
| **TR-TIM-01** | `timer_countdown` | Unit | Direct | Timer down-counter operation and auto-reload | Counter decrements each clock; reloads upon reaching 0 | Timer IP | `count_val` reaches 0; reload occurs |
| **TR-TIM-02** | `timer_overflow_irq` | Unit/SoC | Direct | Overflow flag assertion and core interrupt generation | `overflow` flag asserts; `timer_irq` pulses; `pp_wake_o` fires | Timer IP | Interrupt flag sets and clears via `IRQ_CLR` |
| **TR-TIM-03** | `timer_gating` | Unit | Direct | Inactivity gating via `pp_enable_i = 0` | Counter freezes during low-power mode; resumes when restored | Timer IP | Zero counter advances while enable is 0 |
| **TR-GPIO-01** | `gpio_output_drive` | Unit | Direct | Driving output pins via `GPIO_OUT` | Output pins match register data; direction mask enforced | GPIO IP | `gpio_out` equals written data |
| **TR-GPIO-02** | `gpio_edge_detect` | Unit/SoC | Direct | 2-flop sync and rising/falling edge capture | Edge detected on `gpio_in`; `INTSTAT` bit sets; `pp_wake_o` fires | GPIO IP | Edge detected within 3 clock cycles |
| **TR-HAP-01** | `hap_activity_reset` | Unit | Direct | Inactivity counter resets upon peripheral transaction | Counter resets to 0 on `periph_activity`; idle flag stays 0 | HAP IP | Inactivity counter resets on each pulse |
| **TR-HAP-02** | `hap_threshold_idle` | Unit/SoC | Direct | Counter reaches `HAP_IDLE_TH` during prolonged silence | `hap_idle[p]` asserts after exactly $N$ inactive cycles | HAP IP | `hap_idle` asserts when counter $\ge$ threshold |
| **TR-PPMC-01** | `ppmc_state_fsm` | Unit | Direct | State transitions `ACTIVE` $\rightarrow$ `IDLE` $\rightarrow$ `LOW-ACTIVITY` | State register reads correct 2-bit code; periph enable gated | PPMC IP | State code updates; `periph_enable` transitions to 0 |
| **TR-PPMC-02** | `ppmc_auto_restore` | Unit/SoC | Direct | Transition `LOW-ACTIVITY` $\rightarrow$ `ACTIVE` upon `wakeup_req` | Peripheral enable restored to 1 immediately upon wake request | PPMC IP | `periph_enable` restored within 1 clock cycle |
| **TR-AWEC-01** | `awec_wake_capture` | Unit | Direct | Asynchronous wake event capture from UART, Timer, GPIO | Event latched in `STATUS`; `EVENT_ID` records source ID; `wakeup_req` pulses | AWEC IP | Correct source ID (1:UART, 2:Timer, 3:GPIO) |
| **TR-AWEC-02** | `awec_ack_clear` | Unit | Direct | Software write to `AWEC_ACK` clears serviced event | Pending status clears; `EVENT_ID` resets to 0 | AWEC IP | Status bit clears to 0 |
| **TR-SYS-01** | `power_full_sequence`| SoC | Firmware | Full end-to-end autonomous power management demonstration | CPU boots; HAP detects idle; PPMC gates clocks; AWEC wakes; CPU logs telemetry | Full SoC | Simulation status device writes `PASS` |
| **TR-UVM-01** | `uvm_random_smoke` | UVM | Constrained Random | Randomized traffic across UART and GPIO boundary pins with protocol assertions | Zero protocol violations; scoreboard matches all data | Full SoC UVM Top | 100% scoreboard match; no SVA errors |
| **TR-UVM-02** | `uvm_power_stress` | UVM | Constrained Random | Randomized wake triggers injected during power state transitions | Race conditions resolved cleanly; state machine stability | Full SoC UVM Top | No deadlock; all events acknowledged |

---

## 3. Functional Coverage Goals

* **Code Coverage:** $\ge 95\%$ Line, Branch, and Condition coverage on all synthesizable RTL outside third-party core.
* **FSM Coverage:** $100\%$ state and transition coverage on PPMC (`ACTIVE` $\rightarrow$ `IDLE` $\rightarrow$ `LOW-ACTIVITY` $\rightarrow$ `ACTIVE`).
* **Cross-Coverage:**
  * Wake Source ID $\times$ Initial Peripheral Power State.
  * Inactivity Threshold values (min, typical, max) $\times$ Peripheral Type.
  * Simultaneous Wake Events from multiple sources.
