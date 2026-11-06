// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_base_test.sv
// Description: Base UVM Test instantiating env, configuring phases, running sequences
// ==============================================================================

`ifndef POWERPULSE_BASE_TEST_SV
`define POWERPULSE_BASE_TEST_SV

class powerpulse_base_test extends uvm_test;

    `uvm_component_utils(powerpulse_base_test)

    powerpulse_env env;

    function new(string name = "powerpulse_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = powerpulse_env::type_id::create("env", this);
    endfunction: build_phase

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction: end_of_elaboration_phase

    virtual task run_phase(uvm_phase phase);
        powerpulse_reset_seq     rst_seq;
        powerpulse_gpio_walk_seq gpio_seq;
        powerpulse_uart_hello_seq uart_seq;

        phase.raise_objection(this, "Starting powerpulse_base_test");

        `uvm_info(get_type_name(), "=== [TEST STEP 1]: Executing Reset Sequence ===", UVM_LOW)
        rst_seq = powerpulse_reset_seq::type_id::create("rst_seq");
        rst_seq.start(env.agent.sequencer);

        `uvm_info(get_type_name(), "=== [TEST STEP 2]: Executing GPIO Walking Pattern ===", UVM_LOW)
        gpio_seq = powerpulse_gpio_walk_seq::type_id::create("gpio_seq");
        gpio_seq.start(env.agent.sequencer);

        `uvm_info(get_type_name(), "=== [TEST STEP 3]: Executing UART Character Injection ===", UVM_LOW)
        uart_seq = powerpulse_uart_hello_seq::type_id::create("uart_seq");
        uart_seq.start(env.agent.sequencer);

        #50000ns; // Drain time for pipeline & scoreboard

        `uvm_info(get_type_name(), "=== [TEST COMPLETE]: Dropping Objection ===", UVM_LOW)
        phase.drop_objection(this, "Completed powerpulse_base_test");
    endtask: run_phase

endclass: powerpulse_base_test

`endif // POWERPULSE_BASE_TEST_SV
