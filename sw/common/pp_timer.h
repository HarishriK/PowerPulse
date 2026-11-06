// -----------------------------------------------------------------------------
// pp_timer.h -- System Timer driver for PowerPulse SoC
// -----------------------------------------------------------------------------
#ifndef PP_TIMER_H
#define PP_TIMER_H

#include <stdint.h>
#include "pp_memmap.h"

#define PP_TIMER_REG_CTRL    0x00u  // [0] EN, [1] AUTO_RELOAD, [2] IRQ_EN
#define PP_TIMER_REG_LOAD    0x04u  // [31:0] Reload value
#define PP_TIMER_REG_COUNT   0x08u  // [31:0] Current count (RO)
#define PP_TIMER_REG_STATUS  0x0Cu  // [0] Overflow/Compare match (RO)
#define PP_TIMER_REG_IRQ_CLR 0x10u  // [0] Clear overflow and IRQ (WO)

#define PP_TIMER_CTRL_EN          0x01u
#define PP_TIMER_CTRL_AUTO_RELOAD 0x02u
#define PP_TIMER_CTRL_IRQ_EN      0x04u

static inline void pp_timer_write_reg(uint32_t offset, uint32_t val) {
    *(volatile uint32_t*)(PP_TIMER_BASE + offset) = val;
}

static inline uint32_t pp_timer_read_reg(uint32_t offset) {
    return *(volatile uint32_t*)(PP_TIMER_BASE + offset);
}

static inline void pp_timer_init(uint32_t load_val, uint32_t ctrl_flags) {
    pp_timer_write_reg(PP_TIMER_REG_LOAD, load_val);
    pp_timer_write_reg(PP_TIMER_REG_CTRL, ctrl_flags);
}

static inline uint32_t pp_timer_get_count(void) {
    return pp_timer_read_reg(PP_TIMER_REG_COUNT);
}

static inline uint32_t pp_timer_is_overflow(void) {
    return pp_timer_read_reg(PP_TIMER_REG_STATUS) & 0x01u;
}

static inline void pp_timer_clear_overflow(void) {
    pp_timer_write_reg(PP_TIMER_REG_IRQ_CLR, 0x01u);
}

#endif // PP_TIMER_H
