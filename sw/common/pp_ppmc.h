// -----------------------------------------------------------------------------
// pp_ppmc.h -- Peripheral Power Management Controller (PPMC) driver
// -----------------------------------------------------------------------------
#ifndef PP_PPMC_H
#define PP_PPMC_H

#include <stdint.h>
#include "pp_memmap.h"

#define PP_PPMC_REG_CTRL      0x00u  // [0] Global enable
#define PP_PPMC_REG_POLICY    0x04u  // [0] 1: Autonomous hardware, 0: Manual software
#define PP_PPMC_REG_PERIPH_EN 0x08u  // [2:0] Manual periph enable / clock enable
#define PP_PPMC_REG_STATE     0x0Cu  // [5:0] 2-bit state per periph: 00:ACTIVE, 01:IDLE, 10:LOW-ACT
#define PP_PPMC_REG_WAKE_MASK 0x10u  // [2:0] Permitted wake sources mask

#define PP_PPMC_STATE_ACTIVE       0x00u
#define PP_PPMC_STATE_IDLE         0x01u
#define PP_PPMC_STATE_LOW_ACTIVITY 0x02u

static inline void pp_ppmc_write_reg(uint32_t offset, uint32_t val) {
    *(volatile uint32_t*)(PP_PPMC_BASE + offset) = val;
}

static inline uint32_t pp_ppmc_read_reg(uint32_t offset) {
    return *(volatile uint32_t*)(PP_PPMC_BASE + offset);
}

static inline void pp_ppmc_init_auto(uint8_t wake_mask) {
    pp_ppmc_write_reg(PP_PPMC_REG_WAKE_MASK, wake_mask);
    pp_ppmc_write_reg(PP_PPMC_REG_POLICY, 0x01u); // Autonomous mode
    pp_ppmc_write_reg(PP_PPMC_REG_CTRL, 0x01u);   // Enable PPMC
}

static inline uint8_t pp_ppmc_get_periph_state(uint8_t periph_index) {
    uint32_t states = pp_ppmc_read_reg(PP_PPMC_REG_STATE);
    return (uint8_t)((states >> (periph_index * 2)) & 0x03u);
}

static inline uint8_t pp_ppmc_get_enables(void) {
    return (uint8_t)(pp_ppmc_read_reg(PP_PPMC_REG_PERIPH_EN) & 0x07u);
}

#endif // PP_PPMC_H
