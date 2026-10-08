`timescale 1ns/1ps

module hr_top(
    input clk,
    input rst_n,
    input start,

    input  wire signed  [15:0] f_rms,          
    input  wire signed  [15:0] f_var,          
    input  wire signed  [15:0] f_peak,         
    input  wire signed  [15:0] f_zc,           // Số đếm nguyên không dấu 16-bit
    input  wire signed  [15:0] f_ptp,          
    input  wire signed  [15:0] f_crest,        
    input  wire signed  [15:0] f_half_ratio,   
    input  wire signed  [15:0] f_max,          
    input  wire signed  [15:0] f_rr,           // Số chu kỳ mẫu nguyên 16-bit
    input  wire signed  [15:0] f_rr_prev,      // Số chu kỳ mẫu nguyên 16-bit
    input  wire signed  [15:0] f_rr_ratio,     
    input  wire signed  [15:0] f_rr_diff,
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
    reg signed [31:0] tmp_variable;
    reg signed [15:0] features      [0:11];
    reg signed [31:0] features_norm [0:11];
    reg signed [31:0] feature_after_fc1 [0:7];
    reg signed [31:0] feature_after_fc2 [0:3];
    //--------------------------------
    // counters
    //--------------------------------
    reg [6:0] cnt;
    integer i;

    //--------------------------------
    // Gowin True Dual Port BSRAM IP Core
    // Thay thế hoàn toàn cho module tổ hợp cũ
    //--------------------------------
    reg [7:0] rom_addr_1;
    reg [7:0] rom_addr_2;
    wire signed [15:0] rom_data_1; 
    wire signed [15:0] rom_data_2; 

    Gowin_DPB u_rom (
        .douta(rom_data_1),
        .doutb(rom_data_2),
        .clka(clk),
        .clkb(clk),
        .ada(rom_addr_1),
        .adb(rom_addr_2),
        .cea(1'b1),
        .ceb(1'b1),
        .ocea(1'b1),
        .oceb(1'b1),
        .wrea(1'b0), // Khóa ghi cổng A, cấu hình như ROM
        .wreb(1'b0), // Khóa ghi cổng B, cấu hình như ROM
        .reseta(!rst_n),
        .resetb(!rst_n),
        .dina(16'd0),
        .dinb(16'd0)
    );

    //--------------------------------
    // MAIN FSM LOGIC
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
                tmp_variable <= 0;

                for(i=0;i<12;i=i+1)
                begin
                    features[i] <= 0;
                    features_norm[i] <= 0;
                end

                for(i=0;i<8;i=i+1)
                    feature_after_fc1[i] <= 0;

                for(i=0;i<4;i=i+1)
                    feature_after_fc2[i] <= 0;
            end
        else
        begin
            case(state)

            //--------------------------------
            // IDLE
            //--------------------------------
            IDLE:
            begin
                done <= 0;
                if(start)
                begin
                    cnt <= 0;
                    for(i=0;i<12;i=i+1)
                    begin
                        features[i] <= 0;
                        features_norm[i] <= 0;
                    end

                    for(i=0;i<8;i=i+1)
                        feature_after_fc1[i] <= 0;

                    for(i=0;i<4;i=i+1)
                        feature_after_fc2[i] <= 0;
                        tmp_variable <= 0;
                    state <= LOAD;
                end
            end

            //--------------------------------
            // LOAD
            //--------------------------------
            LOAD:
            begin
                if(valid)
                begin
                    features[0]  <= f_rms;
                    features[1]  <= f_var;
                    features[2]  <= f_peak;
                    features[3]  <= f_zc;
                    features[4]  <= f_ptp;
                    features[5]  <= f_crest;
                    features[6]  <= f_half_ratio;
                    features[7]  <= f_max;
                    features[8]  <= f_rr;
                    features[9]  <= f_rr_prev;
                    features[10] <= f_rr_ratio;
                    features[11] <= f_rr_diff;
                    
                    // Chuẩn bị sẵn địa chỉ cho NORMALIZE ở chu kỳ kế tiếp
                    rom_addr_1 <= 0;  // Trỏ tới mean[0]
                    rom_addr_2 <= 12; // Trỏ tới inv_scale[0]
                    cnt <= 0;
                    state <= NORMALIZE;
                end
            end

            //--------------------------------
            // NORMALIZE
            // Do RAM lệch 1 chu kỳ, tại cnt=0 dữ liệu chưa ra.
            // Bắt đầu tính toán thực tế và lưu từ chu kỳ cnt=1 (cho feature 0).
            //--------------------------------
            NORMALIZE:
            begin
                if(cnt > 0 ) begin
                    tmp_variable = (features[cnt-1] - rom_data_1) * rom_data_2;
                    features_norm[cnt-1] <= tmp_variable >>> 12;
                    //$display("x=%0d mean=%0d scale=%0d mul=%0d out=%0d",features[cnt-1],rom_data_1,rom_data_2,tmp_variable,tmp_variable>>>12);
                end
                   
                if(cnt == 12) begin
                    cnt <= 0;
                    tmp_variable <= 0;
                    // Chuẩn bị địa chỉ cho lớp FC1 ở trạng thái tiếp theo
                    rom_addr_1 <= 24;  // Trỏ tới weight của FC1
                    rom_addr_2 <= 120; // Trỏ tới bias của FC1
                    state <= FC1;
                end
                else begin
                    cnt <= cnt + 1;
                    rom_addr_1 <= rom_addr_1 + 1;
                    rom_addr_2 <= rom_addr_2 + 1;
                end
            end

            //--------------------------------
            // FC1 (Fully Connected 1)
            // Tính toán Mac tích lũy. Dữ liệu RAM ra từ chu kỳ cnt=1.
            //--------------------------------
            FC1:
            begin
                if(cnt > 0) begin
                    tmp_variable = (features_norm[(cnt-1)%12] * rom_data_1);
                    feature_after_fc1[(cnt-1)/12] <= feature_after_fc1[(cnt-1)/12] + (tmp_variable >>> 12);
                end

                if(cnt == 96) begin
                    cnt <= 0;
                    tmp_variable <= 0;
                    rom_addr_2 <= 120; // Đặt lại địa chỉ trỏ tới Base Bias FC1
                    state <= FC1_BIAS;
                end 
                else begin
                    cnt <= cnt + 1;
                    rom_addr_1 <= rom_addr_1 + 1;
                end
            end

            //--------------------------------
            // FC1_BIAS
            //--------------------------------
            FC1_BIAS:
            begin
                if(cnt > 0) begin
                    feature_after_fc1[cnt-1] <= feature_after_fc1[cnt-1] + rom_data_2;
                end
                
                if(cnt == 8) begin
                    cnt <= 0;
                    rom_addr_1 <= 128; // Chuẩn bị địa chỉ weight cho FC2
                    state <= RELU;
                end
                else begin
                    cnt <= cnt + 1;
                    rom_addr_2 <= rom_addr_2 + 1;
                end  
            end

            //--------------------------------
            // RELU
            //--------------------------------
            RELU:
            begin
                if(feature_after_fc1[cnt] < 0) begin
                    feature_after_fc1[cnt] <= 0;
                end
                
                if(cnt == 7) begin
                    cnt <= 0;
                    state <= FC2;
                end
                else begin
                    cnt <= cnt + 1;
                end
            end

            //--------------------------------
            // FC2 (Fully Connected 2)
            //--------------------------------
            FC2:
            begin
                if(cnt > 0) begin
                    tmp_variable = (feature_after_fc1[(cnt-1)%8] * rom_data_1);
                    feature_after_fc2[(cnt-1)/8] <= feature_after_fc2[(cnt-1)/8] + (tmp_variable >>> 12);
                end
                
                if(cnt == 32) begin
                    cnt <= 0;
                    tmp_variable <= 0;
                    rom_addr_2 <= 160; // Trỏ tới bias của FC2
                    state <= FC2_BIAS;
                end
                else begin
                    cnt <= cnt + 1;
                    rom_addr_1 <= rom_addr_1 + 1;
                end
            end

            //--------------------------------
            // FC2_BIAS
            //--------------------------------
            FC2_BIAS:
            begin
                if(cnt > 0) begin
                    feature_after_fc2[cnt-1] <= feature_after_fc2[cnt-1] + rom_data_2;
                end

                if(cnt == 4) begin
                    state <= ARGMAX;
                end
                else begin
                    cnt <= cnt + 1;
                    rom_addr_2 <= rom_addr_2 + 1;
                end                
            end

            //--------------------------------
            // ARGMAX
            //--------------------------------
            ARGMAX:
            begin
                if(feature_after_fc2[0] >= feature_after_fc2[1] && feature_after_fc2[0] >= feature_after_fc2[2] && feature_after_fc2[0] >= feature_after_fc2[3])
                begin
                    result <= 2'd0;
                    //$display("FINAL CLASS = 0");
                end
                else if(feature_after_fc2[1] >= feature_after_fc2[2] && feature_after_fc2[1] >= feature_after_fc2[3])
                begin
                    result <= 2'd1;
                    //$display("FINAL LABEL = 1");
                end
                else if(feature_after_fc2[2] >= feature_after_fc2[3])
                begin
                    result <= 2'd2;
                    //$display("FINAL LABEL = 2");
                end
                else
                begin
                    result <= 2'd3;
                    //$display("FINAL LABEL = 3");
                end
                //$display("================================");
                state <= DONE_S;
            end

            //--------------------------------
            // DONE
            //--------------------------------
            DONE_S:
            begin
                done <= 1;
                if(!start)
                    state <= IDLE;
            end

            default: 
            begin
                state <= IDLE;
            end

            endcase
        end
    end
endmodule