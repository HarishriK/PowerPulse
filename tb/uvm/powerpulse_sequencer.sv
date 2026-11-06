// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_sequencer.sv
// Description: UVM Sequencer for PowerPulse SoC
// ==============================================================================

`ifndef POWERPULSE_SEQUENCER_SV
`define POWERPULSE_SEQUENCER_SV

class powerpulse_sequencer extends uvm_sequencer #(powerpulse_seq_item);

    `uvm_component_utils(powerpulse_sequencer)

    function new(string name = "powerpulse_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

endclass: powerpulse_sequencer

`endif // POWERPULSE_SEQUENCER_SV
