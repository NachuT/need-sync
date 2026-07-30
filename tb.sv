`timescale 1ns/1ps

module tb;
    import precompute::*;

    m3x3_q412 matrix_out;

    // Helper task to format and print a 3x3 Q4.12 matrix in Hex and Decimal
    task print_matrix(input string name, input m3x3_q412 m);
        $display("--------------------------------------------------");
        $display("Matrix Output for %s (Q4.12 Fixed-Point):", name);
        $display("--------------------------------------------------");
        for (int r = 0; r < 3; r++) begin
            $display("Row %0d: [ Hex: %04h  %04h  %04h ] | [ Real: %7.4f  %7.4f  %7.4f ]", 
                r, 
                m[r][0], m[r][1], m[r][2],
                real'(m[r][0]) / 4096.0, 
                real'(m[r][1]) / 4096.0, 
                real'(m[r][2]) / 4096.0
            );
        end
        $display("");
    endtask

    initial begin
        $display("\n================ START SIMULATION ================\n");

        // Mode 1: Protanopia
        matrix_out = m_precompute(1);
        print_matrix("Protanopia (Mode 1)", matrix_out);

        // Mode 2: Deuteranopia
        matrix_out = m_precompute(2);
        print_matrix("Deuteranopia (Mode 2)", matrix_out);

        // Mode 3: Tritanopia
        matrix_out = m_precompute(3);
        print_matrix("Tritanopia (Mode 3)", matrix_out);

        $display("================ END SIMULATION ==================\n");
        $finish;
    end

endmodule
