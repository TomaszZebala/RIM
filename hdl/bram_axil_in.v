// bram_axil_in.v
// AXI-Lite slave z wbudowana pamiecia dual-port. Wariant BRAM_IN.
//   Port AXI-Lite (PS): pelny odczyt/zapis 32-bit (PS zapisuje probki).
//   Port B native (PL): READ-ONLY do readera (enb/addrb/doutb), 32-bit.
// Pamiec: DEPTH slow x 32-bit. 2 probki 16-bit / slowo (pakowanie jak reader wariant A).
// Jeden clock domain (S_AXI_ACLK == zegar readera). Bez CDC.
//
// Struktura AXI-Lite wzorowana na dzialajacym axil_regs (ten sam handshake).

`default_nettype none

module bram_axil_in #(
    parameter integer DEPTH      = 2048,   // liczba slow 32-bit
    parameter integer ADDR_W     = 11      // log2(DEPTH); port B adresuje slowa
)(
    // ---- AXI-Lite (PS) ----
    input  wire                     S_AXI_ACLK,
    input  wire                     S_AXI_ARESETN,
    input  wire [ADDR_W+2-1 : 0]    S_AXI_AWADDR,   // bajtowy: [ADDR_W+1:2] = slowo
    input  wire [2 : 0]             S_AXI_AWPROT,
    input  wire                     S_AXI_AWVALID,
    output reg                      S_AXI_AWREADY,
    input  wire [31 : 0]            S_AXI_WDATA,
    input  wire [3 : 0]             S_AXI_WSTRB,
    input  wire                     S_AXI_WVALID,
    output reg                      S_AXI_WREADY,
    output reg  [1 : 0]             S_AXI_BRESP,
    output reg                      S_AXI_BVALID,
    input  wire                     S_AXI_BREADY,
    input  wire [ADDR_W+2-1 : 0]    S_AXI_ARADDR,
    input  wire [2 : 0]             S_AXI_ARPROT,
    input  wire                     S_AXI_ARVALID,
    output reg                      S_AXI_ARREADY,
    output reg  [31 : 0]            S_AXI_RDATA,
    output reg  [1 : 0]             S_AXI_RRESP,
    output reg                      S_AXI_RVALID,
    input  wire                     S_AXI_RREADY,

    // ---- Port B native (PL, read-only do readera) ----
    input  wire                     enb,
    input  wire [ADDR_W-1 : 0]      addrb,
    output reg  [31 : 0]            doutb
);

    // ---- pamiec ----
    (* ram_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    // =========================================================
    // PORT A: AXI-Lite write channel
    // =========================================================
    reg [ADDR_W-1:0] aw_word;
    reg              aw_seen, w_seen;

    // AWREADY / latch adresu
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY <= 1'b0; aw_seen <= 1'b0; aw_word <= 0;
        end else begin
            if (!S_AXI_AWREADY && S_AXI_AWVALID) begin
                S_AXI_AWREADY <= 1'b1;
                aw_word <= S_AXI_AWADDR[ADDR_W+1:2];
                aw_seen <= 1'b1;
            end else begin
                S_AXI_AWREADY <= 1'b0;
                if (S_AXI_BVALID && S_AXI_BREADY) aw_seen <= 1'b0;
            end
        end
    end

    // WREADY
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_WREADY <= 1'b0; w_seen <= 1'b0;
        end else begin
            if (!S_AXI_WREADY && S_AXI_WVALID) begin
                S_AXI_WREADY <= 1'b1; w_seen <= 1'b1;
            end else begin
                S_AXI_WREADY <= 1'b0;
                if (S_AXI_BVALID && S_AXI_BREADY) w_seen <= 1'b0;
            end
        end
    end

    // faktyczny zapis do pamieci: gdy oba adres i dane zlapane
    wire do_write = S_AXI_AWREADY && S_AXI_AWVALID && S_AXI_WREADY && S_AXI_WVALID;
    always @(posedge S_AXI_ACLK) begin
        if (do_write) begin
            if (S_AXI_WSTRB[0]) mem[aw_word][ 7: 0] <= S_AXI_WDATA[ 7: 0];
            if (S_AXI_WSTRB[1]) mem[aw_word][15: 8] <= S_AXI_WDATA[15: 8];
            if (S_AXI_WSTRB[2]) mem[aw_word][23:16] <= S_AXI_WDATA[23:16];
            if (S_AXI_WSTRB[3]) mem[aw_word][31:24] <= S_AXI_WDATA[31:24];
        end
    end

    // BVALID
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_BVALID <= 1'b0; S_AXI_BRESP <= 2'b0;
        end else begin
            if (do_write && !S_AXI_BVALID) begin
                S_AXI_BVALID <= 1'b1; S_AXI_BRESP <= 2'b0;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    // =========================================================
    // PORT A: AXI-Lite read channel
    // =========================================================
    reg [ADDR_W-1:0] ar_word;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY <= 1'b0; ar_word <= 0;
        end else begin
            if (!S_AXI_ARREADY && S_AXI_ARVALID) begin
                S_AXI_ARREADY <= 1'b1;
                ar_word <= S_AXI_ARADDR[ADDR_W+1:2];
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID <= 1'b0; S_AXI_RRESP <= 2'b0; S_AXI_RDATA <= 32'b0;
        end else begin
            if (S_AXI_ARREADY && S_AXI_ARVALID && !S_AXI_RVALID) begin
                S_AXI_RVALID <= 1'b1; S_AXI_RRESP <= 2'b0;
                S_AXI_RDATA  <= mem[ar_word];   // odczyt 1-cyklowy
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    // =========================================================
    // PORT B native: read-only do readera
    // =========================================================
    always @(posedge S_AXI_ACLK) begin
        if (enb) doutb <= mem[addrb];   // 1-cyklowa latencja (BMG_OUT_REG=0 w readerze)
    end

endmodule

`default_nettype wire
