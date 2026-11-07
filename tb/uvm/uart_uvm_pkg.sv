`timescale 1ns/1ps

package uart_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "uart_seq_item.sv"
    `include "uart_sequencer.sv"
    `include "uart_driver.sv"
    `include "uart_monitor.sv"
    `include "uart_agent.sv"
    `include "uart_scoreboard.sv"
    `include "uart_env.sv"
    `include "uart_seq_lib.sv"
    `include "uart_base_test.sv"

endpackage: uart_uvm_pkg
