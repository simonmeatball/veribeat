`timescale 1ns / 1ps
`default_nettype none

// Convert audio time to a 512-pixel fill width once per video frame.
// Nine fractional division steps share one subtractor, keeping division
// out of the pixel path. The result settles during the frame's left margin.
module song_progress #(
    parameter integer PRE_ROLL_MS = 1400
) (
    input wire clk, reset, frame_tick,
    input wire [31:0] elapsed_ms, duration_ms,
    output reg [9:0] pixels
);
    localparam IDLE=0, CHECK=1, DIVIDE=2;
    reg [1:0] state;
    reg [31:0] remainder, duration;
    reg [8:0] fraction;
    reg [3:0] steps;
    // Extra high bit captures unsigned borrow after doubling the remainder.
    wire [33:0] trial = {1'b0,remainder,1'b0} - {2'b0,duration};
    wire [8:0] next_fraction = {fraction[7:0],~trial[33]};

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            pixels <= 0;
            remainder <= 0;
            duration <= 0;
            fraction <= 0;
            steps <= 0;
        end else begin
            case (state)
                IDLE: if (frame_tick) begin
                    remainder <= elapsed_ms > PRE_ROLL_MS ? elapsed_ms-PRE_ROLL_MS : 0;
                    duration <= duration_ms;
                    state <= CHECK;
                end
                CHECK: begin
                    if (duration == 0 || remainder == 0) begin
                        pixels <= 0;
                        state <= IDLE;
                    end else if (remainder >= duration) begin
                        pixels <= 10'd512;
                        state <= IDLE;
                    end else begin
                        fraction <= 0;
                        steps <= 9;
                        state <= DIVIDE;
                    end
                end
                DIVIDE: begin
                    remainder <= trial[33] ? {remainder[30:0],1'b0} : trial[31:0];
                    fraction <= next_fraction;
                    steps <= steps-1'b1;
                    if (steps == 1) begin
                        pixels <= {1'b0,next_fraction};
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
