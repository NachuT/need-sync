`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import precompute::*;
/* verilator lint_on IMPORTSTAR */

module mac #(
    parameter DW_A  = 16,     // Q4.12 signed matrix weight
    parameter DW_B  = 24,     // Q10.14 signed input pixel
    parameter ACC_W = 44      // Accumulator width
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic signed [DW_A-1:0] a,          // Signed weight
    input  logic signed [DW_B-1:0] b,          // Signed pixel operand
    input  logic                   valid_in,   
    input  logic                   clear_acc,  
    input  logic                   finished, 
    output logic                   valid_out,
    output logic [PIXEL_T-1:0]     pixel_out        
);
    logic signed [ACC_W-1:0] mult_q;
    logic valid_in_q;
    logic clear_acc_q;
    logic finished_q;      
    logic signed [ACC_W-1:0] acc_reg;

    // Stage 1: Multiply (Q4.12 * Q10.14 = Q14.26)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_q      <= '0;
            valid_in_q  <= 1'b0;
            clear_acc_q <= 1'b0;
            finished_q  <= 1'b0;   
        end else begin 
            mult_q      <= $signed(a) * $signed(b); 
            valid_in_q  <= valid_in;
            clear_acc_q <= clear_acc;
            finished_q  <= finished; 
        end
    end

    // Stage 2: Accumulate and Scale down from Q14.26 -> 8-bit Pixel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg   <= '0;
            pixel_out <= '0;  
            valid_out <= 1'b0;
        end else begin
            valid_out <= finished_q;

            if (valid_in_q) begin
                if (clear_acc_q) begin
                    acc_reg <= mult_q; // Clear and load step 0
                end else begin
                    acc_reg <= acc_reg + mult_q; // Accumulate step 1, 2
                end
            end

            if (finished_q) begin 
                // Calculate next full sum including the current mult_q
                automatic logic signed [ACC_W-1:0] full_sum;
                full_sum = (clear_acc_q) ? mult_q : (acc_reg + mult_q);

                // Q4.12 * Q10.14 -> Q14.26 saturation and rounding
                if (full_sum > (44'sd255 <<< 26)) begin
                    pixel_out <= 8'd255;
                end else if (full_sum < 44'sd0) begin
                    pixel_out <= 8'd0;
                end else begin
                    // Add 0.5 (1 <<< 25) for rounding before right shifting
                    pixel_out <= 8'((full_sum + (44'sd1 <<< 25)) >>> 26);
                end
            end
        end
    end

endmodule
