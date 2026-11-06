// -----------------------------------------------------------------------------
// pp_awec.h -- Autonomous Wake-Up Event Controller (AWEC) driver
// -----------------------------------------------------------------------------
#ifndef PP_AWEC_H
#define PP_AWEC_H

#include <stdint.h>
#include "pp_memmap.h"

#define PP_AWEC_REG_CTRL     0x00u  // [0] Wake monitoring global enable
#define PP_AWEC_REG_ENABLE   0x04u  // [2:0] Enable wake source (bit 0: UART, 1: Timer, 2: GPIO)
#define PP_AWEC_REG_STATUS   0x08u  // [2:0] Pending wake event flags (RO)
#define PP_AWEC_REG_EVENT_ID 0x0Cu  // [1:0] Latched wake source ID (1:UART, 2:Timer, 3:GPIO)
#define PP_AWEC_REG_ACK      0x10u  // [2:0] Write-1-to-clear / acknowledge serviced event

#define PP_AWEC_SRC_NONE  0x00u
#define PP_AWEC_SRC_UART  0x01u
#define PP_AWEC_SRC_TIMER 0x02u
#define PP_AWEC_SRC_GPIO  0x03u

static inline void pp_awec_write_reg(uint32_t offset, uint32_t val) {
    *(volatile uint32_t*)(PP_AWEC_BASE + offset) = val;
}

static inline uint32_t pp_awec_read_reg(uint32_t offset) {
    return *(volatile uint32_t*)(PP_AWEC_BASE + offset);
}

static inline void pp_awec_init(uint8_t enabled_sources_mask) {
    pp_awec_write_reg(PP_AWEC_REG_ENABLE, enabled_sources_mask);
    pp_awec_write_reg(PP_AWEC_REG_CTRL, 0x01u); // Enable AWEC
}

static inline uint8_t pp_awec_get_pending_events(void) {
    return (uint8_t)(pp_awec_read_reg(PP_AWEC_REG_STATUS) & 0x07u);
}

static inline uint8_t pp_awec_get_captured_source(void) {
    return (uint8_t)(pp_awec_read_reg(PP_AWEC_REG_EVENT_ID) & 0x03u);
}

static inline void pp_awec_ack_event(uint8_t ack_mask) {
    pp_awec_write_reg(PP_AWEC_REG_ACK, ack_mask);
}

#endif // PP_AWEC_H
