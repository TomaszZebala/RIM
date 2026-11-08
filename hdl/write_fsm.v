// write_fsm.v
// AXI-Stream slave (od bloku studenta) -> BRAM_OUT port A, 16-bit/adres.
// 12-bit adres => 4096 probek pojemnosci wyniku.
// stu_tready = 1 zawsze (nie zawieszamy studenta nawet przy overflow).

module write_fsm #(
    parameter ADDR_W = 12,
    parameter DEPTH  = (1 << ADDR_W)
)(
    input  wire clk, resetn,
    input  wire start_pulse,
    // od studenta (m_axis)
    input  wire [15:0] stu_tdata,
    input  wire        stu_tvalid,
    output wire        stu_tready,
    input  wire        stu_tlast,
    // status
    output reg               status_done,
    output reg               overflow,
    output reg  [ADDR_W-1:0] out_count,
    // port A BRAM_OUT (16-bit szeroki)
    output reg  [ADDR_W-1:0] bram_addr_a,
    output reg  [15:0]       bram_din_a,
    output reg               bram_we_a,
    output reg               bram_en_a
);
    localparam S_IDLE=2'd0, S_WRITE=2'd1, S_DONE=2'd2;
    reg [1:0] state;
    reg [ADDR_W-1:0] addr;

    assign stu_tready = 1'b1;

    always @(posedge clk) begin
        if (!resetn) begin
            state<=S_IDLE; addr<=0; status_done<=0; overflow<=0; out_count<=0;
            bram_addr_a<=0; bram_din_a<=0; bram_we_a<=0; bram_en_a<=0;
        end else begin
            bram_we_a<=0; bram_en_a<=0;
            case (state)
            S_IDLE: begin
                if (start_pulse) begin
                    addr<=0; status_done<=0; overflow<=0; out_count<=0; state<=S_WRITE;
                end
            end
            S_WRITE: begin
                if (stu_tvalid) begin
                    if (addr < DEPTH) begin
                        bram_addr_a<=addr; bram_din_a<=stu_tdata;
                        bram_we_a<=1; bram_en_a<=1;
                        out_count<=addr+1'b1;
                        if (!stu_tlast) addr<=addr+1'b1;
                    end else begin
                        overflow<=1;
                    end
                    if (stu_tlast) state<=S_DONE;
                end
            end
            S_DONE: begin
                status_done<=1;
                state<=S_IDLE;
            end
            default: state<=S_IDLE;
            endcase
        end
    end
endmodule
