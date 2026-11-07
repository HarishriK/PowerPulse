`ifndef UART_BASE_TEST_SV
`define UART_BASE_TEST_SV

class uart_base_test extends uvm_test;
    `uvm_component_utils(uart_base_test)

    uart_env env;

    function new(string name = "uart_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        uart_reset_seq  rst_seq;
        uart_string_seq str_seq;

        phase.raise_objection(this, "Starting uart_base_test");

        `uvm_info(get_type_name(), "=== [UART TEST STEP 1]: Executing Interface Reset Sequence ===", UVM_LOW)
        rst_seq = uart_reset_seq::type_id::create("rst_seq");
        rst_seq.start(env.agent.sequencer);

        `uvm_info(get_type_name(), "=== [UART TEST STEP 2]: Transmitting Serial Byte Stream ===", UVM_LOW)
        str_seq = uart_string_seq::type_id::create("str_seq");
        str_seq.start(env.agent.sequencer);

        #50000ns;

        `uvm_info(get_type_name(), "=== [UART TEST COMPLETE]: Dropping Objection ===", UVM_LOW)
        phase.drop_objection(this, "Completed uart_base_test");
    endtask
endclass

`endif
