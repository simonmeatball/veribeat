`timescale 1ns / 1ps
`default_nettype none

module notes #(
    parameter CHART_FILE = "charts/song_0.mem"
) (
    input wire clk,
    input wire enable,
    input wire [9:0] address,
    output wire [34:0] data
);
    (* rom_style = "block" *) reg [39:0] chart [0:1023];
    reg [39:0] stored_word;
    initial $readmemh(CHART_FILE, chart);
    always @(posedge clk)
        if (enable) stored_word <= chart[address];
    // Keep the on-disk 40-bit format. Only the valid bit, target time,
    // and lane enter gameplay; reserved bits 38:34 terminate here.
    assign data = {stored_word[39],stored_word[33:0]};
endmodule

`default_nettype wire
