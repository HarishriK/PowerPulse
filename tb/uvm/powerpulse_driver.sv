// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_driver.sv
// Description: UVM Driver driving pins on powerpulse_soc_if via procedural interface tasks
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
        // Default initial boundary signal states (set through driver registers)
        vif.drv_rst_n_reg   <= 1'b1;
        vif.drv_uart_rx_reg <= 1'b1;
        vif.drv_gpio_in_reg <= 8'h00;
        vif.drv_drive_en    <= 1'b1;

        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask: run_phase

    virtual task drive_transaction(powerpulse_seq_item item);
        case (item.trans_type)
            powerpulse_seq_item::TRANS_RESET_PULSE: begin
                `uvm_info(get_type_name(), $sformatf("Driving Reset pulse for %0d cycles (via interface always block)", item.reset_duration_cycles), UVM_HIGH)
                vif.drive_reset_pulse(item.reset_duration_cycles);
            end

            powerpulse_seq_item::TRANS_UART_TX: begin
                `uvm_info(get_type_name(), $sformatf("Transmitting UART byte 0x%02h ('%c') into uart_rx (via interface always block)", item.uart_byte, item.uart_byte), UVM_MEDIUM)
                vif.drive_uart_byte(item.uart_byte, clocks_per_baud);
            end

            powerpulse_seq_item::TRANS_GPIO_IN: begin
                `uvm_info(get_type_name(), $sformatf("Driving GPIO_IN = 0x%02h (via interface always block)", item.gpio_data), UVM_MEDIUM)
                vif.drive_gpio(item.gpio_data, item.delay_cycles);
            end

            powerpulse_seq_item::TRANS_WAKE_BURST: begin
                `uvm_info(get_type_name(), "Injecting Wakeup Pulse Burst via GPIO[0] toggle (via interface always block)", UVM_MEDIUM)
                vif.drive_wake_burst(item.delay_cycles);
            end

            powerpulse_seq_item::TRANS_NOP: begin
                repeat (item.delay_cycles) @(posedge vif.clk);
            end

            default: begin
                repeat (1) @(posedge vif.clk);
            end
        endcase
    endtask: drive_transaction

endclass: powerpulse_driver

`endif // POWERPULSE_DRIVER_SV
