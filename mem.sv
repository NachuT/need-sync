`timescale 1ns/1ps
module mem #(
    parameter ROWS = 8,      
    parameter COLS = 8,      
    parameter DW   = 16,
    parameter ADDR_W = (COLS > 1) ? $clog2(COLS) : 1,
    /* verilator lint_off WIDTHTRUNC */
    // ✅ FIX: Mark parameter array as signed
    
    /* verilator lint_on WIDTHTRUNC */  
)
(
    input  logic                            clk,
    input  logic                            wr_en,
    input  logic signed [ROWS-1:0][DW-1:0]  wr_data,
    input  logic        [ADDR_W-1:0]        wr_addr,
    input  logic        [ADDR_W-1:0]        rd_addr,
    output logic signed [ROWS-1:0][DW-1:0]  rd_data
);
logic signed [COLS-1:0][ROWS-1:0][DW-1:0] memory;

initial begin
    memory = '0;
end
    /* verilator lint_off PROCASSINIT */
    logic signed [COLS-1:0][ROWS-1:0][DW-1:0] memory = M_PRECOMPUTE;
    /* verilator lint_on PROCASSINIT */

    always_ff @(posedge clk) begin
        if (wr_en) begin
            memory[wr_addr] <= wr_data;
        end

        if (wr_en && (wr_addr == rd_addr)) begin
            rd_data <= wr_data;
        end else begin
            rd_data <= memory[rd_addr];
        end
    end

endmodule
