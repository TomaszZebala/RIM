`timescale 1ns / 1ps
module student_block (
    input  wire        clk,
    input  wire        resetn,

    // ---- wejście: ramka N próbek z otoczki (capture_replay) ----
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
  
    // ---- wyjście: wynik do DMA ----
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);
    assign m_axis_tdata  = s_axis_tdata+1;
    assign m_axis_tvalid = s_axis_tvalid;
    assign s_axis_tready = m_axis_tready;
    assign m_axis_tlast  = s_axis_tlast;
endmodule
