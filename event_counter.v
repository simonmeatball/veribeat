`timescale 1ns / 1ps
`default_nettype none
module event_counter #(
    parameter integer WIDTH = 11,
    parameter integer LIMIT = 1024,
    parameter integer INPUT_BITS = 4
) (
    input wire clk,
    input wire reset,
    input wire [INPUT_BITS-1:0] hits,
    output reg [WIDTH-1:0] points,
    output reg [15:0] digits
);
    // Each set bit in hits contributes one event. points is the binary count;
    // digits is the matching four-digit BCD representation.
    // Queue simultaneous events and drain one point per cycle so decimal
    // carry propagation stays short for hits, missed notes, and misclicks.
    reg [WIDTH-1:0] pending;
    wire [15:0] events = {{(16-INPUT_BITS){1'b0}},hits};
    wire [2:0] groups [0:3];
    genvar group;
    generate for(group=0;group<4;group=group+1) begin : popcount
        assign groups[group] = {2'b0,events[group*4]} + {2'b0,events[group*4+1]} +
                               {2'b0,events[group*4+2]} + {2'b0,events[group*4+3]};
    end endgenerate
    wire [3:0] lower = {1'b0,groups[0]} + {1'b0,groups[1]};
    wire [3:0] upper = {1'b0,groups[2]} + {1'b0,groups[3]};
    wire [4:0] incoming = {1'b0,lower} + {1'b0,upper};
    always @(posedge clk) begin
        if (reset) begin
            points <= 0;
            digits <= 0;
            pending <= 0;
        end else begin
            if (points == LIMIT) pending <= 0;
            else if (pending != 0) begin
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
            end else pending <= incoming;
        end
    end
endmodule
`default_nettype wire
