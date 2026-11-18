`timescale 1ns / 1ps
`default_nettype none
module score (
    input wire clk,
    input wire reset,
    input wire [3:0] hits,
    output reg [10:0] points,
    output reg [15:0] digits
);
    // Drain a chord one point per cycle, avoiding four decimal increments
    // in one combinational path. The controller emits at most one chord/frame.
    reg [10:0] pending;
    wire [2:0] incoming = {2'b0,hits[0]} + {2'b0,hits[1]} +
                          {2'b0,hits[2]} + {2'b0,hits[3]};
    always @(posedge clk) begin
        if (reset) begin
            points <= 0;
            digits <= 0;
            pending <= 0;
        end else begin
            if (pending != 0) begin
                pending <= pending + incoming - 1'b1;
                points <= points + 1'b1;
                if (digits[3:0] != 9) digits[3:0] <= digits[3:0] + 1'b1;
                else begin
                    digits[3:0] <= 0;
                    if (digits[7:4] != 9) digits[7:4] <= digits[7:4] + 1'b1;
                    else begin
                        digits[7:4] <= 0;
                        if (digits[11:8] != 9) digits[11:8] <= digits[11:8] + 1'b1;
                        else begin
                            digits[11:8] <= 0;
                            digits[15:12] <= digits[15:12] + 1'b1;
                        end
                    end
                end
            end else pending <= {8'b0,incoming};
        end
    end
endmodule
`default_nettype wire
