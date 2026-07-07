`timescale 1ns/1ps

module tb_hr_top;

    reg clk;
    reg rst_n;
    reg start;
    reg signed [15:0] feature_in;
    reg valid;

    wire ready;
    wire done;
    wire [1:0] result;

    hr_top dut(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .feature_in(feature_in),
        .valid(valid),
        .ready(ready),
        .done(done),
        .result(result)
    );

    //--------------------------------
    // clock 50MHz
    //--------------------------------
    always #10 clk = ~clk;

    integer k;

    reg signed [15:0] testvec [0:11];

    initial
    begin
        //--------------------------------
        // INIT
        //--------------------------------
        clk = 0;
        rst_n = 0;
        start = 0;
        valid = 0;
        feature_in = 0;

        //--------------------------------
        // CHỌN TEST CASE (đổi ở đây)
        //--------------------------------
        // label = 2
        testvec[0]  = 16'd1537;
        testvec[1]  = 16'd78;
        testvec[2]  = 16'd3623;
        testvec[3]  = 16'd24;
        testvec[4]  = 16'd6011;
        testvec[5]  = 16'd9657;
        testvec[6]  = 16'd3622;
        testvec[7]  = 16'd3623;
        testvec[8]  = 16'd4073;
        testvec[9]  = 16'd2674;
        testvec[10] = 16'd6240;
        testvec[11] = 16'd1399;

        //--------------------------------
        // RESET
        //--------------------------------
        #100;
        rst_n = 1;

        //--------------------------------
        // START
        //--------------------------------
        @(posedge clk);
        start = 1;

        //--------------------------------
        // SEND 12 FEATURES
        //--------------------------------
        for(k=0;k<12;k=k+1)
        begin
            @(posedge clk);
            valid = 1;
            feature_in = testvec[k];

            $display("send[%0d] = %0d", k, testvec[k]);
        end

        @(posedge clk);
        valid = 0;
        feature_in = 0;
        start = 0;

        //--------------------------------
        // WAIT RESULT
        //--------------------------------
        wait(done == 1);

    

        #100;
        $stop;
    end

endmodule