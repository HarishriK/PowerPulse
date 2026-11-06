// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_driver.sv
// Description: UVM Driver driving pins on powerpulse_soc_if
// ==============================================================================

`ifndef POWERPULSE_DRIVER_SV
`define POWERPULSE_DRIVER_SV

class powerpulse_driver extends uvm_driver #(powerpulse_seq_item);

    `uvm_component_utils(powerpulse_driver)

    virtual powerpulse_soc_if vif;

    // Configurable baud rate timing parameters (50 MHz clock / 115200 baud = 434 cycles/bit)
    int unsigned clocks_per_baud = 434;

    function new(string name = "powerpulse_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual powerpulse_soc_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV_NO_VIF", "Virtual interface powerpulse_soc_if not found in config_db")
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        // Default initial boundary signal states
        vif.rst_n   <= 1'b1;
        vif.uart_rx <= 1'b1;
        vif.gpio_in <= 8'h00;

        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask: run_phase

    virtual task drive_transaction(powerpulse_seq_item item);
        case (item.trans_type)
            powerpulse_seq_item::TRANS_RESET_PULSE: begin
                `uvm_info(get_type_name(), $sformatf("Driving Reset pulse for %0d cycles", item.reset_duration_cycles), UVM_HIGH)
                vif.rst_n <= 1'b0;
                repeat (item.reset_duration_cycles) @(posedge vif.clk);
                vif.rst_n <= 1'b1;
                repeat (5) @(posedge vif.clk);
            end

            powerpulse_seq_item::TRANS_UART_TX: begin
                `uvm_info(get_type_name(), $sformatf("Transmitting UART byte 0x%02h ('%c')", item.uart_byte, item.uart_byte), UVM_MEDIUM)
                send_uart_byte(item.uart_byte);
            end

            powerpulse_seq_item::TRANS_GPIO_IN: begin
                `uvm_info(get_type_name(), $sformatf("Driving GPIO_IN = 0x%02h", item.gpio_data), UVM_MEDIUM)
                vif.gpio_in <= item.gpio_data;
                repeat (item.delay_cycles) @(posedge vif.clk);
            end

            powerpulse_seq_item::TRANS_WAKE_BURST: begin
                `uvm_info(get_type_name(), "Injecting Wakeup Pulse Burst via GPIO[0] toggle", UVM_MEDIUM)
                vif.gpio_in[0] <= ~vif.gpio_in[0];
                repeat (10) @(posedge vif.clk);
                vif.gpio_in[0] <= ~vif.gpio_in[0];
                repeat (item.delay_cycles) @(posedge vif.clk);
            end

            powerpulse_seq_item::TRANS_NOP: begin
                repeat (item.delay_cycles) @(posedge vif.clk);
            end

            default: begin
                repeat (1) @(posedge vif.clk);
            end
        endcase
    endtask: drive_transaction

    // Transmit one 8N1 serial UART byte over uart_rx pin
    virtual task send_uart_byte(bit [7:0] data);
        int i;
        // Start bit (Low)
        vif.uart_rx <= 1'b0;
        repeat (clocks_per_baud) @(posedge vif.clk);

        // 8 Data bits (LSB first)
        for (i = 0; i < 8; i++) begin
            vif.uart_rx <= data[i];
            repeat (clocks_per_baud) @(posedge vif.clk);
        end

        // Stop bit (High)
        vif.uart_rx <= 1'b1;
        repeat (clocks_per_baud) @(posedge vif.clk);

        // Inter-character guard time
        repeat (clocks_per_baud / 2) @(posedge vif.clk);
    endtask: send_uart_byte

endclass: powerpulse_driver

`endif // POWERPULSE_DRIVER_SV
