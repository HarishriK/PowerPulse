// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_power_test.sv
// Description: UVM Test stressing autonomous power-management wake/sleep sequences
// ==============================================================================

`ifndef POWERPULSE_POWER_TEST_SV
`define POWERPULSE_POWER_TEST_SV

class powerpulse_power_test extends powerpulse_base_test;

    `uvm_component_utils(powerpulse_power_test)

    function new(string name = "powerpulse_power_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual task run_phase(uvm_phase phase);
        powerpulse_reset_seq       rst_seq;
        powerpulse_wake_stress_seq stress_seq;

        phase.raise_objection(this, "Starting powerpulse_power_test");

        `uvm_info(get_type_name(), "=== [POWER TEST]: Driving Initial System Reset ===", UVM_LOW)
        rst_seq = powerpulse_reset_seq::type_id::create("rst_seq");
        rst_seq.start(env.agent.sequencer);

        `uvm_info(get_type_name(), "=== [POWER TEST]: Launching Autonomous Power Wake Stress Sequence ===", UVM_LOW)
        stress_seq = powerpulse_wake_stress_seq::type_id::create("stress_seq");
        stress_seq.num_iterations = 25;
        stress_seq.start(env.agent.sequencer);

        #100000ns; // Wait for autonomous state transitions and firmware handling

        `uvm_info(get_type_name(), "=== [POWER TEST COMPLETE]: Dropping Objection ===", UVM_LOW)
        phase.drop_objection(this, "Completed powerpulse_power_test");
    endtask: run_phase

endclass: powerpulse_power_test

`endif // POWERPULSE_POWER_TEST_SV
