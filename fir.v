module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
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
    input   wire                     ss_tvalid,
    input   wire [(pDATA_WIDTH-1):0] ss_tdata,
    input   wire                     ss_tlast,
    output  wire                     ss_tready,
    input   wire                     sm_tready,
    output  wire                     sm_tvalid,
    output  wire [(pDATA_WIDTH-1):0] sm_tdata,
    output  wire                     sm_tlast,

    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
//---------------------------------------------------------------------
//        PARAMETER DECLARATION
//---------------------------------------------------------------------
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
  
  localparam IDLE     = 3'b000;
  localparam INIT     = 3'b001;
  localparam RUN_INIT = 3'b010;
  localparam RUN_TAP  = 3'b011;
  localparam EXE      = 3'b101;
  localparam OUTPUT   = 3'b110;
  localparam DONE     = 3'b111;

  localparam DATA_WIDTH = log2(Tape_Num);

//---------------------------------------------------------------------
//   WIRE AND REG DECLARATION && CONNECTION                            
//--------------------------------------------------------------------- 
  reg  [9:0] count;
  wire ap_start;
  wire ap_done;
  wire ap_idle;
  
  reg [DATA_WIDTH-1:0] tap_ptr;
  reg [DATA_WIDTH-1:0] tap_nptr;
  reg [DATA_WIDTH-1:0] data_ptr;
  reg [DATA_WIDTH-1:0] data_nptr;
  reg [DATA_WIDTH-1:0] start_ptr;
  
  wire [pDATA_WIDTH-1:0] coef;
  wire [pDATA_WIDTH-1:0] data;
  wire [pDATA_WIDTH-1:0] data_length;
  
  reg signed [pDATA_WIDTH-1:0] mul;
  reg  [pDATA_WIDTH-1:0] sum;
  
  
  wire sm_samp;
  wire en;
  wire shift;
  wire wait_ram;
  
  reg [2:0] state;
  reg [2:0] next_state;
  
  
  
  assign ap_done = (state==DONE||(state==OUTPUT&&(sm_samp&&count==(data_length[0+:10]+1))))?1'b1:1'b0;
  assign ap_idle = (state==IDLE||state==DONE||(state==OUTPUT&&(sm_samp&&count==(data_length[0+:10]+1))))?1'b1:1'b0;
  assign en = ((state==INIT&&wait_ram)||(state==OUTPUT&&sm_samp&&!(count==(data_length[0+:10]+1))))?1'b1:1'b0;;
  assign sm_samp = sm_tvalid & sm_tready;
  assign sm_tvalid = (state == OUTPUT);
  assign sm_tdata  = sum;
  assign sm_tlast  = ss_tlast;

//---------------------------------------------------------------------
//        MODULE INSTATIATION 
//---------------------------------------------------------------------
  axilite axilite_U(
    .awready(awready),
    .wready(wready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wvalid(wvalid),
    .wdata(wdata),
    .arready(arready),
    .rready(rready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rvalid(rvalid),
    .rdata(rdata),
    .tap_WE(tap_WE),
    .tap_EN(tap_EN),
    .tap_Di(tap_Di),
    .tap_A(tap_A),
    .tap_Do(tap_Do),
    .ap_start(ap_start),
    .ap_done(ap_done),
    .ap_idle(ap_idle),
    .data_length(data_length),
    .FIR_raddr(tap_ptr),
    .FIR_rdata(coef),
    .axis_clk(axis_clk),
    .axis_rst_n(axis_rst_n)
  );
  
  axi_stream axi_stream_U(
    .ss_tvalid(ss_tvalid),
    .ss_tdata(ss_tdata),
    .ss_tlast(ss_tlast),
    .ss_tready(ss_tready),
    .data_WE(data_WE),
    .data_EN(data_EN),
    .data_Di(data_Di),
    .data_A(data_A),
    .data_Do(data_Do),
    .en(en),
    .shift(shift),
    .wait_ram(wait_ram),
    .FIR_addr(data_ptr),
    .FIR_data(data),
    .ap_start(ap_start),
    .ap_done(ap_done),
    .axis_clk(axis_clk),
    .axis_rst_n(axis_rst_n)
  );
      
//---------------------------------------------------------------------
//        finite state machine - state logic
//---------------------------------------------------------------------
  always@(*)begin
    case(state)
      IDLE: begin
        if (ap_start) 
          next_state = INIT;
        else
          next_state = IDLE;
      end
      INIT: begin
        if (wait_ram) 
          next_state = RUN_INIT;
        else 
          next_state = INIT;
      end
      RUN_INIT: begin
        if (shift) 
          next_state = RUN_TAP;
        else 
          next_state = RUN_INIT;
      end
      RUN_TAP: begin
        next_state = EXE;
      end
      EXE: begin
        if (count <= Tape_Num + 1) begin
          if (data_ptr == (Tape_Num-1)) 
            next_state = OUTPUT;
          else 
            next_state = RUN_TAP;
        end else begin
          if (tap_ptr == 0) 
            next_state = OUTPUT;
          else 
            next_state = RUN_TAP;
        end
      end
      OUTPUT: begin
        if (sm_samp) begin
          if (count == (data_length[0+:10]+1)) 
            next_state = DONE;
          else 
            next_state = RUN_INIT;
        end else begin
          next_state = EXE;
        end
      end
      DONE: begin
        if (ap_start) 
          next_state = INIT;
        else 
          next_state = DONE;
      end
      default:next_state = IDLE;
    endcase
  end
  
//---------------------------------------------------------------------
//        finite state machine - output logic
//---------------------------------------------------------------------
  always@(*)begin
    mul = coef * data;
  end
  
  always@(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
      state    <= IDLE;
      tap_ptr  <= 0;
      data_ptr <= 0;
    end else begin
      state    <= next_state;
      tap_ptr  <= tap_nptr;
      data_ptr <= data_nptr;
    end
  end
  
  always@(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
      sum       <= 0;
      count     <= 2;
      start_ptr <= 2;
    end else begin
      case(state)
        IDLE: begin
          sum       <= 0;
          count     <= 2;
          start_ptr <= 2;
        end
        INIT: begin
          sum       <= 0;
          count     <= count;
          start_ptr <= start_ptr;
        end
        RUN_INIT: begin
          sum       <= 0;
          count     <= count;
          start_ptr <= start_ptr;
        end
        RUN_TAP: begin
          sum       <= sum;
          count     <= count;
          start_ptr <= start_ptr;
        end
        EXE: begin
          sum       <= sum + mul;
          count     <= count;
          start_ptr <= start_ptr;
        end
        OUTPUT: begin
          if (sm_samp) begin
            if (start_ptr == (Tape_Num-1)) begin
              start_ptr <= 0;
            end else begin
              start_ptr <= start_ptr + 1;
            end
            count       <= count + 1;
            sum         <= 0;
          end else begin
            count     <= count;
            sum       <= sum;
            start_ptr <= start_ptr;
          end
        end
        DONE: begin
          sum       <= 0;
          count     <= count;
          start_ptr <= start_ptr;
        end
        default: begin
          sum       <= 0;
          count     <= 2;
          start_ptr <= 2;
        end
      endcase
    end
  end
  
  always@(*)begin
    case(state)
      IDLE: begin
        data_nptr = 0;
        tap_nptr  = 0;
      end
      INIT: begin
        data_nptr = 0;
        tap_nptr  = 0;
      end
      RUN_INIT: begin
        data_nptr = data_ptr;
        tap_nptr  = tap_ptr;
      end
      RUN_TAP: begin
        tap_nptr  = tap_ptr;
        data_nptr = data_ptr;
      end
      EXE: begin
        if (data_ptr == (Tape_Num-1)) begin
          data_nptr = 0;
        end else begin
          data_nptr = data_ptr + 1;  
        end  
        if (tap_ptr == 0) begin  
          tap_nptr = Tape_Num-1;  
        end else begin  
          tap_nptr = tap_ptr-1;  
        end  
      end
      OUTPUT: begin
          if (sm_samp) begin
            if (count < (Tape_Num+1)) begin
              tap_nptr = (count - 1);
            end else begin
              tap_nptr = (Tape_Num - 1);
            end
            if (count >= (Tape_Num+1)) begin
              data_nptr = start_ptr;
            end else begin
              data_nptr = 0;
            end
          end else begin
            tap_nptr  = tap_ptr;
            data_nptr = data_ptr;
          end
      end
      DONE: begin
        tap_nptr  = 0;
        data_nptr = 0;
      end
      default: begin
        tap_nptr  = 0;
        data_nptr = 0;
      end
    endcase
  end
  
endmodule