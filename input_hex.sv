`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import precompute::*;
/* verilator lint_on IMPORTSTAR */

module input_hex (
    input  logic clk,
    input  logic rst_n,             // Changed to active-low reset

    // streaming inputs
    input  logic        in_valid,
    input  logic [23:0] in_pixel,   // streaming data from image file via tb_top.sv

    // dynamic image size
    output logic [15:0] width,
    output logic [15:0] height,

    // outputs
    output logic        out_valid,
    output logic        done,
    output rgb_vect_q1014 pixel_out
);

    typedef enum logic [1:0] {
        READ_WIDTH,
        READ_HEIGHT,
        READ_PIXELS
    } state_t;

    state_t state;
    int address;
    int total_pixels;

    // Fixed-point conversion helper (synthesizable, for register)
    function automatic logic signed [Q1014_T-1:0] to_q1014(input logic [7:0] val);
        return $signed({2'b0, val, 14'b0});
    endfunction 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= READ_WIDTH;
            address      <= 0;
            width        <= '0;
            height       <= '0;
            total_pixels <= 0;
            done         <= 1'b0;
            out_valid    <= 1'b0;
            pixel_out    <= '0;
        end else if (done) begin
            state        <= READ_WIDTH;
            address      <= 0;
            done         <= 1'b0;
            out_valid    <= 1'b0;
            pixel_out    <= '0;
        end else if (in_valid) begin
            case (state)
                READ_WIDTH: begin
                    width     <= in_pixel[15:0];
                    state     <= READ_HEIGHT;
                    out_valid <= 1'b0;
                end

                READ_HEIGHT: begin
                    height       <= in_pixel[15:0];
                    total_pixels <= width * in_pixel[15:0];
                    state        <= READ_PIXELS;
                    out_valid    <= 1'b0;
                end

                READ_PIXELS: begin
                    pixel_out[0] <= to_q1014(in_pixel[23:16]); // Red   -> b[0]
                    pixel_out[1] <= to_q1014(in_pixel[15:8]);  // Green -> b[1]
                    pixel_out[2] <= to_q1014(in_pixel[7:0]);   // Blue  -> b[2]
                    out_valid    <= 1'b1;

                    if (address == total_pixels - 1) begin
                        done <= 1'b1;
                    end else begin
                        address <= address + 1;
                    end
                end

                default: begin
                    state     <= READ_WIDTH;
                    out_valid <= 1'b0;
                end
            endcase
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
