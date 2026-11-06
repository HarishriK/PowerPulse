// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_seq_item.sv
// Description: UVM Sequence Item representing stimulus and observed transactions
// ==============================================================================

`ifndef POWERPULSE_SEQ_ITEM_SV
`define POWERPULSE_SEQ_ITEM_SV

class powerpulse_seq_item extends uvm_sequence_item;

    typedef enum bit [2:0] {
        TRANS_NOP        = 3'b000,
        TRANS_UART_TX    = 3'b001,
        TRANS_GPIO_IN    = 3'b010,
        TRANS_RESET_PULSE= 3'b011,
        TRANS_WAKE_BURST = 3'b100
    } trans_type_e;

    // Random stimulus fields
    rand trans_type_e trans_type;
    rand bit [7:0]    uart_byte;
    rand bit [7:0]    gpio_data;
    rand int unsigned delay_cycles;
    rand int unsigned reset_duration_cycles;

    // Monitored / Response fields
    bit [7:0]         uart_rx_char;
    bit [7:0]         gpio_out_sample;
    bit               timer_irq_sample;
    bit               gpio_irq_sample;
    time              timestamp;

    // Constraints
    constraint c_delay {
        delay_cycles inside {[1 : 200]};
    }

    constraint c_reset_duration {
        reset_duration_cycles inside {[5 : 50]};
    }

    constraint c_default_distribution {
        trans_type dist {
            TRANS_NOP         := 10,
            TRANS_UART_TX     := 40,
            TRANS_GPIO_IN     := 40,
            TRANS_RESET_PULSE := 2,
            TRANS_WAKE_BURST  := 8
        };
    }

    // UVM Field Automation & Registration
    `uvm_object_utils_begin(powerpulse_seq_item)
        `uvm_field_enum(trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(uart_byte,                 UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(gpio_data,                 UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(delay_cycles,              UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(reset_duration_cycles,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(uart_rx_char,              UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(gpio_out_sample,           UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(timer_irq_sample,          UVM_ALL_ON)
        `uvm_field_int(gpio_irq_sample,           UVM_ALL_ON)
        `uvm_field_int(timestamp,                 UVM_ALL_ON | UVM_TIME)
    `uvm_object_utils_end

    function new(string name = "powerpulse_seq_item");
        super.new(name);
        trans_type            = TRANS_NOP;
        uart_byte             = 8'h00;
        gpio_data             = 8'h00;
        delay_cycles          = 10;
        reset_duration_cycles = 10;
        uart_rx_char          = 8'h00;
        gpio_out_sample       = 8'h00;
        timer_irq_sample      = 1'b0;
        gpio_irq_sample       = 1'b0;
        timestamp             = 0;
    endfunction: new

    virtual function string convert2string();
        return $sformatf("Type=%s | UART=0x%02h ('%c') | GPIO_IN=0x%02h | GPIO_OUT=0x%02h | T_IRQ=%0d | G_IRQ=%0d | Delay=%0d",
            trans_type.name(), uart_byte, (uart_byte >= 32 && uart_byte < 127) ? uart_byte : 8'h2E,
            gpio_data, gpio_out_sample, timer_irq_sample, gpio_irq_sample, delay_cycles);
    endfunction: convert2string

endclass: powerpulse_seq_item

`endif // POWERPULSE_SEQ_ITEM_SV
