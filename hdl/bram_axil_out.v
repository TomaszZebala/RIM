// bram_axil_out.v
// AXI-Lite slave z wbudowana pamiecia dual-port. Wariant BRAM_OUT.
//   Port A native (PL): WRITE od write_fsm (ena/wea/addra/dina), 16-bit/probka.
//   Port AXI-Lite (PS): READ (PS czyta wynik). 32-bit slowa (2 probki/slowo).
// Pamiec: DEPTH slow x 32-bit. write_fsm pisze 16-bit probki; pakujemy 2/slowo
//   tak jak reader rozpakowuje wejscie -> spojnie w calym systemie.
//
// Uwaga: write_fsm pisze 16-bit/adres. Tu port A przyjmuje 16-bit probke pod
//   adres PROBKI (nie slowa) i sam sklada do 32-bit slowa w pamieci:
//   probka parzysta -> [15:0], nieparzysta -> [31:16].

`default_nettype none

module bram_axil_out #(
    parameter integer DEPTH      = 2048,   // slowa 32-bit
    parameter integer ADDR_W     = 11,     // log2(DEPTH) - adres SLOWA
    parameter integer SMPADDR_W  = 12      // adres PROBKI (o 1 bit wiecej)
)(
    // ---- AXI-Lite (PS) — read path uzywany, write path stub (PS tylko czyta) ----
    input  wire                     S_AXI_ACLK,
    input  wire                     S_AXI_ARESETN,
    input  wire [ADDR_W+2-1 : 0]    S_AXI_AWADDR,
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

    // ---- Port A native (PL): write od write_fsm ----
    input  wire                     ena,
    input  wire                     wea,
    input  wire [SMPADDR_W-1 : 0]   addra_smp,   // adres PROBKI
    input  wire [15 : 0]            dina
);

    (* ram_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    // ---- Port A: zapis 16-bit probki, pakowanie do 32-bit slowa ----
    wire [ADDR_W-1:0] a_word = addra_smp[SMPADDR_W-1:1];  // slowo = probka>>1
    wire              a_hi   = addra_smp[0];              // 0=dolna,1=gorna polowka
    always @(posedge S_AXI_ACLK) begin
        if (ena && wea) begin
            if (a_hi) mem[a_word][31:16] <= dina;
            else      mem[a_word][15: 0] <= dina;
        end
    end

    // ---- AXI-Lite write channel: stub (PS nie pisze do BRAM_OUT, ale musi
    //      odpowiadac zeby transakcja sie nie zawiesila) ----
    reg aw_hs, w_hs;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY<=0; S_AXI_WREADY<=0; S_AXI_BVALID<=0; S_AXI_BRESP<=0;
            aw_hs<=0; w_hs<=0;
        end else begin
            if (!S_AXI_AWREADY && S_AXI_AWVALID) begin S_AXI_AWREADY<=1; aw_hs<=1; end
            else S_AXI_AWREADY<=0;
            if (!S_AXI_WREADY && S_AXI_WVALID) begin S_AXI_WREADY<=1; w_hs<=1; end
            else S_AXI_WREADY<=0;
            if (aw_hs && w_hs && !S_AXI_BVALID) begin
                S_AXI_BVALID<=1; S_AXI_BRESP<=2'b00; aw_hs<=0; w_hs<=0;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID<=0;
            end
        end
    end

    // ---- AXI-Lite read channel (PS czyta wynik) ----
    reg [ADDR_W-1:0] ar_word;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY<=0; ar_word<=0;
        end else begin
            if (!S_AXI_ARREADY && S_AXI_ARVALID) begin
                S_AXI_ARREADY<=1; ar_word<=S_AXI_ARADDR[ADDR_W+1:2];
            end else S_AXI_ARREADY<=0;
        end
    end
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID<=0; S_AXI_RRESP<=0; S_AXI_RDATA<=0;
        end else begin
            if (S_AXI_ARREADY && S_AXI_ARVALID && !S_AXI_RVALID) begin
                S_AXI_RVALID<=1; S_AXI_RRESP<=0; S_AXI_RDATA<=mem[ar_word];
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID<=0;
            end
        end
    end

endmodule

`default_nettype wire
