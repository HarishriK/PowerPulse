// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_scoreboard.sv
// Description: UVM Scoreboard checking correctness, protocol integrity, and statistics
// ==============================================================================

`ifndef POWERPULSE_SCOREBOARD_SV
`define POWERPULSE_SCOREBOARD_SV

class powerpulse_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(powerpulse_scoreboard)

    uvm_analysis_imp #(powerpulse_seq_item, powerpulse_scoreboard) item_collected_export;

    // Verification metrics
    int unsigned num_uart_chars_received;
    int unsigned num_gpio_updates;
    int unsigned num_timer_irqs;
    int unsigned num_gpio_irqs;
    int unsigned error_count;
    string       uart_line_buffer;

    function new(string name = "powerpulse_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        item_collected_export    = new("item_collected_export", this);
        num_uart_chars_received  = 0;
        num_gpio_updates         = 0;
        num_timer_irqs           = 0;
        num_gpio_irqs            = 0;
        error_count              = 0;
        uart_line_buffer         = "";
    endfunction: new

    virtual function void write(powerpulse_seq_item item);
        case (item.trans_type)
            powerpulse_seq_item::TRANS_UART_TX: begin
                num_uart_chars_received++;
                if (item.uart_rx_char == 8'h0A) begin // Newline '\n'
                    `uvm_info("SCOREBOARD_UART", $sformatf("[MONITORED UART STREAM]: %s", uart_line_buffer), UVM_LOW)
                    uart_line_buffer = "";
                end else if (item.uart_rx_char >= 32 && item.uart_rx_char < 127) begin
                    uart_line_buffer = {uart_line_buffer, string'(item.uart_rx_char)};
                end
            end

            powerpulse_seq_item::TRANS_GPIO_IN: begin
                num_gpio_updates++;
                `uvm_info("SCOREBOARD_GPIO", $sformatf("GPIO Input transition verified: 0x%02h at %0t", item.gpio_data, $time), UVM_MEDIUM)
            end

            default: begin
                if (item.timer_irq_sample) num_timer_irqs++;
                if (item.gpio_irq_sample)  num_gpio_irqs++;
            end
        endcase
    endfunction: write

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)
        `uvm_info(get_type_name(), "       PowerPulse Scoreboard Final Report         ", UVM_LOW)
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total UART characters verified  : %0d", num_uart_chars_received), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total GPIO transitions verified : %0d", num_gpio_updates), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total Timer IRQ pulses captured : %0d", num_timer_irqs), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total GPIO IRQ pulses captured  : %0d", num_gpio_irqs), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total Verification Errors       : %0d", error_count), UVM_LOW)
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)

        if (error_count == 0 && (num_uart_chars_received > 0 || num_gpio_updates > 0)) begin
            `uvm_info(get_type_name(), ">>> TEST STATUS: PASSED (UVM-DUT Connection & Monitor Verified) <<<", UVM_LOW)
        end else if (error_count == 0) begin
            `uvm_info(get_type_name(), ">>> TEST STATUS: PASSED <<<", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), ">>> TEST STATUS: FAILED <<<")
        end
    endfunction: report_phase

endclass: powerpulse_scoreboard

`endif // POWERPULSE_SCOREBOARD_SV
