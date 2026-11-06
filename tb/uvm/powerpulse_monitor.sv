// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_monitor.sv
// Description: UVM Monitor observing UART TX, GPIO outputs, and IRQ lines
// ==============================================================================

`ifndef POWERPULSE_MONITOR_SV
`define POWERPULSE_MONITOR_SV

class powerpulse_monitor extends uvm_monitor;

    `uvm_component_utils(powerpulse_monitor)

    virtual powerpulse_soc_if vif;

    uvm_analysis_port #(powerpulse_seq_item) item_collected_port;

    int unsigned clocks_per_baud = 434;

    function new(string name = "powerpulse_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual powerpulse_soc_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON_NO_VIF", "Virtual interface powerpulse_soc_if not found in config_db")
        end
    endfunction: build_phase

    virtual task run_phase(uvm_phase phase);
        fork
            monitor_uart_tx();
            monitor_gpio_out();
            monitor_interrupts();
        join
    endtask: run_phase

    // Process 1: Decode UART TX stream
    virtual task monitor_uart_tx();
        bit [7:0] rx_byte;
        int i;
        powerpulse_seq_item item;

        forever begin
            // Wait for start bit falling edge (1 -> 0)
            @(negedge vif.uart_tx);
            // Verify center of start bit
            repeat (clocks_per_baud / 2) @(posedge vif.clk);
            if (vif.uart_tx == 1'b0) begin
                // Sample 8 data bits
                for (i = 0; i < 8; i++) begin
                    repeat (clocks_per_baud) @(posedge vif.clk);
                    rx_byte[i] = vif.uart_tx;
                end

                // Wait for stop bit
                repeat (clocks_per_baud) @(posedge vif.clk);
                if (vif.uart_tx == 1'b1) begin
                    item = powerpulse_seq_item::type_id::create("uart_mon_item");
                    item.trans_type      = powerpulse_seq_item::TRANS_UART_TX;
                    item.uart_rx_char    = rx_byte;
                    item.gpio_out_sample = vif.gpio_out;
                    item.timestamp       = $time;
                    `uvm_info(get_type_name(), $sformatf("Monitored UART TX Byte: 0x%02h ('%c')", rx_byte, rx_byte), UVM_LOW)
                    item_collected_port.write(item);
                end else begin
                    `uvm_warning(get_type_name(), "Framing error detected on UART TX (stop bit not high)")
                end
            end
        end
    endtask: monitor_uart_tx

    // Process 2: Monitor GPIO Output changes
    virtual task monitor_gpio_out();
        logic [7:0] prev_gpio;
        powerpulse_seq_item item;

        @(posedge vif.rst_n);
        prev_gpio = vif.gpio_out;

        forever begin
            @(posedge vif.clk);
            if (vif.gpio_out !== prev_gpio) begin
                prev_gpio = vif.gpio_out;
                item = powerpulse_seq_item::type_id::create("gpio_mon_item");
                item.trans_type      = powerpulse_seq_item::TRANS_GPIO_IN;
                item.gpio_out_sample = vif.gpio_out;
                item.timestamp       = $time;
                `uvm_info(get_type_name(), $sformatf("Monitored GPIO OUT Change: 0x%02h", vif.gpio_out), UVM_MEDIUM)
                item_collected_port.write(item);
            end
        end
    endtask: monitor_gpio_out

    // Process 3: Monitor Timer and GPIO Interrupts
    virtual task monitor_interrupts();
        powerpulse_seq_item item;

        forever begin
            @(posedge vif.clk);
            if (vif.timer_irq || vif.gpio_irq) begin
                item = powerpulse_seq_item::type_id::create("irq_mon_item");
                item.timer_irq_sample = vif.timer_irq;
                item.gpio_irq_sample  = vif.gpio_irq;
                item.gpio_out_sample  = vif.gpio_out;
                item.timestamp        = $time;
                `uvm_info(get_type_name(), $sformatf("Monitored IRQ Assertion: Timer_IRQ=%0d, GPIO_IRQ=%0d", vif.timer_irq, vif.gpio_irq), UVM_MEDIUM)
                item_collected_port.write(item);
            end
        end
    endtask: monitor_interrupts

endclass: powerpulse_monitor

`endif // POWERPULSE_MONITOR_SV
