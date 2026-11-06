// -----------------------------------------------------------------------------
// pp_gpio.h -- GPIO driver for PowerPulse SoC
// -----------------------------------------------------------------------------
#ifndef PP_GPIO_H
#define PP_GPIO_H

#include <stdint.h>
#include "pp_memmap.h"

#define PP_GPIO_REG_DIR     0x00u  // [7:0] Direction (1: output, 0: input)
#define PP_GPIO_REG_OUT     0x04u  // [7:0] Output data
#define PP_GPIO_REG_IN      0x08u  // [7:0] Synchronized input data (RO)
#define PP_GPIO_REG_INTCFG  0x0Cu  // [7:0] Edge cfg (0: rising, 1: falling)
#define PP_GPIO_REG_INTEN   0x10u  // [7:0] Interrupt enable per pin
#define PP_GPIO_REG_INTSTAT 0x14u  // [7:0] Interrupt status (RO)
#define PP_GPIO_REG_INTCLR  0x18u  // [7:0] Write-1-to-clear interrupt status

static inline void pp_gpio_write_reg(uint32_t offset, uint32_t val) {
    *(volatile uint32_t*)(PP_GPIO_BASE + offset) = val;
}

static inline uint32_t pp_gpio_read_reg(uint32_t offset) {
    return *(volatile uint32_t*)(PP_GPIO_BASE + offset);
}

static inline void pp_gpio_set_dir(uint8_t dir_mask) {
    pp_gpio_write_reg(PP_GPIO_REG_DIR, dir_mask);
}

static inline void pp_gpio_write(uint8_t out_val) {
    pp_gpio_write_reg(PP_GPIO_REG_OUT, out_val);
}

static inline uint8_t pp_gpio_read(void) {
    return (uint8_t)pp_gpio_read_reg(PP_GPIO_REG_IN);
}

static inline void pp_gpio_config_interrupt(uint8_t pin_mask, uint8_t falling_edge_mask) {
    pp_gpio_write_reg(PP_GPIO_REG_INTCFG, falling_edge_mask);
    pp_gpio_write_reg(PP_GPIO_REG_INTEN, pin_mask);
}

static inline void pp_gpio_clear_interrupt(uint8_t pin_mask) {
    pp_gpio_write_reg(PP_GPIO_REG_INTCLR, pin_mask);
}

#endif // PP_GPIO_H
