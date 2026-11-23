`timescale 1ns / 1ps
`default_nettype none

module notes #(
    parameter CHART_FILE = "charts/song_0.mem"
) (
    input wire clk,
    input wire enable,
    input wire [9:0] address,
    output reg [39:0] data
);
    (* rom_style = "block" *) reg [39:0] chart [0:1023];
    initial $readmemh(CHART_FILE, chart);
    always @(posedge clk)
        if (enable) data <= chart[address];
endmodule

`default_nettype wire
