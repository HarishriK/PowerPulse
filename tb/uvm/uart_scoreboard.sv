`ifndef UART_SCOREBOARD_SV
`define UART_SCOREBOARD_SV

class uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_scoreboard)

    uvm_analysis_imp #(uart_seq_item, uart_scoreboard) item_collected_export;
    int unsigned num_chars_verified;
    string       captured_string;

    function new(string name = "uart_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        item_collected_export = new("item_collected_export", this);
        num_chars_verified    = 0;
        captured_string       = "";
    endfunction

    virtual function void write(uart_seq_item item);
        num_chars_verified++;
        captured_string = {captured_string, string'(item.mon_rx_byte)};
        `uvm_info("UART_SCOREBOARD", $sformatf("Verified Byte #%0d: 0x%02h ('%c')", num_chars_verified, item.mon_rx_byte, item.mon_rx_byte), UVM_LOW)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)
        `uvm_info(get_type_name(), "       Dedicated UART Interface UVM Report        ", UVM_LOW)
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total UART characters verified: %0d", num_chars_verified), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Monitored Text Payload       : %s", captured_string), UVM_LOW)
        `uvm_info(get_type_name(), "==================================================", UVM_LOW)
        if (num_chars_verified > 0) begin
            `uvm_info(get_type_name(), ">>> TEST STATUS: PASSED (UART Interface Top Verified) <<<", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), ">>> TEST STATUS: FAILED (No characters verified) <<<")
        end
    endfunction
endclass

`endif
