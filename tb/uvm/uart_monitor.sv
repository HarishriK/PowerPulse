// ==============================================================================
// PowerPulse SoC Verification Environment
// File: uart_monitor.sv
// Description: Dedicated UVM Monitor for UART Interface
// ==============================================================================

`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

class uart_monitor extends uvm_monitor;

    `uvm_component_utils(uart_monitor)

    virtual uart_if vif;

    uvm_analysis_port #(uart_seq_item) item_collected_port;

    int unsigned clocks_per_baud = 434;

    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "UART virtual interface was not configured in monitor")
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        fork
            monitor_uart_rx();
        join
    endtask: run_phase

    virtual task monitor_uart_rx();
        bit [7:0] rx_byte;
        int i;
        uart_seq_item item;

        forever begin
            @(negedge vif.uart_rx);
            repeat (clocks_per_baud / 2) @(posedge vif.clk);
            if (vif.uart_rx == 1'b0) begin
                for (i = 0; i < 8; i++) begin
                    repeat (clocks_per_baud) @(posedge vif.clk);
                    rx_byte[i] = vif.uart_rx;
                end
                repeat (clocks_per_baud) @(posedge vif.clk);
                if (vif.uart_rx == 1'b1) begin
                    vif.mon_uart_rx_byte  <= rx_byte;
                    vif.mon_uart_rx_valid <= 1'b1;
                    item = uart_seq_item::type_id::create("uart_mon_item");
                    item.trans_type  = uart_seq_item::UART_TRANS_BYTE;
                    item.uart_data   = rx_byte;
                    item.mon_rx_byte = rx_byte;
                    item.timestamp   = $time;
                    `uvm_info(get_type_name(), $sformatf("Monitored UART RX Byte at DUT Interface: 0x%02h ('%c')", rx_byte, rx_byte), UVM_LOW)
                    item_collected_port.write(item);
                    @(posedge vif.clk);
                    vif.mon_uart_rx_valid <= 1'b0;
                end
            end
        end
    endtask: monitor_uart_rx

endclass: uart_monitor

`endif // UART_MONITOR_SV
