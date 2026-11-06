// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_agent.sv
// Description: UVM Agent instantiating driver, monitor, and sequencer
// ==============================================================================

`ifndef POWERPULSE_AGENT_SV
`define POWERPULSE_AGENT_SV

class powerpulse_agent extends uvm_agent;

    `uvm_component_utils(powerpulse_agent)

    powerpulse_driver    driver;
    powerpulse_sequencer sequencer;
    powerpulse_monitor   monitor;

    uvm_analysis_port #(powerpulse_seq_item) item_collected_port;

    function new(string name = "powerpulse_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = powerpulse_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            driver    = powerpulse_driver::type_id::create("driver", this);
            sequencer = powerpulse_sequencer::type_id::create("sequencer", this);
        end
    endfunction: build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        item_collected_port = monitor.item_collected_port;

        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction: connect_phase

endclass: powerpulse_agent

`endif // POWERPULSE_AGENT_SV
