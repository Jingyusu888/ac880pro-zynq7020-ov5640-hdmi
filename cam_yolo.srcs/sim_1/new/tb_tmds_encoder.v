`timescale 1ns / 1ps
module tb_tmds_encoder;
    reg pixel_clk;
    reg pixel_reset;
    reg [7:0] data_in;
    reg de, c0, c1;
    wire [9:0] tmds_out;
    integer check_count;

    tmds_encoder dut (
        .pixel_clk(pixel_clk), .pixel_reset(pixel_reset),
        .data_in(data_in), .de(de), .c0(c0), .c1(c1),
        .tmds_out(tmds_out)
    );

    initial pixel_clk = 1'b0;
    always #6.737 pixel_clk = ~pixel_clk;

    // Drive inputs at the falling edge; inspect after the next rising edge.
    task check_code;
        input test_de;
        input [1:0] test_control;
        input [7:0] test_data;
        input [9:0] expected_code;
        begin
            @(negedge pixel_clk);
            de = test_de;
            {c1, c0} = test_control;
            data_in = test_data;
            @(posedge pixel_clk);
            #1;
            if (tmds_out !== expected_code)
                $fatal(1, "FAIL: de=%b control=%b data=%h expected=%b actual=%b",
                    test_de, test_control, test_data, expected_code, tmds_out);
            check_count = check_count + 1;
            $display("Check %0d OK: output=%b disparity=%0d",
                check_count, tmds_out, $signed(dut.disparity));
        end
    endtask

    initial begin
        pixel_reset = 1'b1;
        data_in = 8'h00;
        de = 1'b0;
        c0 = 1'b0;
        c1 = 1'b0;
        check_count = 0;
        repeat (5) @(negedge pixel_clk);
        #1;
        pixel_reset = 1'b0;

        check_code(1'b0, 2'b00, 8'h00, 10'b1101010100);
        check_code(1'b0, 2'b01, 8'h00, 10'b0010101011);
        check_code(1'b0, 2'b10, 8'h00, 10'b0101010100);
        check_code(1'b0, 2'b11, 8'h00, 10'b1010101011);

        check_code(1'b1, 2'b00, 8'hFF, 10'b1000000000);
        check_code(1'b1, 2'b00, 8'hFF, 10'b0011111111);
        check_code(1'b1, 2'b00, 8'hFF, 10'b0011111111);
        check_code(1'b1, 2'b00, 8'hFF, 10'b1000000000);

        check_code(1'b0, 2'b00, 8'hFF, 10'b1101010100);
        if (dut.disparity !== 6'sd0)
            $fatal(1, "FAIL: Disparity was not cleared.");
        check_code(1'b1, 2'b00, 8'hFF, 10'b1000000000);
        $display("PASS: All %0d code checks passed.", check_count);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL: Simulation timeout.");
    end
endmodule
