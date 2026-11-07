// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_monitor.sv
// Description: UVM Monitor observing UART RX/TX, GPIO in/out, and IRQ lines
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
            monitor_uart_rx();
            monitor_uart_tx();
            monitor_gpio_in();
            monitor_gpio_out();
            monitor_interrupts();
        join
    endtask: run_phase

    // Process 1: Decode incoming UART RX stream (data delivered to DUT)
    virtual task monitor_uart_rx();
        bit [7:0] rx_byte;
        int i;
        powerpulse_seq_item item;

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
                    item = powerpulse_seq_item::type_id::create("uart_rx_mon_item");
                    item.trans_type   = powerpulse_seq_item::TRANS_UART_TX;
                    item.uart_byte    = rx_byte;
                    item.uart_rx_char = rx_byte;
                    item.timestamp    = $time;
                    `uvm_info(get_type_name(), $sformatf("Monitored UART RX Byte received by design: 0x%02h ('%c')", rx_byte, rx_byte), UVM_LOW)
                    item_collected_port.write(item);
                    @(posedge vif.clk);
                    vif.mon_uart_rx_valid <= 1'b0;
                end
            end
        end
    endtask: monitor_uart_rx

    // Process 2: Decode UART TX stream (data transmitted from DUT)
    virtual task monitor_uart_tx();
        bit [7:0] rx_byte;
        int i;
        powerpulse_seq_item item;

        forever begin
            @(negedge vif.uart_tx);
            repeat (clocks_per_baud / 2) @(posedge vif.clk);
            if (vif.uart_tx == 1'b0) begin
                for (i = 0; i < 8; i++) begin
                    repeat (clocks_per_baud) @(posedge vif.clk);
                    rx_byte[i] = vif.uart_tx;
                end
                repeat (clocks_per_baud) @(posedge vif.clk);
                if (vif.uart_tx == 1'b1) begin
                    item = powerpulse_seq_item::type_id::create("uart_tx_mon_item");
                    item.trans_type      = powerpulse_seq_item::TRANS_UART_TX;
                    item.uart_rx_char    = rx_byte;
                    item.gpio_out_sample = vif.gpio_out;
                    item.timestamp       = $time;
                    `uvm_info(get_type_name(), $sformatf("Monitored UART TX Byte from DUT: 0x%02h ('%c')", rx_byte, rx_byte), UVM_LOW)
                    item_collected_port.write(item);
                end
            end
        end
    endtask: monitor_uart_tx

    // Process 3: Monitor GPIO Input changes applied to design
    virtual task monitor_gpio_in();
        logic [7:0] prev_gpio_in;
        powerpulse_seq_item item;

        @(posedge vif.rst_n);
        prev_gpio_in = vif.gpio_in;

        forever begin
            @(posedge vif.clk);
            if (vif.gpio_in !== prev_gpio_in) begin
                prev_gpio_in = vif.gpio_in;
                vif.mon_gpio_in_sampled <= vif.gpio_in;
                vif.mon_gpio_in_valid   <= 1'b1;
                item = powerpulse_seq_item::type_id::create("gpio_in_mon_item");
                item.trans_type = powerpulse_seq_item::TRANS_GPIO_IN;
                item.gpio_data  = vif.gpio_in;
                item.timestamp  = $time;
                `uvm_info(get_type_name(), $sformatf("Monitored GPIO IN applied to design: 0x%02h", vif.gpio_in), UVM_LOW)
                item_collected_port.write(item);
                @(posedge vif.clk);
                vif.mon_gpio_in_valid <= 1'b0;
            end
        end
    endtask: monitor_gpio_in

    // Process 4: Monitor GPIO Output changes
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

    // Process 5: Monitor Timer, GPIO and UART Interrupts
    virtual task monitor_interrupts();
        powerpulse_seq_item item;

        forever begin
            @(posedge vif.clk);
            if (vif.timer_irq || vif.gpio_irq || vif.uart_irq) begin
                item = powerpulse_seq_item::type_id::create("irq_mon_item");
                item.timer_irq_sample = vif.timer_irq;
                item.gpio_irq_sample  = vif.gpio_irq;
                item.gpio_out_sample  = vif.gpio_out;
                item.timestamp        = $time;
                `uvm_info(get_type_name(), $sformatf("Monitored IRQ Assertion: Timer_IRQ=%0d, GPIO_IRQ=%0d, UART_IRQ=%0d", vif.timer_irq, vif.gpio_irq, vif.uart_irq), UVM_MEDIUM)
                item_collected_port.write(item);
            end
        end
    endtask: monitor_interrupts

endclass: powerpulse_monitor

`endif // POWERPULSE_MONITOR_SV
