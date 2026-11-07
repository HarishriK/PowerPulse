// ==============================================================================
// PowerPulse SoC Verification Environment
// File: uart_seq_item.sv
// Description: UVM Sequence Item for dedicated UART Interface
// ==============================================================================

`ifndef UART_SEQ_ITEM_SV
`define UART_SEQ_ITEM_SV

class uart_seq_item extends uvm_sequence_item;

    typedef enum bit [1:0] {
        UART_TRANS_BYTE  = 2'b00,
        UART_TRANS_RESET = 2'b01
    } uart_trans_e;

    rand uart_trans_e trans_type;
    rand bit [7:0]    uart_data;
    rand int unsigned reset_cycles;
    rand int unsigned delay_cycles;

    // Monitored / Response
    bit [7:0]         mon_rx_byte;
    time              timestamp;

    constraint c_reset_cycles {
        reset_cycles inside {[10 : 30]};
    }

    constraint c_delay_cycles {
        delay_cycles inside {[1 : 50]};
    }

    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_enum(uart_trans_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(uart_data,     UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(reset_cycles,  UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(delay_cycles,  UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mon_rx_byte,   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(timestamp,     UVM_ALL_ON | UVM_TIME)
    `uvm_object_utils_end

    function new(string name = "uart_seq_item");
        super.new(name);
        trans_type   = UART_TRANS_BYTE;
        uart_data    = 8'h00;
        reset_cycles = 20;
        delay_cycles = 10;
        mon_rx_byte  = 8'h00;
        timestamp    = 0;
    endfunction: new

    virtual function string convert2string();
        return $sformatf("Type=%s | Data=0x%02h ('%c')", trans_type.name(), uart_data, 
            (uart_data >= 32 && uart_data < 127) ? uart_data : 8'h2E);
    endfunction: convert2string

endclass: uart_seq_item

`endif // UART_SEQ_ITEM_SV
