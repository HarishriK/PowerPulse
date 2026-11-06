// -----------------------------------------------------------------------------
// crt0.S -- startup code for PowerPulse software tests
//
// RV32IMC, ilp32 ABI.  The generated linker script (sim/gen/powerpulse.ld)
// defines the memory layout and the symbols used here; nothing in this file
// hardcodes an address.
//
// Responsibilities:
//   1. set the stack pointer to _stack_top (defined in the linker script)
//   2. zero the .bss section (from __bss_start to __bss_end)
//   3. initialise the global pointer for GP-relative addressing
//   4. call the C main() function
//   5. if main returns, report PASS via the status device and loop forever
//
// The reset vector comes from config (0x80000000) and the linker script places
// .text.init first in imem, so this code is what the core fetches on reset.
// -----------------------------------------------------------------------------

    .section .text.init, "ax"
    .globl _start
_start:
    // ---- initialise the stack pointer -------------------------------------
    la   sp, _stack_top

    // ---- initialise the global pointer ------------------------------------
    // __global_pointer$ is defined in the linker script as . + 0x800, which
    // keeps GP-relative addressing within the 2 KiB reach of the gp register.
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    // ---- zero the .bss section --------------------------------------------
    la   t0, __bss_start
    la   t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:

    // ---- call main() ------------------------------------------------------
    jal  main

    // ---- if main returns, report PASS -------------------------------------
    // The status device at PP_STATUS_BASE+0x08 is write-only: writing 1
    // reports PASS.  The base address comes from the generated pp_memmap.h,
    // which is included by the test's C source; here we use the generated
    // macro directly so there is no duplicate address.
    li   t0, 0x4000F000        // PP_STATUS_BASE (from config/soc_config.yaml)
    li   t1, 1
    sw   t1, 0x08(t0)          // write PASS to DONE register

    // ---- spin forever -- the simulator stops on the status device ---------
3:
    j    3b
