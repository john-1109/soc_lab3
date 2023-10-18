`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2023 03:08:08 AM
// Design Name: 
// Module Name: axi_stream
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module axi_stream
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter RAM_bit     = log2(Tape_Num)
)
(
    input   wire                     ss_tvalid,
    input   wire [(pDATA_WIDTH-1):0] ss_tdata,
    input   wire                     ss_tlast,
    output  wire                     ss_tready,

    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     en,
    output  wire                     shift,
    output  wire                     wait_ram,

    input   wire                     ap_start,
    input   wire                     ap_done,
    input   wire     [(RAM_bit-1):0] FIR_addr,
    output  wire [(pDATA_WIDTH-1):0] FIR_data,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

    reg [3:0]               data_WE_reg;
    reg                     data_EN_reg;
    reg [(pADDR_WIDTH-1):0] data_A_reg;
    reg [(pDATA_WIDTH-1):0] data_Di_reg;

    reg [(RAM_bit-1):0] write_ptr;
    reg [(RAM_bit-1):0] write_nptr;

    reg shift_reg;
    reg wait_ram_reg;

    reg           [1:0] state;
    reg           [1:0] next_state;
    localparam
    IDLE      = 2'b00,
    INIT      = 2'b01,
    WAIT      = 2'b10;

    always@(posedge axis_clk or negedge axis_rst_n) begin
        if(~axis_rst_n) begin
            state <= IDLE;
            write_ptr <= 0;
        end
        else begin
            state <= next_state;
            case(state)
                IDLE: begin
                    write_ptr <= write_nptr;
                end
                INIT:begin
                    write_ptr <= write_nptr;
                end
                WAIT:begin
                    if (w_hs) begin
                        write_ptr <= write_nptr;
                    end
                    else begin
                        write_ptr <= write_ptr;
                    end
                end
            endcase
        end
    end


    always@* begin
        case(state)
            IDLE: begin
                wait_ram_reg = 0;
                data_Di_reg = 0;
                data_A_reg  = 0;
            end
            INIT: begin
                data_Di_reg = 0;
                data_A_reg  = {6'b0,write_ptr,2'b00};
                wait_ram_reg = 0;
            end
            WAIT: begin
                wait_ram_reg = 1;
                if (w_hs) begin
                    data_Di_reg = ss_tdata;
                    data_A_reg  = {6'b0,write_ptr,2'b00};
                end
                else begin
                    data_Di_reg = 0;
                    data_A_reg  = {6'b0,FIR_addr,2'b00};
                end
            end
            default: begin
                wait_ram_reg = 0;
                data_Di_reg = 0;
                data_A_reg  = 0;
            end
        endcase
    end

    always@* begin
        case(state)
            IDLE: begin
                data_EN_reg = 0;
                data_WE_reg = 4'b0000;
            end
            INIT: begin
                data_EN_reg = 1;
                data_WE_reg = 4'b1111;
            end
            WAIT: begin
                data_EN_reg = 1;
                if (w_hs) begin
                    data_WE_reg  = {4{w_hs}};
                end
                else begin
                    data_WE_reg = 4'b0000;
                end
            end
            default: begin
                data_EN_reg = 0;
                data_WE_reg = 4'b0000;
            end
        endcase
    end

    always@* begin
        case(state)
            IDLE: begin
                if (ap_start) begin
                    next_state = INIT;
                end
                else begin
                    next_state = IDLE;
                end
                write_nptr = 0;
            end
            INIT: begin
                if (write_ptr == (Tape_Num-1)) begin
                    next_state = WAIT;
                    write_nptr = 0;
                end
                else begin
                    next_state = INIT;
                    write_nptr = write_ptr + 1;
                end
            end
            WAIT: begin
                if (w_hs) begin
                    if (write_ptr == (Tape_Num-1)) begin
                        write_nptr = 0;
                    end
                    else begin
                        write_nptr = write_ptr + 1;
                    end
                    next_state = WAIT;
                end
                else if (ap_done) begin
                    next_state = IDLE;
                    write_nptr = 0;
                end
                else begin
                    next_state = WAIT;
                    write_nptr = write_ptr;
                end
            end
            default: begin
                next_state = IDLE;
                write_nptr = 0;
            end
        endcase
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
        if(~axis_rst_n) begin
            shift_reg <= 0;
        end
        else if (w_hs) begin
            shift_reg <= 1;
        end
        else begin
            shift_reg <= 0;
        end
    end

    assign data_EN = data_EN_reg;
    assign data_WE = data_WE_reg;
    assign data_Di = data_Di_reg;
    assign data_A  = data_A_reg;
    assign ss_tready = (ss_tvalid & en);
    assign w_hs = ss_tready & ss_tvalid;

    assign shift = shift_reg;
    assign wait_ram = wait_ram_reg;

    assign FIR_data  = data_Do;

    function integer log2;
        input integer x;
        integer n, m;
        begin
            n = 1;
            m = 2;
            while (m < x) begin
                n = n + 1;
                m = m * 2;
            end
            log2 = n;
        end
    endfunction
endmodule
