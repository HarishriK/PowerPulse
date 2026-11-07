`ifndef UART_SEQ_LIB_SV
`define UART_SEQ_LIB_SV

class uart_reset_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_reset_seq)

    function new(string name = "uart_reset_seq");
        super.new(name);
    endfunction

    virtual task body();
        uart_seq_item req_item = uart_seq_item::type_id::create("rst_item");
        start_item(req_item);
        req_item.trans_type   = uart_seq_item::UART_TRANS_RESET;
        req_item.reset_cycles = 20;
        finish_item(req_item);
    endtask
endclass

class uart_string_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_string_seq)

    string msg = "UART_VERIFIED\n";

    function new(string name = "uart_string_seq");
        super.new(name);
    endfunction

    virtual task body();
        uart_seq_item req_item;
        int i;
        for (i = 0; i < msg.len(); i++) begin
            req_item = uart_seq_item::type_id::create($sformatf("char_%0d", i));
            start_item(req_item);
            req_item.trans_type = uart_seq_item::UART_TRANS_BYTE;
            req_item.uart_data  = msg[i];
            finish_item(req_item);
        end
    endtask
endclass

`endif
