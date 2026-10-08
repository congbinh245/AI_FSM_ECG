//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.11.03 Education
//Part Number: GW5A-LV25UG324C2/I1
//Device: GW5A-25
//Device Version: A
//Created Time: Sat Jul 18 01:33:12 2026

module Gowin_DPB (douta, doutb, clka, ocea, cea, reseta, wrea, clkb, oceb, ceb, resetb, wreb, ada, dina, adb, dinb);

output [15:0] douta;
output [15:0] doutb;
input clka;
input ocea;
input cea;
input reseta;
input wrea;
input clkb;
input oceb;
input ceb;
input resetb;
input wreb;
input [7:0] ada;
input [15:0] dina;
input [7:0] adb;
input [15:0] dinb;

wire gw_vcc;
wire gw_gnd;

assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;

DPB dpb_inst_0 (
    .DOA(douta[15:0]),
    .DOB(doutb[15:0]),
    .CLKA(clka),
    .OCEA(ocea),
    .CEA(cea),
    .RESETA(reseta),
    .WREA(wrea),
    .CLKB(clkb),
    .OCEB(oceb),
    .CEB(ceb),
    .RESETB(resetb),
    .WREB(wreb),
    .BLKSELA({gw_gnd,gw_gnd,gw_gnd}),
    .BLKSELB({gw_gnd,gw_gnd,gw_gnd}),
    .ADA({gw_gnd,gw_gnd,ada[7:0],gw_gnd,gw_gnd,gw_vcc,gw_vcc}),
    .DIA(dina[15:0]),
    .ADB({gw_gnd,gw_gnd,adb[7:0],gw_gnd,gw_gnd,gw_vcc,gw_vcc}),
    .DIB(dinb[15:0])
);

defparam dpb_inst_0.READ_MODE0 = 1'b0;
defparam dpb_inst_0.READ_MODE1 = 1'b0;
defparam dpb_inst_0.WRITE_MODE0 = 2'b00;
defparam dpb_inst_0.WRITE_MODE1 = 2'b00;
defparam dpb_inst_0.BIT_WIDTH_0 = 16;
defparam dpb_inst_0.BIT_WIDTH_1 = 16;
defparam dpb_inst_0.BLK_SEL_0 = 3'b000;
defparam dpb_inst_0.BLK_SEL_1 = 3'b000;
defparam dpb_inst_0.RESET_MODE = "SYNC";
defparam dpb_inst_0.INIT_RAM_00 = 256'h7FFF1E2A64663D4E000110BB0C910C9214220E813563241C004D17AF020D0814;
defparam dpb_inst_0.INIT_RAM_01 = 256'hE47A015606871584FB24078FFB98F40949B2212F476C473619B840B30C57125C;
defparam dpb_inst_0.INIT_RAM_02 = 256'hFBE1F741F6F4F23113610171F657DF2B030C08CC079CF8A0EAEC086AED64E06E;
defparam dpb_inst_0.INIT_RAM_03 = 256'h03D0FAA3C2D200D227951883FE6A1A3A15D4FF01FCBFF28E0231F3A8FFEC0552;
defparam dpb_inst_0.INIT_RAM_04 = 256'h103700EB0195CE0D0CD002CFF8731BD0082EF296FBE9FFDA084B0296FBFA1509;
defparam dpb_inst_0.INIT_RAM_05 = 256'hDEBFE4AE0D46F8DD103DFE5C00FCF0DEFFEEF894015C0D59097AECF401E90682;
defparam dpb_inst_0.INIT_RAM_06 = 256'h0031027D0126F7CE001E0A730BDE082BF74501FA0522ECA513D9FFC6F16A1CB7;
defparam dpb_inst_0.INIT_RAM_07 = 256'h420512E715071267F2521A550A3036E917DE0B66202C2BE6011DFFF8FBD6FF53;
defparam dpb_inst_0.INIT_RAM_08 = 256'hA1600185FA27FC20F597F9A9094B0498F817E84EFFD51FED1E8A0170E925FA10;
defparam dpb_inst_0.INIT_RAM_09 = 256'h01DB1EF719A6D697DA8E24EE0DAC153E1D3AF4AADE5216CD14D9E1C3E051C01C;
defparam dpb_inst_0.INIT_RAM_0A = 256'h0000000000000000000000000000000000000000000000008D0CE98A312C6857;

endmodule //Gowin_DPB
