// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_env.sv
// Description: Top-level UVM Environment containing agent, scoreboard, and coverage
// ==============================================================================

`ifndef POWERPULSE_ENV_SV
`define POWERPULSE_ENV_SV

class powerpulse_env extends uvm_env;

    `uvm_component_utils(powerpulse_env)

    powerpulse_agent      agent;
    powerpulse_scoreboard scoreboard;
    powerpulse_coverage   coverage;

    function new(string name = "powerpulse_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = powerpulse_agent::type_id::create("agent", this);
        scoreboard = powerpulse_scoreboard::type_id::create("scoreboard", this);
        coverage   = powerpulse_coverage::type_id::create("coverage", this);
    endfunction: build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.item_collected_port.connect(scoreboard.item_collected_export);
        agent.item_collected_port.connect(coverage.analysis_export);
    endfunction: connect_phase

endclass: powerpulse_env

`endif // POWERPULSE_ENV_SV
