package precompute;

    localparam PIXEL_T = 8; 
    localparam Q412_T  = 16; 
    localparam Q1014_T = 24; 

    typedef real m3x3_real[3][3];

    typedef logic signed [2:0][Q1014_T-1:0]       rgb_vect_q1014;  
    typedef logic [2:0][PIXEL_T-1:0]       rgb_vect_pixel;  
    typedef logic signed [2:0][2:0][Q412_T-1:0]  m3x3_q412;  
    typedef logic signed [2:0][2:0][Q1014_T-1:0] m3x3_q1014; 

    localparam m3x3_real M_IDE = '{
        '{1.0, 0.0, 0.0},
        '{0.0, 1.0, 0.0},
        '{0.0, 0.0, 1.0}
    };

    
    localparam m3x3_real M_PRO_SIM = '{ '{0.0, 2.02344, -2.52581}, '{0.0, 1.0, 0.0}, '{0.0, 0.0, 1.0} };
    localparam m3x3_real M_PRO_ES  = '{ '{1.0, 0.0, 0.0}, '{0.0, 1.0, 0.0}, '{0.0, 0.45, 1.0} };
    
    localparam m3x3_real M_DUT_SIM = '{ '{1.0, 0.0, 0.0}, '{0.494207, 0.0, 1.24827}, '{0.0, 0.0, 1.0} };
    localparam m3x3_real M_DUT_ES  = '{ '{0.7, 0.0, 1.0}, '{0.0, 0.7, 1.0}, '{0.0, 0.0, 1.0} };

    localparam m3x3_real M_TRI_SIM = '{ '{1.0, 0.0, 0.0}, '{0.0, 1.0, 0.0}, '{-0.395913, 0.801109, 0.0} };
    localparam m3x3_real M_TRI_ES  = '{ '{1.0, 0.7, 0.0}, '{1.0, 0.7, 0.0}, '{0.0, 0.0, 1.0} };
    
    localparam m3x3_real M_RGB_TO_LMS = '{ '{17.8824, 43.5161, 4.11935}, '{3.45565, 27.1554, 3.86714}, '{0.0299566, 0.184309, 1.46709} };
    localparam m3x3_real M_LMS_TO_RGB = '{ 
        '{0.0809444479,    -0.130504409,   0.116721066}, 
        '{-0.0102485335,    0.0540193266,  -0.113614708}, 
        '{-0.000365296938, -0.00412161469, 0.693511405} 
    };

    function automatic logic signed [Q412_T-1:0] float_to_q412(input real val);
        real scaled;
        /* verilator lint_off UNUSEDSIGNAL */
        integer int_val; 
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            scaled = val * 4096.0; 
            int_val = (scaled >= 0.0) ? $rtoi(scaled + 0.5) : $rtoi(scaled - 0.5); 
            return int_val[Q412_T-1:0]; 
        end
    endfunction

    /* verilator lint_off DECLFILENAME */
    class MatrixEvaluator;
        static function m3x3_real m_mul(m3x3_real A, m3x3_real B);
            return '{
                '{ A[0][0]*B[0][0] + A[0][1]*B[1][0] + A[0][2]*B[2][0],
                   A[0][0]*B[0][1] + A[0][1]*B[1][1] + A[0][2]*B[2][1],
                   A[0][0]*B[0][2] + A[0][1]*B[1][2] + A[0][2]*B[2][2] },
                '{ A[1][0]*B[0][0] + A[1][1]*B[1][0] + A[1][2]*B[2][0],
                   A[1][0]*B[0][1] + A[1][1]*B[1][1] + A[1][2]*B[2][1],
                   A[1][0]*B[0][2] + A[1][1]*B[1][2] + A[1][2]*B[2][2] },
                '{ A[2][0]*B[0][0] + A[2][1]*B[1][0] + A[2][2]*B[2][0],
                   A[2][0]*B[0][1] + A[2][1]*B[1][1] + A[2][2]*B[2][1],
                   A[2][0]*B[0][2] + A[2][1]*B[1][2] + A[2][2]*B[2][2] }
            };
        endfunction

        static function m3x3_real m_add(m3x3_real A, m3x3_real B);
            return '{
                '{A[0][0]+B[0][0], A[0][1]+B[0][1], A[0][2]+B[0][2]},
                '{A[1][0]+B[1][0], A[1][1]+B[1][1], A[1][2]+B[1][2]},
                '{A[2][0]+B[2][0], A[2][1]+B[2][1], A[2][2]+B[2][2]}
            };
        endfunction

        static function m3x3_real m_sub(m3x3_real A, m3x3_real B);
            return '{
                '{A[0][0]-B[0][0], A[0][1]-B[0][1], A[0][2]-B[0][2]},
                '{A[1][0]-B[1][0], A[1][1]-B[1][1], A[1][2]-B[1][2]},
                '{A[2][0]-B[2][0], A[2][1]-B[2][1], A[2][2]-B[2][2]}
            };
        endfunction

        static function m3x3_q412 compute(input int mode);
            m3x3_real m_sim, m_shift; 
            m3x3_real m_lms_sim, m_rgb2, m_diff, m_map, m_out; 

            case (mode)
                1: begin m_sim = M_PRO_SIM; m_shift = M_PRO_ES; end
                2: begin m_sim = M_DUT_SIM; m_shift = M_DUT_ES; end
                3: begin m_sim = M_TRI_SIM; m_shift = M_TRI_ES; end
                default: begin m_sim = M_PRO_SIM; m_shift = M_PRO_ES; end
            endcase

            m_lms_sim = m_mul(m_sim, M_RGB_TO_LMS); 
            m_rgb2    = m_mul(M_LMS_TO_RGB, m_lms_sim); 
            m_diff    = m_sub(M_IDE, m_rgb2);
            m_map     = m_mul(m_shift, m_diff);
            m_out     = m_add(M_IDE, m_map);

            return '{
                '{float_to_q412(m_out[0][2]), float_to_q412(m_out[1][2]), float_to_q412(m_out[2][2])},
                '{float_to_q412(m_out[0][1]), float_to_q412(m_out[1][1]), float_to_q412(m_out[2][1])},
                '{float_to_q412(m_out[0][0]), float_to_q412(m_out[1][0]), float_to_q412(m_out[2][0])}
            };
        endfunction
    endclass
    /* verilator lint_on DECLFILENAME */

    function automatic m3x3_q412 m_precompute(input int mode);
        return MatrixEvaluator::compute(mode);
    endfunction

endpackage

