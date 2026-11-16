`timescale 1ns / 1ps
`default_nettype none

// Demo chart. Each entry occupies the same slot in both packed buses.
module notes (
    output wire [15:0] lanes,
    output wire [79:0] targets
);
    assign lanes   = {2'd3, 2'd1, 2'd0, 2'd3, 2'd2, 2'd1, 2'd0, 2'd2};
    assign targets = {10'd320, 10'd280, 10'd240, 10'd200,
                      10'd160, 10'd160, 10'd120, 10'd80};
endmodule

`default_nettype wire
