`timescale 1 ns / 1 ps
// ============================================================================
//  axis_ctrl_v3_0 - AXI4-Lite slave sterujacy (wariant dwu-BRAM, bez DMA)
//
//  Register map:
//    0x00 CTRL   [0]=START (W1P, self-clear), [31:1] scratch R/W
//    0x04 COUNT  [24:0] R/W
//    0x08 STATUS [0]=running [1]=done [2]=overflow [15:4]=out_count (RO)
//    0x0C ID     0xC0FFEE03 (RO)
//
//  Wpiecie w Block Design:
//    - start_pulse -> OBU fsm (replay_fsm i write_fsm), jeden net
//    - status_running <- replay_fsm
//    - status_done, overflow, out_count <- write_fsm
//    - done/overflow czyszczone przez write_fsm przy START (S_IDLE)
// ============================================================================
module axis_ctrl_v3_0 #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 4
)
(
    // ---- User ports ----
    output wire        start_pulse,
    output wire [24:0] count,
    input  wire        status_running,
    input  wire        status_done,
    input  wire        overflow,
    input  wire [11:0] out_count,

    // ---- AXI4-Lite slave ----
    input  wire                                  s00_axi_aclk,
    input  wire                                  s00_axi_aresetn,
    input  wire [C_S00_AXI_ADDR_WIDTH-1:0]       s00_axi_awaddr,
    input  wire [2:0]                            s00_axi_awprot,
    input  wire                                  s00_axi_awvalid,
    output wire                                  s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1:0]       s00_axi_wdata,
    input  wire [(C_S00_AXI_DATA_WIDTH/8)-1:0]   s00_axi_wstrb,
    input  wire                                  s00_axi_wvalid,
    output wire                                  s00_axi_wready,
    output wire [1:0]                            s00_axi_bresp,
    output wire                                  s00_axi_bvalid,
    input  wire                                  s00_axi_bready,
    input  wire [C_S00_AXI_ADDR_WIDTH-1:0]       s00_axi_araddr,
    input  wire [2:0]                            s00_axi_arprot,
    input  wire                                  s00_axi_arvalid,
    output wire                                  s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0]       s00_axi_rdata,
    output wire [1:0]                            s00_axi_rresp,
    output wire                                  s00_axi_rvalid,
    input  wire                                  s00_axi_rready
);

    localparam integer DW                = C_S00_AXI_DATA_WIDTH;
    localparam integer ADDR_LSB          = (DW/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 1;
    localparam [31:0]  ID_VALUE          = 32'hC0FF_EE03;  // "coffee", rev 03

    // ---------------- AXI state ----------------
    reg [C_S00_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                            axi_awready;
    reg                            axi_wready;
    reg                            axi_bvalid;
    reg [C_S00_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                            axi_arready;
    reg [DW-1:0]                   axi_rdata;
    reg                            axi_rvalid;
    reg                            aw_en;

    // ---------------- Registers ----------------
    reg [DW-1:0] slv_reg0;   // CTRL
    reg [DW-1:0] slv_reg1;   // COUNT
    reg          start_reg;
    reg [DW-1:0] reg_data_out;
    integer      byte_index;

    wire [OPT_MEM_ADDR_BITS:0] wr_sel = axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];
    wire [OPT_MEM_ADDR_BITS:0] rd_sel = axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

    wire slv_reg_wren = axi_wready  && s00_axi_wvalid && axi_awready && s00_axi_awvalid;
    wire slv_reg_rden = axi_arready && s00_axi_arvalid && ~axi_rvalid;

    assign s00_axi_awready = axi_awready;
    assign s00_axi_wready  = axi_wready;
    assign s00_axi_bresp   = 2'b00;        // OKAY
    assign s00_axi_bvalid  = axi_bvalid;
    assign s00_axi_arready = axi_arready;
    assign s00_axi_rdata   = axi_rdata;
    assign s00_axi_rresp   = 2'b00;        // OKAY
    assign s00_axi_rvalid  = axi_rvalid;

    // ---------------- Write address / data handshake ----------------
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_awaddr  <= 0;
            aw_en       <= 1'b1;
        end else begin
            // AWREADY + latch adresu
            if (~axi_awready && s00_axi_awvalid && s00_axi_wvalid && aw_en) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= s00_axi_awaddr;
                aw_en       <= 1'b0;
            end else if (s00_axi_bready && axi_bvalid) begin
                axi_awready <= 1'b0;
                aw_en       <= 1'b1;
            end else begin
                axi_awready <= 1'b0;
            end

            // WREADY
            if (~axi_wready && s00_axi_wvalid && s00_axi_awvalid && aw_en)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    // ---------------- Write response ----------------
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn)
            axi_bvalid <= 1'b0;
        else if (axi_awready && s00_axi_awvalid && ~axi_bvalid && axi_wready && s00_axi_wvalid)
            axi_bvalid <= 1'b1;
        else if (s00_axi_bready && axi_bvalid)
            axi_bvalid <= 1'b0;
    end

    // ---------------- Register write ----------------
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
        end else if (slv_reg_wren) begin
            for (byte_index = 0; byte_index < DW/8; byte_index = byte_index + 1)
                if (s00_axi_wstrb[byte_index]) begin
                    case (wr_sel)
                        2'h0: slv_reg0[byte_index*8 +: 8] <= s00_axi_wdata[byte_index*8 +: 8];
                        2'h1: slv_reg1[byte_index*8 +: 8] <= s00_axi_wdata[byte_index*8 +: 8];
                        default: ;  // STATUS i ID sa read-only
                    endcase
                end
        end
    end

    // ---------------- Read address handshake ----------------
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 0;
        end else if (~axi_arready && s00_axi_arvalid) begin
            axi_arready <= 1'b1;
            axi_araddr  <= s00_axi_araddr;
        end else begin
            axi_arready <= 1'b0;
        end
    end

    // ---------------- Read valid ----------------
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn)
            axi_rvalid <= 1'b0;
        else if (axi_arready && s00_axi_arvalid && ~axi_rvalid)
            axi_rvalid <= 1'b1;
        else if (axi_rvalid && s00_axi_rready)
            axi_rvalid <= 1'b0;
    end

    // ---------------- Read decode ----------------
    always @(*) begin
        case (rd_sel)
            2'h0:    reg_data_out = {slv_reg0[DW-1:1], start_reg};
            2'h1:    reg_data_out = slv_reg1;
            2'h2:    reg_data_out = {16'b0, out_count, 1'b0, overflow, status_done, status_running};
            2'h3:    reg_data_out = ID_VALUE;
            default: reg_data_out = 0;
        endcase
    end

    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn)
            axi_rdata <= 0;
        else if (slv_reg_rden)
            axi_rdata <= reg_data_out;
    end

    // ============================================================
    //  User logic
    // ============================================================
    assign count = slv_reg1[24:0];

    // START: impuls 1-cyklowy na zapis 1 do CTRL[0], auto-clear
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn)
            start_reg <= 1'b0;
        else
            start_reg <= slv_reg_wren && (wr_sel == 2'h0)
                         && s00_axi_wstrb[0] && s00_axi_wdata[0];
    end

    assign start_pulse = start_reg;

endmodule