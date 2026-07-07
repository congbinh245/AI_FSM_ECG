module hr_top(
    input clk,
    input rst_n,
    input start,

    input signed [15:0] feature_in,
    input valid,

    output ready,
    output reg done,
    output reg [1:0] result
);

    //--------------------------------
    // FSM
    //--------------------------------
    localparam IDLE      = 4'd0;
    localparam LOAD      = 4'd1;
    localparam NORMALIZE = 4'd2;
    localparam FC1       = 4'd3;
    localparam FC1_BIAS  = 4'd4;
    localparam RELU      = 4'd5;
    localparam FC2       = 4'd6;
    localparam FC2_BIAS  = 4'd7;
    localparam ARGMAX    = 4'd8;
    localparam DONE_S    = 4'd9;

    reg [3:0] state;

    assign ready = (state == LOAD);

    //--------------------------------
    // buffers
    //--------------------------------
    reg signed [15:0] x      [0:11];
    reg signed [15:0] x_norm [0:11];
    reg signed [31:0] h [0:7];
    reg signed [31:0] y [0:3];
    //--------------------------------
    // counters
    //--------------------------------
    reg [6:0] cnt;
    integer i;
    //--------------------------------
    // softmax
    //--------------------------------
    real e0,e1,e2,e3,sum; //chỉ là để hiển thị giá trị trong quá trình tính toán, có thể xóa

    //--------------------------------
    // ROM
    // thay đổi cho module weight_rom có 2 output vaf 2 input
    //--------------------------------
    reg [7:0] rom_addr_1;
    reg [7:0] rom_addr_2;
    wire signed [15:0] rom_data_1; // dùng để truy cập đến giá trị của mean và weight
    wire signed [15:0] rom_data_2; // dùng để truy cập đến giá tị của inv_scale và bias
    weight_rom u_rom(
        //clock
        .clk(clk),
        //address
        .first_addr(rom_addr_1),
        .second_addr(rom_addr_2),
        //data
        .first_data(rom_data_1),
        .second_data(rom_data_2)
    );

    //--------------------------------
    // MAIN
    //--------------------------------
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            state <= IDLE;
            done <= 0;
            result <= 0;

            cnt <= 0;
            rom_addr_1 <= 0;
            rom_addr_2 <= 0;

            for(i=0;i<12;i=i+1)
            begin
                x[i] <= 0;
                x_norm[i] <= 0;
            end

            for(i=0;i<8;i=i+1)
                h[i] <= 0;

            for(i=0;i<4;i=i+1)
                y[i] <= 0;
        end
        else
        begin
            case(state)

            //--------------------------------
            //IDLE
            //--------------------------------
            IDLE:
            begin
                done <= 0;

                if(start)
                begin
                    cnt <= 0;
                    state <= LOAD;
                end
            end

            //--------------------------------
            //LOAD
            //--------------------------------
            LOAD:
            begin
                if(valid)
                begin
                    x[cnt] <= feature_in;

                    if(cnt == 11)
                    begin
                        cnt <= 0;
                        rom_addr_1 <= 0;
                        rom_addr_2 <= 12;
                        state <= NORMALIZE;
                    end
                    else
                        cnt <= cnt + 1;
                end
            end

            //--------------------------------
            //NORMALIZE
            //--------------------------------
            NORMALIZE:
            begin
                x_norm[cnt] <= ((x[cnt] - rom_data_1) * rom_data_2) >>> 12;

                $display("x=%0d mean=%0d scale=%0d mul=%0d out=%0d",
                x[cnt],
                rom_data_1,
                rom_data_2,
                ((x[cnt] - rom_data_1) * rom_data_2),
                ((x[cnt] - rom_data_1) * rom_data_2)>>>12);

                if(cnt == 11) begin
                    cnt <= 0;
                    rom_addr_1 <= 24;
                    rom_addr_2 <= 120;

                    state <= FC1;
                end
                else
                begin
                    cnt <= cnt + 1;
                    rom_addr_1 <= rom_addr_1 + 1;
                    rom_addr_2 <= rom_addr_2 + 1;
                end
            end

            //--------------------------------
            //FC1
            //--------------------------------
            FC1:
            begin
                h[cnt/12] <= h[cnt/12] + ((x_norm[cnt%12]*rom_data_1)>>>12);

                if(cnt == 95)begin
                    $display("\n---- FC1 AFTER BIAS ----");
                    cnt <= 0;
                    rom_addr_2 <= 120;
                    state <= FC1_BIAS;
                end 
                else
                begin
                    cnt <= cnt + 1;
                    rom_addr_1 <= rom_addr_1 + 1;
                end
            end

            //--------------------------------
            //FC1_BIAS
            //--------------------------------
            FC1_BIAS:
            begin
                h[cnt] <= h[cnt] + rom_data_2;
                $display(
                    "h[%0d] = %0d",
                    cnt,
                    h[cnt] + rom_data_2
                );
                if(cnt == 7)begin
                    $display("\n---- AFTER RELU ----");

                    cnt <= 0;
                    rom_addr_1 <= 128;
                    state <= RELU;
                end
                else begin
                    cnt <= cnt + 1;
                    rom_addr_2 <=  rom_addr_2 + 1;
                end  
            end

            //--------------------------------
            //RELU
            //--------------------------------
            RELU:
            begin
                if(h[cnt] < 0)begin
                    h[cnt] <= 0;
                end
                $display("h[%0d] = %0d",
                cnt, 
                (h[cnt] < 0) ? 0 : h[cnt]
                );
                if(cnt ==7)begin
                    cnt <= 0;
                    state <= FC2;
                end
                else begin
                    cnt <= cnt + 1;
                end
            end

            //--------------------------------
            //FC2
            //--------------------------------
            FC2:
            begin
                y[cnt/8] <= y[cnt/8] + ((h[cnt%8]*rom_data_1)>>>12);

                if(cnt == 31)
                    cnt <= 0;
                    rom_addr_2 <= 160;
                    state <= FC2_BIAS;
                else
                begin
                    fc2_cnt <= fc2_cnt + 1;
                    rom_addr_1 <= rom_addr_1 + 1;
                end
            end

            //--------------------------------
            //FC2_BIAS
            //--------------------------------
            FC2_BIAS:
            begin
                $display("\n---- FC2 AFTER BIAS ----");

                for(i=0;i<4;i=i+1) begin
                    tmp_y = y[i] + u_rom.mem[160+i];
                    y[i] <= tmp_y;
                    $display("y[%0d] = %0d", i, tmp_y);
                end
                                    
                state <= ARGMAX;
            end

            //--------------------------------
            //ARGMAX
            //--------------------------------
            ARGMAX:
            begin
                e0 = $pow(2.71828, y[0]/4096.0);
                e1 = $pow(2.71828, y[1]/4096.0);
                e2 = $pow(2.71828, y[2]/4096.0);
                e3 = $pow(2.71828, y[3]/4096.0);

                sum = e0+e1+e2+e3;

                $display("\n---- SOFTMAX ----");
                $display("class0 = %.4f %%", e0*100/sum);
                $display("class1 = %.4f %%", e1*100/sum);
                $display("class2 = %.4f %%", e2*100/sum);
                $display("class3 = %.4f %%", e3*100/sum);
                $display("================================");
                if(y[0]>=y[1] && y[0]>=y[2] && y[0]>=y[3])
                begin
                    result <= 0;
                    $display("FINAL CLASS = 0");
                end
                else if(y[1]>=y[2] && y[1]>=y[3])
                begin
                    result <= 1;
                    $display("FINAL LABEL = 1");
                end
                else if(y[2]>=y[3])
                begin
                    result <= 2;
                    $display("FINAL LABEL = 2");
                end
                else
                begin
                    result <= 3;
                    $display("FINAL LABEL = 3");
                end
                $display("================================");
                state <= DONE_S;
            end

            //--------------------------------
            //DONE
            //--------------------------------
            DONE_S:
            begin
                done <= 1;

                if(!start)
                    state <= IDLE;
            end

            endcase
        end
    end

endmodule