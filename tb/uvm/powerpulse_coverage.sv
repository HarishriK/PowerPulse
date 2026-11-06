// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_coverage.sv
// Description: UVM Subscriber collecting functional coverage metrics
// ==============================================================================

`ifndef POWERPULSE_COVERAGE_SV
`define POWERPULSE_COVERAGE_SV

class powerpulse_coverage extends uvm_subscriber #(powerpulse_seq_item);

    `uvm_component_utils(powerpulse_coverage)

    powerpulse_seq_item cov_item;

    // --------------------------------------------------------------------------
    // Covergroups
    // --------------------------------------------------------------------------
    covergroup cg_soc_boundary;
        option.per_instance = 1;

        // GPIO Input stimulus coverage
        cp_gpio_in: coverpoint cov_item.gpio_data {
            bins zero     = {8'h00};
            bins all_ones = {8'hFF};
            bins walking_ones[] = {8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80};
            bins other    = default;
        }

        // GPIO Output response coverage
        cp_gpio_out: coverpoint cov_item.gpio_out_sample {
            bins zero     = {8'h00};
            bins all_ones = {8'hFF};
            bins mid_vals = {[8'h01 : 8'hFE]};
        }

        // UART character coverage
        cp_uart_char: coverpoint cov_item.uart_rx_char {
            bins ascii_upper = {[8'd65 : 8'd90]};  // 'A' - 'Z'
            bins ascii_lower = {[8'd97 : 8'd122]}; // 'a' - 'z'
            bins ascii_digit = {[8'd48 : 8'd57]};  // '0' - '9'
            bins ascii_crlf  = {8'd10, 8'd13};     // '\n', '\r'
            bins other_chars = default;
        }

        // Interrupt line toggles
        cp_timer_irq: coverpoint cov_item.timer_irq_sample {
            bins active = {1'b1};
            bins idle   = {1'b0};
        }

        cp_gpio_irq: coverpoint cov_item.gpio_irq_sample {
            bins active = {1'b1};
            bins idle   = {1'b0};
        }

        // Cross-coverage between stimulus type and interrupts
        cross_item_irq: cross cov_item.trans_type, cov_item.timer_irq_sample;

    endgroup: cg_soc_boundary

    function new(string name = "powerpulse_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_soc_boundary = new();
    endfunction: new

    virtual function void write(powerpulse_seq_item t);
        cov_item = t;
        cg_soc_boundary.sample();
    endfunction: write

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf("Total Functional Coverage achieved = %0.2f%%", cg_soc_boundary.get_coverage()), UVM_LOW)
    endfunction: report_phase

endclass: powerpulse_coverage

`endif // POWERPULSE_COVERAGE_SV
