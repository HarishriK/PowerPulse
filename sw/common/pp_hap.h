// -----------------------------------------------------------------------------
// pp_hap.h -- Hardware Activity Profiler (HAP) driver for PowerPulse SoC
// -----------------------------------------------------------------------------
#ifndef PP_HAP_H
#define PP_HAP_H

#include <stdint.h>
#include "pp_memmap.h"

#define PP_HAP_REG_CTRL       0x00u  // [0] Global profiling enable
#define PP_HAP_REG_MANAGE_EN  0x04u  // [2:0] Monitored sources (bit 0: UART, 1: Timer, 2: GPIO)
#define PP_HAP_REG_IDLE_TH    0x08u  // [31:0] Inactivity threshold in clock cycles
#define PP_HAP_REG_IDLE_CNT   0x0Cu  // [31:0] Current inactivity counter (RO)
#define PP_HAP_REG_STATUS     0x10u  // [2:0] active flags, [6:4] idle flags (RO)

#define PP_HAP_PERIPH_UART    0x01u
#define PP_HAP_PERIPH_TIMER   0x02u
#define PP_HAP_PERIPH_GPIO    0x04u

static inline void pp_hap_write_reg(uint32_t offset, uint32_t val) {
    *(volatile uint32_t*)(PP_HAP_BASE + offset) = val;
}

static inline uint32_t pp_hap_read_reg(uint32_t offset) {
    return *(volatile uint32_t*)(PP_HAP_BASE + offset);
}

static inline void pp_hap_init(uint32_t threshold_cycles, uint8_t periph_mask) {
    pp_hap_write_reg(PP_HAP_REG_IDLE_TH, threshold_cycles);
    pp_hap_write_reg(PP_HAP_REG_MANAGE_EN, periph_mask);
    pp_hap_write_reg(PP_HAP_REG_CTRL, 0x01u); // Enable HAP
}

static inline uint32_t pp_hap_get_inactivity_count(void) {
    return pp_hap_read_reg(PP_HAP_REG_IDLE_CNT);
}

static inline uint8_t pp_hap_get_idle_status(void) {
    return (uint8_t)((pp_hap_read_reg(PP_HAP_REG_STATUS) >> 4) & 0x07u);
}

#endif // PP_HAP_H
