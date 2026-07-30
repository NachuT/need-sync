`timescale 1ns/1ps

module tb_top;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic [23:0] in_pixel;
    logic done;

    // Instantiate the Top module
    top #(
        .N    (3),
        .MODE (3)  // 1 = Protanopia, 2 = Deuteranopia, 3 = Tritanopia
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (in_valid),
        .in_pixel (in_pixel),
        .done (done)  // Matches top.sv's output declaration!
    );

    // Clock Generation: 100 MHz clock (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // Test stimulus execution
    initial begin
        int fd;
        int status;
        int width, height;
        int total_pixels;
        int progress_step;
        logic [23:0] temp_pixel;

        $display("\n==================================================");
        $display("===          tb_top SIMULATION START           ===");
        $display("==================================================");


        // Diagnostic: print all 9 weights in MODESELECT
        // MODESELECT[col][row] — col=k=input channel, row=mac output
        $display("[DIAG] MODESELECT[0] (R-input col): row0=%0d row1=%0d row2=%0d",
            $signed(dut.MODESELECT[0][0]), $signed(dut.MODESELECT[0][1]), $signed(dut.MODESELECT[0][2]));
        $display("[DIAG] MODESELECT[1] (G-input col): row0=%0d row1=%0d row2=%0d",
            $signed(dut.MODESELECT[1][0]), $signed(dut.MODESELECT[1][1]), $signed(dut.MODESELECT[1][2]));
        $display("[DIAG] MODESELECT[2] (B-input col): row0=%0d row1=%0d row2=%0d",
            $signed(dut.MODESELECT[2][0]), $signed(dut.MODESELECT[2][1]), $signed(dut.MODESELECT[2][2]));
        // Expected Q4.12: m_out[row][col]*4096
        // row0: [1.0, 0.0, 0.0] -> [4096, 0, 0]
        // row1: [0.5089, 0.4910, 0] -> [2085, 2011, 0]
        // row2: [0.6173, -0.6173, 1.0] -> [2529, -1529, 4096]
        // MODESELECT[col=0][row0]=4096, [col=0][row1]=2085, [col=0][row2]=2529
        // MODESELECT[col=1][row0]=0,    [col=1][row1]=2011, [col=1][row2]=-1529
        // MODESELECT[col=2][row0]=0,    [col=2][row1]=0,    [col=2][row2]=4096


        // 1. Initialize Signals
        rst_n    = 0;
        in_valid = 0;
        in_pixel = '0;

        // Hold reset for 3 cycles
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // 2. Open input hex file
        fd = $fopen("output.hex", "r");
        if (fd == 0) begin
            $fatal(1, "[TB_TOP ERROR] Could not open output.hex for reading!");
        end

        // 3. Read image dimensions from header
        status = $fscanf(fd, "%d\n", width);
        status = $fscanf(fd, "%d\n", height);
        total_pixels = width * height;
        progress_step = total_pixels / 10; // 10% increments
        
        $display("[TB_TOP] Streaming image dimensions: %0dx%0d (%0d total pixels)", width, height, total_pixels);

        // 4. Stream width first into the DUT
        @(posedge clk);
        in_valid <= 1'b1;
        in_pixel <= {8'b0, width[15:0]}; 

        // 5. Stream height next
        @(posedge clk);
        in_pixel <= {8'b0, height[15:0]}; 

        // 6. Stream all pixels sequentially with a progress tracker
        $write("[TB_TOP Progress] [          ] 0%%\r");
        
        for (int i = 0; i < total_pixels; i++) begin
            @(posedge clk);
            if ($feof(fd)) begin
                $fatal(1, "[TB_TOP ERROR] Unexpected EOF while reading pixels at index %0d of %0d", i, total_pixels);
            end
            status = $fscanf(fd, "%h\n", temp_pixel);
            in_pixel <= temp_pixel;

            // Update text progress bar every 10%
            if (progress_step > 0 && (i % progress_step == 0)) begin
                int percent = (i * 10) / total_pixels;
                case (percent)
                    0:  $write("[TB_TOP Progress] [>         ] 10%%\r");
                    1:  $write("[TB_TOP Progress] [==>       ] 20%%\r");
                    2:  $write("[TB_TOP Progress] [===>      ] 30%%\r");
                    3:  $write("[TB_TOP Progress] [====>     ] 40%%\r");
                    4:  $write("[TB_TOP Progress] [=====>    ] 50%%\r");
                    5:  $write("[TB_TOP Progress] [======>   ] 60%%\r");
                    6:  $write("[TB_TOP Progress] [=======>  ] 70%%\r");
                    7:  $write("[TB_TOP Progress] [========> ] 80%%\r");
                    8:  $write("[TB_TOP Progress] [=========>] 90%%\r");
                    default: ;
                endcase
            end
        end

        // 7. Deassert in_valid after streaming completes
        @(posedge clk);
        in_valid <= 1'b0;
        in_pixel <= '0;
        
        $write("[TB_TOP Progress] [==========] 100%%\n");
        $fclose(fd);
        $display("[TB_TOP] Finished streaming all pixels to DUT. Waiting for completion...");

        // 8. Wait for pipeline completion with a safety timeout guard
        fork
            begin
                wait (done);
                $display("\n[TB_TOP SUCCESS] Pipeline processing complete! done asserted.");
            end
            begin
                repeat (200_000_000) @(posedge clk);
                $fatal(1, "\n[TB_TOP ERROR] TIMEOUT waiting for top.done after 200M cycles.");
            end
        join_any

        // Let simulation settle a few cycles before ending
        repeat (10) @(posedge clk);
        $display("==================================================");
        $display("===          tb_top SIMULATION END             ===");
        $display("==================================================");
        $finish;
    end

endmodule
