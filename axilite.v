`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2023 03:07:52 AM
// Design Name: 
// Module Name: axilite
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


module axilite
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter RAM_ADDR    = log2(Tape_Num)
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,

    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    output wire                      ap_start,
    input  wire                      ap_idle,
    input  wire                      ap_done,
    output wire  [(pDATA_WIDTH-1):0] data_length,

    input  wire     [(RAM_ADDR-1):0] FIR_raddr,
    output wire  [(pDATA_WIDTH-1):0] FIR_rdata,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
    wire aw_hs;
    wire w_hs;
    wire ar_hs;
    wire r_hs;

    reg rvalid_reg;
    reg arready_reg;
    reg [(pDATA_WIDTH-1):0] rdata_reg;

    reg [3:0]           tap_WE_reg;
    reg                 tap_EN_reg;
    reg [(pADDR_WIDTH-1):0] tap_A_reg;
    reg [(pDATA_WIDTH-1):0] tap_Di_reg;

    reg [(pDATA_WIDTH-1):0] data_length_reg;
    reg               [7:0] ap_control;

    reg [1:0] state;
    reg [1:0] next_state;
    localparam
    IDLE = 2'b00,
    WAIT = 2'b01,
    CAL  = 2'b10;

    always@(posedge axis_clk or negedge axis_rst_n) begin
        if(~axis_rst_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end


    always@* begin
        case(state)
            IDLE: begin
                tap_Di_reg  = 0;
            end
            WAIT: begin
                if (w_hs & (awaddr >= 12'h020 & awaddr <= 12'h0FF)) begin
                    tap_Di_reg = wdata;
                end
                else begin
                    tap_Di_reg  = 0;
                end
            end
            CAL: begin
                tap_Di_reg  = 0;
            end
            default: begin
                tap_Di_reg  = 0;
            end
        endcase
    end


    always@(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            ap_control <= 8'b0;
            data_length_reg <= 32'b0;
        end
        else begin
            case(state)
                IDLE: begin
                    ap_control <= {5'b0,ap_idle,ap_done,1'b0};
                    data_length_reg <= 32'b0;
                end
                WAIT: begin
                    ap_control[1] <= ap_done;
                    ap_control[2] <= ap_idle;
                    if (w_hs) begin
                        if (awaddr == 12'h000) begin
                            ap_control[0] <= wdata[0];
                        end
                        else if (awaddr == 12'h010) begin
                            data_length_reg <= wdata;
                        end
                        else begin
                            ap_control[0]  <= ap_control[0];
                            data_length_reg <= data_length_reg;
                        end
                    end
                    else begin
                        ap_control[0]  <= ap_control[0];
                        data_length_reg <= data_length_reg;
                    end
                end
                CAL: begin
                    ap_control[0] <= 0;
                    ap_control[1] <= ap_done;
                    ap_control[2] <= ap_idle;
                    data_length_reg <= data_length_reg;
                end
            endcase
        end
    end

    always@* begin
        case(state)
            IDLE: begin
                tap_A_reg = 0;
            end
            WAIT: begin
                if (aw_hs) begin
                    if ((awaddr >= 12'h020 & awaddr <= 12'h0FF)) begin
                        tap_A_reg =  {4'b00,awaddr[0+:7]-8'h020};
                    end
                    else begin
                        tap_A_reg = 0;
                    end
                end
                else if (ar_hs) begin
                    if ((araddr >= 12'h020 & araddr <= 12'h0FF)) begin
                        tap_A_reg = {4'b00,araddr[0+:7]-8'h020};
                    end
                    else begin
                        tap_A_reg = 0;
                    end
                end
                else begin
                    tap_A_reg = 0;
                end
            end
            CAL: begin
                tap_A_reg = {6'b0,FIR_raddr[3:0],2'b00};
            end
            default: begin
                tap_A_reg = 0;
            end
        endcase
    end

    always@* begin
        if (araddr == 12'h000) begin
            rdata_reg = ap_control;
        end
        else if (araddr == 12'h010) begin
            rdata_reg = data_length;
        end
        else if (araddr >= 12'h020 & araddr <= 12'h0FF) begin
            rdata_reg = tap_Do;
        end
        else begin
            rdata_reg = 0;
        end
    end

    always@* begin
        case (state)
            IDLE: begin
                tap_WE_reg = 4'b0000;
                tap_EN_reg = 0;
            end
            WAIT: begin
                if (w_hs & (awaddr >= 12'h020 & awaddr <= 12'h0FF)) begin
                    tap_WE_reg = 4'b1111;
                end
                else begin
                    tap_WE_reg = 4'b0000;
                end
                tap_EN_reg = 1;
            end
            CAL: begin
                tap_WE_reg = 4'b0000;
                tap_EN_reg = 1;
            end
            default: begin
                tap_WE_reg = 4'b0000;
                tap_EN_reg = 0;
            end
        endcase
    end

    always@* begin
        case (state)
            IDLE: begin
                next_state = WAIT;
            end
            WAIT: begin
                if (ap_control[0]) begin
                    next_state = CAL;
                end
                else begin
                    next_state = WAIT;
                end
            end
            CAL: begin
                if (ap_control[1]) begin
                    next_state = WAIT;
                end
                else begin
                    next_state = CAL;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n)
            rvalid_reg <= 0;
        else
            rvalid_reg <= (ar_hs & rready);
    end

    assign awready = ((state == WAIT) & awvalid & wvalid);
    assign wready  = ((state == WAIT) & awvalid & wvalid);
    assign aw_hs = awvalid & awready;
    assign w_hs  = wvalid  & wready;

    assign arready = ((state == WAIT| state == CAL) & arvalid);
    assign rvalid  = rvalid_reg;
    assign ar_hs = arvalid & arready;
    assign r_hs  = rvalid  & rready;
    assign rdata  = rdata_reg;

    assign data_length = data_length_reg;

    assign tap_EN = tap_EN_reg;
    assign tap_WE = tap_WE_reg;
    assign tap_Di = tap_Di_reg;
    assign tap_A  = tap_A_reg;

    assign ap_start = ap_control[0];
    assign FIR_rdata = tap_Do;

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