// -----------------------------------------------------------------------------
// pp_uart.h -- minimal UART driver for the PowerPulse software tests
//
// The UART is the vendored BSC/CIC-IPN AXI4-Lite UART at the address defined
// in config/soc_config.yaml (generated into pp_memmap.h as PP_UART_BASE).
//
// Register map (byte offsets; the IP decodes addr[4:2]):
//   0x00  RBR (read)  / THR (write)   receive / transmit data register
//   0x04  IER                           interrupt enable register
//   0x08  BAUD_DIVISOR                  baud divisor (only accessible when DLAB=1)
//   0x0C  LCR                           line control register
//   0x14  LSR (read-only)               line status register
//
// LSR bit definitions:
//   bit 0  DATA_READY  a complete character has been received
//   bit 5  THRE        transmit holding register empty (ready for next byte)
//   bit 6  TEMT        transmitter empty (FIFO drained + shift reg empty)
//
// The UART IP initialises the baud divisor from the generated macro
// _UART_BAUDRATE_DIV_INIT_ (= clock / baud = 100 MHz / 115200 = 868), so no
// runtime configuration is needed for the default baud rate.
// -----------------------------------------------------------------------------
#ifndef PP_UART_H
#define PP_UART_H

#include <stdint.h>
#include "pp_memmap.h"

// ---- register offsets (byte addresses relative to PP_UART_BASE) -------------
#define PP_UART_REG_RBR      0x00u   // receive buffer register (read)
#define PP_UART_REG_THR      0x00u   // transmit holding register (write)
#define PP_UART_REG_IER      0x04u   // interrupt enable register
#define PP_UART_REG_BAUD_DIV 0x08u   // baud divisor (DLAB must be set)
#define PP_UART_REG_LCR      0x0Cu   // line control register
#define PP_UART_REG_LSR      0x14u   // line status register (read-only)

// ---- LSR bit masks ----------------------------------------------------------
#define PP_UART_LSR_DATA_READY  0x01u   // bit 0: a character has been received
#define PP_UART_LSR_THRE        0x20u   // bit 5: transmit holding register empty
#define PP_UART_LSR_TEMT        0x40u   // bit 6: transmitter completely idle

// ---- convenience register accessors ----------------------------------------
static inline void pp_uart_write_reg(uint32_t offset, uint32_t value) {
    *(volatile uint32_t*)(PP_UART_BASE + offset) = value;
}

static inline uint32_t pp_uart_read_reg(uint32_t offset) {
    return *(volatile uint32_t*)(PP_UART_BASE + offset);
}

// ---- transmit one character, polling THRE -----------------------------------
static inline void pp_uart_putc(char c) {
    // Wait for the transmit holding register to be empty before writing.
    while ((pp_uart_read_reg(PP_UART_REG_LSR) & PP_UART_LSR_THRE) == 0) {
        // spin until the transmitter can accept a byte
    }
    pp_uart_write_reg(PP_UART_REG_THR, (uint32_t)(uint8_t)c);
}

// ---- transmit a NUL-terminated string ---------------------------------------
static inline void pp_uart_puts(const char *s) {
    while (*s) {
        pp_uart_putc(*s);
        s++;
    }
}

// ---- flush: wait for the transmitter to finish sending ----------------------
static inline void pp_uart_flush(void) {
    while ((pp_uart_read_reg(PP_UART_REG_LSR) & PP_UART_LSR_TEMT) == 0) {
        // spin until the transmitter is completely empty
    }
}

#endif // PP_UART_H
