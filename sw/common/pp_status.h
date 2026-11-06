// pp_status.h -- simulation status device driver for software tests
//
// The status device is a simulation-only AXI4-Lite slave at PP_STATUS_BASE
// (defined in the generated pp_memmap.h).  Software writes PASS/FAIL to end
// the simulation with a machine-readable PP_RESULT line.
#ifndef PP_STATUS_H
#define PP_STATUS_H
#include <stdint.h>
#include "pp_memmap.h"

// Register offsets (relative to PP_STATUS_BASE)
//   0x04  CODE   WO   bits[7:0]  exit / diagnostic code
//   0x08  DONE   WO   bit0 PASS  write 1 = pass, write 0 = fail

static inline void pp_status_pass(void) {
    *(volatile uint32_t*)(PP_STATUS_BASE + 0x08) = 1;
}

static inline void pp_status_fail(uint32_t code) {
    *(volatile uint32_t*)(PP_STATUS_BASE + 0x04) = code;
    *(volatile uint32_t*)(PP_STATUS_BASE + 0x08) = 0;
}

#endif
