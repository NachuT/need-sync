`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import precompute::*;
/* verilator lint_on IMPORTSTAR */

module top #(
    parameter int N      = 3,
    parameter int DW_A   = Q412_T,
    parameter int DW_B   = Q1014_T,
    parameter int ACC_W  = 44,
    parameter int ADDR_W = (N > 1) ? $clog2(N) : 1,
    parameter int MODE   = 1  // 1 = protanopia, 2 = deuteranopia, 3 = tritanopia
) (
    input  logic clk,
    input  logic rst_n,
    input  logic in_valid, // pixel streaming input is valid
    input  logic [23:0] in_pixel, // pixel streaming directly from tb_top.sv for input_hex interface
    output logic done
);

    // Precomputed 3x3 color-correction matrix
    localparam m3x3_q412 MODESELECT = m_precompute(MODE);

    // ------------------------------------------------------------------
    // TIMING FIX
    // ------------------------------------------------------------------
    // PIPE_DELAY = exact number of cycles from an ib_out_valid pixel
    // arriving to that pixel's result being valid at matmul_rd_data.
    // Traced for N=3 (current instantiation) as follows:
    //   +1  ib_out_valid -> matmul_ld_en/start (registered a cycle late
    //       in the "load data" always_ff block below)
    //   +7  matmul start -> done (N=3 taps through the k_running FSM,
    //       then mac's 2-stage multiply/accumulate pipeline, then the
    //       2-cycle last_reg shift that gates `done`)
    //   +1  done (=c_wr_en) -> mem_c's registered write/read-bypass
    //       makes rd_data valid the cycle after the write
    //   = 9 cycles total, ib_out_valid(T) -> matmul_rd_data valid at T+9
    //
    // If N, DW_A/DW_B, ACC_W, or matmul's internal FSM ever change,
    // RE-MEASURE this by instrumenting matmul with a free-running cycle
    // counter reset on `start` and $display'd on `done` in simulation --
    // do not just guess. Getting this wrong is what caused the original
    // "blurry" output: lanes were being restarted mid-accumulation.
    localparam int PIPE_DELAY = 9;

    // NUM_MATMULS = number of parallel lanes. Because pixels stream in
    // back-to-back (one per cycle, see tb_top.sv), a given lane index is
    // reused every NUM_MATMULS cycles. That reuse gap MUST be >= PIPE_DELAY
    // or a lane gets a new `start`/`ld_en` while its previous pixel's
    // accumulation is still in flight, corrupting acc_reg/k mid-sum --
    // this is what produced the blur/ghosting artifact. We size this a
    // few cycles above PIPE_DELAY for margin rather than using an exact
    // (fragile, off-by-one-prone) equality.
    localparam int NUM_MATMULS = PIPE_DELAY + 3; // = 12 for N=3

    // Pointer width now derived from NUM_MATMULS instead of a hardcoded
    // 3-bit literal -- the original code's `3'(NUM_MATMULS - 1)` casts
    // silently truncated if NUM_MATMULS ever grew past 8.
    localparam int PTR_W = $clog2(NUM_MATMULS);

    // input_hex relevant variables
    logic [15:0]    width, height;
    logic [31:0]    total_pixels;
    logic           ib_out_done, ib_out_valid; // input buffer's output is done, valid
    rgb_vect_q1014  ib_out_pixel_rgbvect; // input buffer's output rgb vector as an 8-bit pixel

    assign total_pixels = 32'(width) * 32'(height);

    // Round robin management
    logic [PTR_W-1:0]      wr_ptr = '0;
    logic [PTR_W-1:0]      rd_ptr = '0;
    logic [PIPE_DELAY-1:0] ptr_pipe; // makes rd_ptr lag wr_ptr by PIPE_DELAY cycles; tracks ib_out_valid

    // Parallel signals for matmul units
    logic [NUM_MATMULS-1:0]        matmul_start;
    logic [NUM_MATMULS-1:0]        matmul_ld_en;
    logic [NUM_MATMULS-1:0]        matmul_rd_en;
    logic [NUM_MATMULS-1:0]        matmul_done;
    rgb_vect_q1014                 matmul_ld_data [NUM_MATMULS];
    rgb_vect_pixel                 matmul_rd_data [NUM_MATMULS];

    // Matmul outputs
    rgb_vect_pixel                 matmul_out_pixel_rgbvect;
    logic                          matmul_out_valid; // purely for input to output buffer

    // FSM
    typedef enum logic {
        IDLE    = 1'b0,
        COMPUTE = 1'b1
    } state_t;
    state_t state, next_state;

    logic       done_latched;
    logic [2:0] delay_cnt;

    // Input reader (continuous streaming via top_tb.sv)
    input_hex u_input_hex (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_pixel  (in_pixel),
        .width     (width),
        .height    (height),
        .out_valid (ib_out_valid),
        .done      (ib_out_done),
        .pixel_out (ib_out_pixel_rgbvect)
    );

    // Output writer
    output_hex u_output_hex (
        .clk            (clk),
        .valid_in       (matmul_out_valid),
        .width          (width),
        .height         (height),
        .rgb_vect_pixel (matmul_out_pixel_rgbvect),
        .done           (done)
    );

    // Initialize NUM_MATMULS matmuls in parallel
    generate
        for (genvar i = 0; i < NUM_MATMULS; i++) begin : g_matmul
            matmul #(
                .N            (N),
                .DW_A         (DW_A),
                .DW_B         (DW_B),
                .ACC_W        (ACC_W),
                .ADDR_W       (ADDR_W),
                .M_PRECOMPUTE (MODESELECT)
            ) u_matmul (
                .clk     (clk),
                .rst_n   (rst_n),
                .start   (matmul_start[i]),
                .done    (matmul_done[i]),
                .ld_en   (matmul_ld_en[i]),
                .ld_addr ('0),
                .ld_data (matmul_ld_data[i]),
                .rd_en   (matmul_rd_en[i]),
                .rd_addr ('0),
                .rd_data (matmul_rd_data[i])
            );
        end
    endgenerate

    // increment through robin (wr_ptr and rd_ptr decoupled by PIPE_DELAY cycles)
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || state == IDLE) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            ptr_pipe <= '0;
        end else if (state == COMPUTE) begin
            // shift register tracking when valid inputs passed
            ptr_pipe <= {ptr_pipe[PIPE_DELAY-2:0], ib_out_valid};

            // write pointer responds immediately
            if (ib_out_valid) begin
                if (wr_ptr == PTR_W'(NUM_MATMULS - 1)) wr_ptr <= '0;
                else wr_ptr <= wr_ptr + 1'b1;
            end

            // read pointer lags by PIPE_DELAY cycles
            if (ptr_pipe[PIPE_DELAY-1]) begin
                if (rd_ptr == PTR_W'(NUM_MATMULS - 1)) rd_ptr <= '0;
                else rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    // load data
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || state == IDLE) begin
            matmul_ld_en <= '0;
            matmul_start <= '0;
            for (int i = 0; i < NUM_MATMULS; i++) begin
                matmul_ld_data[i] <= '0;
            end
        end else begin
            matmul_ld_en <= '0;
            matmul_start <= '0;

            if (ib_out_valid) begin
                for (int i = 0; i < NUM_MATMULS; i++) begin
                    if (PTR_W'(i) == wr_ptr) begin
                        matmul_ld_en[i] <= 1'b1;
                        matmul_start[i] <= 1'b1;
                    end else begin
                        matmul_ld_en[i] <= 1'b0;
                        matmul_start[i] <= 1'b0;
                    end
                end
                matmul_ld_data[wr_ptr] <= ib_out_pixel_rgbvect;
            end
        end
    end

    // unload data - relaxed dependency to prevent pipeline lockups
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || state == IDLE) begin
            matmul_rd_en             <= '0;
            matmul_out_valid         <= 1'b0;
            matmul_out_pixel_rgbvect <= '0;
        end else begin
            matmul_rd_en     <= '0;
            matmul_out_valid <= 1'b0;

            if (ptr_pipe[PIPE_DELAY-1]) begin
                matmul_out_valid <= 1'b1;
                for (int i = 0; i < NUM_MATMULS; i++) begin
                    if (PTR_W'(i) == rd_ptr) begin
                        matmul_rd_en[i] <= 1'b1;
                        matmul_out_pixel_rgbvect <= matmul_rd_data[i];
                    end else begin
                        matmul_rd_en[i] <= 1'b0;
                    end
                end
            end
        end
    end

    // FSM & Delay Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state        <= IDLE;
            done_latched <= 1'b0;
            delay_cnt    <= '0;
        end else begin
            state <= next_state;

            if (state == IDLE) begin
                done_latched <= 1'b0;
                delay_cnt    <= '0;
            end else begin
                if (done) begin
                    done_latched <= 1'b1;
                end

                if (done || done_latched) begin
                    delay_cnt <= delay_cnt + 1'b1;
                end
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (in_valid) next_state = COMPUTE;
            end
            COMPUTE: begin
                if (delay_cnt == 3'd5) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

endmodule
