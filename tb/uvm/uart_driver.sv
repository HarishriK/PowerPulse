// ==============================================================================
// PowerPulse SoC Verification Environment
// File: uart_driver.sv
// Description: Dedicated UVM Driver for UART Interface (matches faculty specification)
// ==============================================================================

`ifndef UART_DRIVER_SV
`define UART_DRIVER_SV

class uart_driver extends uvm_driver #(uart_seq_item);

    `uvm_component_utils(uart_driver)

    // Virtual interface declaration (as specified in assignment Phase 5)
    virtual uart_if vif;

    int unsigned clocks_per_baud = 434;

    function new(string name = "uart_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Configuration retrieval (exact code from assignment instructions)
        if (!uvm_config_db#(virtual uart_if)::get(
                this, "", "vif", vif
            )) begin
            `uvm_fatal("NOVIF", "UART virtual interface was not configured")
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        // Default initial boundary state
        vif.drv_rst_n_reg   <= 1'b1;
        vif.drv_uart_rx_reg <= 1'b1;
        vif.drv_drive_en    <= 1'b1;

        forever begin
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask: run_phase

    virtual task drive_transaction(uart_seq_item item);
        case (item.trans_type)
            uart_seq_item::UART_TRANS_RESET: begin
                `uvm_info(get_type_name(), $sformatf("Driving UART Reset pulse for %0d cycles (via interface always block)", item.reset_cycles), UVM_HIGH)
                vif.drive_reset_pulse(item.reset_cycles);
            end

            uart_seq_item::UART_TRANS_BYTE: begin
                `uvm_info(get_type_name(), $sformatf("Driving UART TX Byte 0x%02h ('%c') into uart_rx (via interface always block)", item.uart_data, item.uart_data), UVM_MEDIUM)
                vif.drive_uart_byte(item.uart_data, clocks_per_baud);
            end

            default: begin
                repeat (item.delay_cycles) @(posedge vif.clk);
            end
        endcase
    endtask: drive_transaction

endclass: uart_driver

`endif // UART_DRIVER_SV
