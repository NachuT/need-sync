`timescale 1ns/1ps

package precompute;

    localparam PIXEL_T = 8; 
    localparam Q412_T  = 16; 
    localparam Q1014_T = 24; 

    typedef logic signed [2:0][Q1014_T-1:0]       rgb_vect_q1014;  
    typedef logic [2:0][PIXEL_T-1:0]       rgb_vect_pixel;  
    typedef logic signed [2:0][2:0][Q412_T-1:0]  m3x3_q412;  
    typedef logic signed [2:0][2:0][Q1014_T-1:0] m3x3_q1014; 

    // Completely precalculated and pre-multiplied static Q4.12 fixed-point matrices.
    // All floating-point math, classes, and real types have been entirely stripped out
    // and resolved beforehand to make synthesis 100% clean for Yosys and Verilator.

    function automatic m3x3_q412 m_precompute(input int mode);
        case (mode)
            1: begin // Protanopia (Fully pre-multiplied & scaled to Q4.12 integers)
                return '{
                    '{16'sd4096, 16'sd0,    16'sd0},
                    '{16'sd0,    16'sd4096, 16'sd0},
                    '{16'sd0,    16'sd1843, 16'sd4096}
                };
            end
            2: begin // Deuteranopia (Fully pre-multiplied & scaled to Q4.12 integers)
                return '{
                    '{16'sd2867, 16'sd0,    16'sd4096},
                    '{16'sd0,    16'sd2867, 16'sd4096},
                    '{16'sd0,    16'sd0,    16'sd4096}
                };
            end
            3: begin // Tritanopia (Fully pre-multiplied & scaled to Q4.12 integers)
                return '{
                    '{16'sd4096, 16'sd2867, 16'sd0},
                    '{16'sd4096, 16'sd2867, 16'sd0},
                    '{16'sd0,    16'sd0,    16'sd4096}
                };
            end
            default: begin // Identity / Fallback
                return '{
                    '{16'sd4096, 16'sd0,    16'sd0},
                    '{16'sd0,    16'sd4096, 16'sd0},
                    '{16'sd0,    16'sd0,    16'sd4096}
                };
            end
        endcase
    endfunction

endpackage
