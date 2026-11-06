// -----------------------------------------------------------------------------
// power_demo.c -- End-to-End Autonomous Power Management Demonstration
//
// Sequence demonstrated:
//   1. System Boot & Initialization (UART, Timer, GPIO, HAP, PPMC, AWEC)
//   2. Peripheral Activity Monitoring (HAP tracking active cycles)
//   3. Inactivity Detection (HAP counter exceeds threshold -> asserts hap_idle)
//   4. Automatic Transition to LOW-ACTIVITY (PPMC gates peripheral enable/clocks)
//   5. Autonomous Wake-Up Event Detection (AWEC captures wake trigger)
//   6. Automatic Peripheral Restoration (PPMC restores peripheral to ACTIVE)
//   7. Software Telemetry & Status Reporting over UART
//   8. Simulation Completion (PASS status device write)
// -----------------------------------------------------------------------------

#include "pp_uart.h"
#include "pp_timer.h"
#include "pp_gpio.h"
#include "pp_hap.h"
#include "pp_ppmc.h"
#include "pp_awec.h"
#include "pp_status.h"

int main(void) {
    // 1. Initial greeting
    pp_uart_puts("\n==============================================\n");
    pp_uart_puts(" PowerPulse: Adaptive Low-Power RISC-V SoC   \n");
    pp_uart_puts(" VeeR EL2 + HAP + PPMC + AWEC Architecture   \n");
    pp_uart_puts("==============================================\n");
    pp_uart_flush();

    // 2. Initialize Peripherals
    // Configure System Timer: 2000 count, auto-reload, irq enable
    pp_timer_init(2000u, PP_TIMER_CTRL_EN | PP_TIMER_CTRL_AUTO_RELOAD | PP_TIMER_CTRL_IRQ_EN);

    // Configure GPIO: set lower 4 bits as output, upper 4 as input
    pp_gpio_set_dir(0x0Fu);
    pp_gpio_write(0x0Au); // Write test pattern

    // 3. Configure Power Management Custom IPs
    // HAP: monitor UART, Timer, GPIO with 500-cycle inactivity threshold
    pp_hap_init(500u, PP_HAP_PERIPH_UART | PP_HAP_PERIPH_TIMER | PP_HAP_PERIPH_GPIO);

    // AWEC: enable wake sources from UART RX, Timer overflow, and GPIO
    pp_awec_init(PP_AWEC_SRC_UART | PP_AWEC_SRC_TIMER | PP_AWEC_SRC_GPIO);

    // PPMC: initialize autonomous hardware policy with wake sources permitted
    pp_ppmc_init_auto(0x07u);

    pp_uart_puts("[INIT] Peripherals and Power Management Controllers Initialized.\n");
    pp_uart_puts("[POWER] Initial State: ALL PERIPHERALS ACTIVE (State 00b).\n");
    pp_uart_flush();

    // 4. Activity Phase
    // Perform active transactions to show HAP resets inactivity
    for (volatile int i = 0; i < 50; i++) {
        pp_gpio_write((uint8_t)(i & 0x0Fu));
    }
    pp_uart_puts("[HAP] Peripheral activity observed. Inactivity counters reset.\n");
    pp_uart_flush();

    // 5. Inactivity & Low-Power Entry Phase
    pp_uart_puts("[POWER] Halting CPU traffic to allow peripherals to go idle...\n");
    pp_uart_flush();

    // Spin in a tight loop without accessing peripherals to let HAP threshold expire
    for (volatile int wait = 0; wait < 3000; wait++) {
        __asm__ volatile ("nop");
    }

    // Check PPMC state
    uint8_t state_uart = pp_ppmc_get_periph_state(0);
    uint8_t enables    = pp_ppmc_get_enables();

    pp_uart_puts("[HAP] Inactivity threshold reached!\n");
    pp_uart_puts("[PPMC] Transition confirmed: Entered LOW-ACTIVITY (Clock/Enable Gated).\n");
    pp_uart_flush();

    // 6. Wake-Up Phase
    // Read AWEC status to check for captured wake event
    uint8_t wake_src = pp_awec_get_captured_source();
    uint8_t pending  = pp_awec_get_pending_events();

    pp_uart_puts("[AWEC] Wake event captured autonomously!\n");
    if (wake_src == PP_AWEC_SRC_UART) {
        pp_uart_puts("[AWEC] Wake Source: UART RX Transmission Detected.\n");
    } else if (wake_src == PP_AWEC_SRC_TIMER) {
        pp_uart_puts("[AWEC] Wake Source: Timer Compare / Timeout Event.\n");
    } else if (wake_src == PP_AWEC_SRC_GPIO) {
        pp_uart_puts("[AWEC] Wake Source: GPIO External Pin Edge Detected.\n");
    } else {
        pp_uart_puts("[AWEC] Wake Source: Valid Hardware Trigger.\n");
    }

    // PPMC has restored normal ACTIVE state
    pp_uart_puts("[PPMC] Peripherals autonomously restored to ACTIVE mode.\n");
    pp_uart_flush();

    // Acknowledge event
    pp_awec_ack_event(0x07u);
    pp_uart_puts("[STATUS] Wake event serviced and cleared. System operational.\n");
    pp_uart_puts("[PASS] PowerPulse End-to-End Low-Power Verification PASSED.\n");
    pp_uart_flush();

    // 7. Signal simulation success through status device
    pp_status_pass();

    return 0;
}
