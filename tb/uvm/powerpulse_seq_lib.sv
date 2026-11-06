// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_seq_lib.sv
// Description: UVM Sequence Library (Reset, GPIO Walking, UART Stimulus, Wake Stress)
// ==============================================================================

`ifndef POWERPULSE_SEQ_LIB_SV
`define POWERPULSE_SEQ_LIB_SV

// ------------------------------------------------------------------------------
// Base Sequence
// ------------------------------------------------------------------------------
class powerpulse_base_seq extends uvm_sequence #(powerpulse_seq_item);

    `uvm_object_utils(powerpulse_base_seq)

    function new(string name = "powerpulse_base_seq");
        super.new(name);
    endfunction: new

endclass: powerpulse_base_seq

// ------------------------------------------------------------------------------
// Sequence: Reset Pulse
// ------------------------------------------------------------------------------
class powerpulse_reset_seq extends powerpulse_base_seq;

    `uvm_object_utils(powerpulse_reset_seq)

    rand int unsigned rst_cycles;

    constraint c_rst {
        rst_cycles inside {[10 : 30]};
    }

    function new(string name = "powerpulse_reset_seq");
        super.new(name);
        rst_cycles = 20;
    endfunction: new

    virtual task body();
        powerpulse_seq_item req_item = powerpulse_seq_item::type_id::create("rst_item");
        start_item(req_item);
        req_item.trans_type            = powerpulse_seq_item::TRANS_RESET_PULSE;
        req_item.reset_duration_cycles = rst_cycles;
        finish_item(req_item);
    endtask: body

endclass: powerpulse_reset_seq

// ------------------------------------------------------------------------------
// Sequence: GPIO Walking Ones & Zeros
// ------------------------------------------------------------------------------
class powerpulse_gpio_walk_seq extends powerpulse_base_seq;

    `uvm_object_utils(powerpulse_gpio_walk_seq)

    function new(string name = "powerpulse_gpio_walk_seq");
        super.new(name);
    endfunction: new

    virtual task body();
        powerpulse_seq_item req_item;
        int i;

        // Walking 1s across 8 pins
        for (i = 0; i < 8; i++) begin
            req_item = powerpulse_seq_item::type_id::create($sformatf("gpio_walk1_%0d", i));
            start_item(req_item);
            req_item.trans_type   = powerpulse_seq_item::TRANS_GPIO_IN;
            req_item.gpio_data    = (8'h01 << i);
            req_item.delay_cycles = 50;
            finish_item(req_item);
        end

        // Return to 0
        req_item = powerpulse_seq_item::type_id::create("gpio_zero");
        start_item(req_item);
        req_item.trans_type   = powerpulse_seq_item::TRANS_GPIO_IN;
        req_item.gpio_data    = 8'h00;
        req_item.delay_cycles = 100;
        finish_item(req_item);
    endtask: body

endclass: powerpulse_gpio_walk_seq

// ------------------------------------------------------------------------------
// Sequence: UART Hello Stream
// ------------------------------------------------------------------------------
class powerpulse_uart_hello_seq extends powerpulse_base_seq;

    `uvm_object_utils(powerpulse_uart_hello_seq)

    string msg = "POWERPULSE\n";

    function new(string name = "powerpulse_uart_hello_seq");
        super.new(name);
    endfunction: new

    virtual task body();
        powerpulse_seq_item req_item;
        int i;

        for (i = 0; i < msg.len(); i++) begin
            req_item = powerpulse_seq_item::type_id::create($sformatf("uart_char_%0d", i));
            start_item(req_item);
            req_item.trans_type = powerpulse_seq_item::TRANS_UART_TX;
            req_item.uart_byte  = msg[i];
            finish_item(req_item);
        end
    endtask: body

endclass: powerpulse_uart_hello_seq

// ------------------------------------------------------------------------------
// Sequence: Autonomous Power Management Stress Sequence
// ------------------------------------------------------------------------------
class powerpulse_wake_stress_seq extends powerpulse_base_seq;

    `uvm_object_utils(powerpulse_wake_stress_seq)

    rand int unsigned num_iterations;

    constraint c_iter {
        num_iterations inside {[5 : 20]};
    }

    function new(string name = "powerpulse_wake_stress_seq");
        super.new(name);
        num_iterations = 10;
    endfunction: new

    virtual task body();
        powerpulse_seq_item req_item;
        int iter;

        for (iter = 0; iter < num_iterations; iter++) begin
            req_item = powerpulse_seq_item::type_id::create($sformatf("wake_item_%0d", iter));
            start_item(req_item);
            assert(req_item.randomize());
            finish_item(req_item);
        end
    endtask: body

endclass: powerpulse_wake_stress_seq

`endif // POWERPULSE_SEQ_LIB_SV
