// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_uvm_pkg.sv
// Description: UVM Package encapsulating items, components, sequences, and tests
// ==============================================================================

`timescale 1ns/1ps

package powerpulse_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Sequence Items & Components
    `include "powerpulse_seq_item.sv"
    `include "powerpulse_sequencer.sv"
    `include "powerpulse_driver.sv"
    `include "powerpulse_monitor.sv"
    `include "powerpulse_coverage.sv"
    `include "powerpulse_scoreboard.sv"
    `include "powerpulse_agent.sv"
    `include "powerpulse_env.sv"

    // Sequences & Tests
    `include "powerpulse_seq_lib.sv"
    `include "powerpulse_base_test.sv"
    `include "powerpulse_power_test.sv"

endpackage: powerpulse_uvm_pkg
