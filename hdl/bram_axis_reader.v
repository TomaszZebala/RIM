// bram_axis_reader.v
// BRAM_IN (BMG port B, native, 32-bit) -> AXI-Stream master
// Wariant A: 32-bit slowo = 2x 16-bit probki, jedno slowo => 2 bity strumienia.
// Babel podczas ladowania slowa (bez prefetch).
// Nieparzyste COUNT: ostatnie slowo tylko dolna probka + TLAST; gorna ignorowana.
//
// Single clock domain (stream clock == BMG port B clock). No CDC.
//   BMG_OUT_REG = 1 -> 2-cycle latency (output register ON)
//   BMG_OUT_REG = 0 -> 1-cycle latency (output register OFF)

`default_nettype none

module bram_axis_reader #(
    parameter integer ADDR_W       = 12,
    parameter integer COUNT_W      = 25,
    parameter integer BMG_OUT_REG  = 1
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [COUNT_W-1:0]   count,
    output reg                  enb,
    output reg  [ADDR_W-1:0]    addrb,
    input  wire [31:0]          doutb,
    output reg  [15:0]          m_tdata,
    output reg                  m_tvalid,
    output reg                  m_tlast,
    input  wire                 m_tready,
    output reg                  busy
);

    localparam integer RD_LAT = (BMG_OUT_REG != 0) ? 2 : 1;

    localparam [2:0] S_IDLE = 3'd0,
                     S_LOAD = 3'd1,
                     S_LOW  = 3'd2,
                     S_HIGH = 3'd3,
                     S_DONE = 3'd4;

    reg [2:0]          state;
    reg [COUNT_W-1:0]  sample_idx;
    reg [ADDR_W-1:0]   word_addr;
    reg [31:0]         word_reg;
    reg [1:0]          lat_cnt;

    wire is_last      = (sample_idx == (count - 1'b1));
    wire next_is_last = ((sample_idx + 1'b1) == (count - 1'b1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; sample_idx<=0; word_addr<=0; word_reg<=0; lat_cnt<=0;
            enb<=0; addrb<=0; m_tdata<=0; m_tvalid<=0; m_tlast<=0; busy<=0;
        end else begin
            enb <= 1'b0;
            case (state)
            S_IDLE: begin
                m_tvalid<=1'b0; m_tlast<=1'b0; busy<=1'b0;
                if (start && (count != {COUNT_W{1'b0}})) begin
                    sample_idx<=0; word_addr<=0; addrb<=0;
                    enb<=1'b1; lat_cnt<=RD_LAT[1:0]; busy<=1'b1;
                    state<=S_LOAD;
                end
            end
            S_LOAD: begin
                m_tvalid<=1'b0;
                if (lat_cnt == 2'd0) begin
                    word_reg<=doutb;
                    m_tdata<=doutb[15:0];
                    m_tvalid<=1'b1;
                    m_tlast<=is_last;
                    state<=S_LOW;
                end else begin
                    lat_cnt<=lat_cnt-1'b1;
                end
            end
            S_LOW: begin
                if (m_tvalid && m_tready) begin
                    if (is_last) begin
                        m_tvalid<=1'b0; m_tlast<=1'b0; state<=S_DONE;
                    end else begin
                        sample_idx<=sample_idx+1'b1;
                        m_tdata<=word_reg[31:16];
                        m_tvalid<=1'b1;
                        m_tlast<=next_is_last;
                        state<=S_HIGH;
                    end
                end
            end
            S_HIGH: begin
                if (m_tvalid && m_tready) begin
                    if (m_tlast) begin
                        m_tvalid<=1'b0; m_tlast<=1'b0; state<=S_DONE;
                    end else begin
                        sample_idx<=sample_idx+1'b1;
                        word_addr<=word_addr+1'b1;
                        addrb<=word_addr+1'b1;
                        enb<=1'b1;
                        lat_cnt<=RD_LAT[1:0];
                        m_tvalid<=1'b0;
                        state<=S_LOAD;
                    end
                end
            end
            S_DONE: begin
                m_tvalid<=1'b0; m_tlast<=1'b0; busy<=1'b0; state<=S_IDLE;
            end
            default: state<=S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
