// -----------------------------------------------------------------------------
// uart_hello -- P1-12 Milestone B software test
//
// Purpose: prove the VeeR core can send a string through the UART and the
// testbench UART model decodes it exactly.  The core runs from the hex image
// loaded into instruction memory; all UART access goes through the downsizers
// and the AXI4-Lite bridge.
//
// The test prints "Hello UART\n" by polling the UART LSR THRE bit before each
// byte, then reports PASS through the simulation status device.
// -----------------------------------------------------------------------------
#include "pp_uart.h"
#include "pp_status.h"

static const char hello_msg[] = "Hello UART\n";

int main(void) {
    // Transmit the greeting string one character at a time.
    pp_uart_puts(hello_msg);

    // Wait for the last byte to leave the UART transmitter so the testbench
    // model has decoded it before we signal end-of-test.
    pp_uart_flush();

    // Report PASS through the simulation status device.  The status device
    // ends the simulation with PP_RESULT: PASS, which the regression runner
    // parses.
    pp_status_pass();

    // Should never reach here; pp_status_pass() finishes the simulation.
    return 0;
}
