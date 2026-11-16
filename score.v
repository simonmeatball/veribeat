`timescale 1ns / 1ps
`default_nettype none

module score (
    input  wire       clk,
    input  wire       reset,
    input  wire       frame_tick,
    input  wire [3:0] hits,
    output reg  [3:0] points
);
    // The demo chart contains eight notes. A chord awards one point per lane.
    wire [2:0] hit_count = {2'b0, hits[0]} + {2'b0, hits[1]} +
                           {2'b0, hits[2]} + {2'b0, hits[3]};
    always @(posedge clk) begin
        if (reset)
            points <= 0;
        else if (frame_tick)
            points <= points + {1'b0, hit_count};
    end
endmodule

`default_nettype wire
