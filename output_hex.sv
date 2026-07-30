`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import precompute::*;
/* verilator lint_on IMPORTSTAR */

module output_hex (
    input  logic          clk,
    input  logic          valid_in,
    input  logic [15:0]   width,
    input  logic [15:0]   height,
    input  rgb_vect_pixel rgb_vect_pixel,
    output logic          done = 1'b0
);

    int fd;
    int pixel_count    = 0;
    int total_pixels   = 0;
    logic header_written = 1'b0;

    initial begin
        fd = $fopen("verilog_output.hex", "w");
        if (fd == 0) begin
            $display("Error: Could not open verilog_output.hex");
        end
    end

    always_ff @(posedge clk) begin
        if (width == 0 || height == 0) begin
            pixel_count    <= 0;
            total_pixels   <= 0;
            header_written <= 1'b0;
            done           <= 1'b0;
        end else if (!done) begin
            // Latch total_pixels once dimensions are known
            if (total_pixels == 0) begin
                total_pixels <= int'(width) * int'(height);
            end

            // Write header exactly once
            if (!header_written && fd != 0) begin
                $fdisplay(fd, "%0d", width);
                $fdisplay(fd, "%0d", height);
                header_written <= 1'b1;
            end

            // Write one pixel per valid beat
            if (valid_in && fd != 0) begin
                $fdisplay(fd, "%02h%02h%02h", rgb_vect_pixel[0], rgb_vect_pixel[1], rgb_vect_pixel[2]);
                pixel_count <= pixel_count + 1;

                // Close file and assert done after the last pixel
                if (total_pixels > 0 && (pixel_count + 1 >= total_pixels)) begin
                    $fclose(fd);
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
