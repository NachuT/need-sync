`timescale 1ns/1ps

/* verilator lint_off IMPORTSTAR */
import precompute::*;
/* verilator lint_on IMPORTSTAR */

module matmul #(
    parameter N      = 3,      
    parameter DW_A   = precompute::Q412_T,   
    parameter DW_B   = precompute::Q1014_T,   
    parameter ACC_W  = 44, 
    parameter ADDR_W = (N > 1) ? $clog2(N) : 1,
) (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            start, 
    output logic                            done, 
    input  logic                            ld_en,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [ADDR_W-1:0]               ld_addr, 
    input  precompute::rgb_vect_q1014       ld_data, 
    input  logic                            rd_en,   
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [ADDR_W-1:0]               rd_addr,
    output precompute::rgb_vect_pixel       rd_data 
);

    logic signed [COLS-1:0][ROWS-1:0][DW-1:0] memory;

    initial begin
        memory = '0;
    end 

    localparam IDLE = 1'b0, COMPUTE = 1'b1;
    logic state;
    logic                    a_wr_en, b_wr_en, c_wr_en;
    logic [ADDR_W-1:0]       a_wr_addr, c_wr_addr;
    logic signed [N-1:0][DW_A-1:0] a_wr_data;
    logic [ADDR_W-1:0]       a_rd_addr;

    assign a_wr_en   = 1'b0;
    assign a_wr_addr = '0;
    assign a_wr_data = '0;

    logic signed [N-1:0][DW_A-1:0]  a; 
    logic signed [N-1:0][DW_B-1:0]  b;   
    logic signed [DW_B-1:0]         b_scalar;
    logic                           valid_in, clear_acc, finished, valid_out;
    logic [7:0]                     pixel_out_0, pixel_out_1, pixel_out_2; 
    logic [N-1:0][7:0]              pixel_out_bus; 
    logic                           valid_out_0, valid_out_1, valid_out_2;

    logic [ADDR_W-1:0]       k; 
    logic [ADDR_W-1:0]       k_save; 
    logic                    last_reg [0:1]; 

    logic                    k_running;
    logic                    k_running_save;
    logic                    pass_done; 

    assign b_wr_en = ld_en;

    assign valid_in  = k_running_save;
    assign clear_acc = k_running_save && (k_save == 0);
    assign finished  = k_running_save && (k_save == N-1);
    assign valid_out = valid_out_0 && valid_out_1 && valid_out_2;

    assign pixel_out_bus = '{pixel_out_0, pixel_out_1, pixel_out_2};

    // FIX: Force explicit $signed on array slice
    assign b_scalar = $signed(b[k_save]);

    // FIX — Channel swap: SV packed array assigns first element of
    // '{r0,r1,r2} to MSB (a[2]=r0), last to LSB (a[0]=r2).
    // So a[0]=blue row, a[2]=red row.  Swap .a ports so mac_0 (→ R)
    // multiplies by the red row and mac_2 (→ B) by the blue row.
    mac #(.DW_A(DW_A), .DW_B(DW_B), .ACC_W(ACC_W)) mac_0 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .clear_acc(clear_acc), .finished(finished), 
               .a($signed(a[0])), .b(b_scalar), .valid_out(valid_out_0), .pixel_out(pixel_out_0)
    );
    
    mac #(.DW_A(DW_A), .DW_B(DW_B), .ACC_W(ACC_W)) mac_1 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .clear_acc(clear_acc), .finished(finished), 
        .a($signed(a[1])), .b(b_scalar), .valid_out(valid_out_1), .pixel_out(pixel_out_1)
    );
    
    mac #(.DW_A(DW_A), .DW_B(DW_B), .ACC_W(ACC_W)) mac_2 (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .clear_acc(clear_acc), .finished(finished), 
                .a($signed(a[2])), .b(b_scalar), .valid_out(valid_out_2), .pixel_out(pixel_out_2)
    );   

    mem #(.DW(DW_A), .ROWS(N), .COLS(N), .ADDR_W(ADDR_W), .M_PRECOMPUTE(M_PRECOMPUTE)) mem_a (
        .clk(clk), .wr_en(a_wr_en), .wr_addr(a_wr_addr), .wr_data(a_wr_data), .rd_addr(a_rd_addr), .rd_data(a)
    );

    mem #(.DW(DW_B), .ROWS(N), .COLS(1))
    mem_b (.clk(clk), .wr_en(b_wr_en), .wr_addr('0), .wr_data($unsigned(ld_data)), .rd_addr('0), .rd_data(b));

    mem #(.DW(8), .ROWS(N), .COLS(1), .ADDR_W(ADDR_W))
    mem_c (.clk(clk), .wr_en(c_wr_en), .wr_addr(c_wr_addr), .wr_data($unsigned(pixel_out_bus)), .rd_addr(rd_addr), .rd_data(rd_data));

    assign a_rd_addr = k;
    assign c_wr_addr = '0; 
    assign c_wr_en   = valid_out && last_reg[1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k         <= '0;
            k_running <= 1'b0;
            pass_done <= 1'b0;
        end else if (state != COMPUTE) begin
            k         <= '0;
            k_running <= 1'b0;
            pass_done <= 1'b0;
        end else if (!k_running && !pass_done) begin
            k_running <= 1'b1;
        end else if (k_running && (k == N - 1)) begin
            k_running <= 1'b0;
            pass_done <= 1'b1;
        end else if (k_running) begin
            k <= k + 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_reg[0] <= 1'b0; 
            last_reg[1] <= 1'b0;
        end else begin
            last_reg[0] <= finished;
            last_reg[1] <= last_reg[0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE:    if (start) state <= COMPUTE;
                COMPUTE: if (done)  state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end 

    assign done = (state == COMPUTE) && valid_out && last_reg[1]; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k_save         <= '0;
            k_running_save <= 1'b0;
        end else begin
            k_save         <= k; 
            k_running_save <= k_running;
        end 
    end 

    // ==================================================================
    // DEBUG INSTRUMENTATION (temporary) — pure $display, drives nothing,
    // reads only existing signals/parameters. Safe to delete afterward.
    // =================================================================

 

endmodule
