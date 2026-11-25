`timescale 1ns / 1ps
`default_nettype none

// All logic stays on 100 MHz. The pixel enable is sampled once every four
// cycles, with the same phase after reset as the original VGA divider.
module clock (
    input wire clk,
    input wire reset,
    output wire reset_sync,
    output wire pixel_tick
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe;
    reg [1:0] pixel_phase;

    initial begin
        reset_pipe = 2'b11;
        pixel_phase = 0;
    end

    // Synchronize both reset edges. The output register has no asynchronous
    // set/reset, so reset-dependent block-RAM addresses and controls change
    // on clock edges and are covered by normal static timing analysis.
    always @(posedge clk) begin
        reset_pipe <= {reset_pipe[0],reset};
    end
    assign reset_sync = reset_pipe[1];

    always @(posedge clk) begin
        if (reset_sync) pixel_phase <= 0;
        else pixel_phase <= pixel_phase + 1'b1;
    end
    assign pixel_tick = !reset_sync && pixel_phase == 2'd3;
endmodule
`default_nettype wire
