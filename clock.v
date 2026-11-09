`timescale 1ns / 1ps
`default_nettype none

// Keep all logic on the Basys 3's 100 MHz clock. pixel_tick is a
// one-cycle clock ENABLE at 25 MHz; do not use it in a posedge block.
module clock (
    input  wire clk,
    input  wire reset,       // Active-high external reset (center button).
    output wire reset_sync,
    output wire pixel_tick
);
    // Async assertion, synchronous release. Vivado implements the initial
    // value at configuration, so the display also starts without a button press.
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe = 2'b11;
    reg [1:0] pixel_div = 2'b00;

    always @(posedge clk or posedge reset) begin
        if (reset)
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0], 1'b0};
    end

    assign reset_sync = reset_pipe[1];

    always @(posedge clk) begin
        if (reset_sync)
            pixel_div <= 2'b00;
        else
            pixel_div <= pixel_div + 2'b01;
    end

    assign pixel_tick = !reset_sync && (pixel_div == 2'b11);
endmodule

`default_nettype wire
