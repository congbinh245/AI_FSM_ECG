module weight_rom (
    input  wire clk,
    input  wire [7:0] first_addr,
    input  wire [7:0] second_addr,
    output reg  signed [15:0] first_data,
    output reg  signed [15:0] second_data
);

    reg signed [15:0] mem [0:163];

    initial begin
        $readmemh("weight.hex", mem);
        $display("ROM[0] = %h", mem[0]);
        $display("ROM[1] = %h", mem[1]);
        $display("ROM[12] = %h", mem[12]);
    end

    always @(posedge clk) begin
        first_data <= mem[first_addr];
        second_data <= mem[second_addr];
    end

endmodule