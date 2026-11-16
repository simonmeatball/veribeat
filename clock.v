`timescale 1ns / 1ps
`default_nettype none

module clock (
    input  wire clk,             // Basys 3: 100 MHz
    input  wire reset,
    output wire reset_sync,
    output wire CLK_100MHz,
    output reg  CLK_50MHz,
    output reg  CLK_25MHz,
    output wire pixel_tick
);
    // 100 MHz / (2 * 2) = 25 MHz: toggle every two input cycles.
    // One bit is enough to count from 0 to 1.
    reg count_25MHz;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe;

    initial begin
        count_25MHz = 0;
        CLK_25MHz = 0;
        CLK_50MHz = 0;
        reset_pipe = 2'b11;
    end

    // Assert reset immediately; release it after two clock edges.
    always @(posedge clk or posedge reset) begin
        if (reset)
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0], 1'b0};
    end

    assign reset_sync = reset_pipe[1];
    assign CLK_100MHz = clk;

    always @(posedge clk) begin
        if (reset_sync) begin
            count_25MHz <= 0;
            CLK_25MHz <= 0;
            CLK_50MHz <= 0;
        end else begin
            // 100 MHz / (2 * 1) = 50 MHz: toggle every input cycle.
            CLK_50MHz <= ~CLK_50MHz;

            if (count_25MHz == 2 - 1) begin
                count_25MHz <= 0;
                CLK_25MHz <= ~CLK_25MHz;
            end else begin
                count_25MHz <= count_25MHz + 1'b1;
            end
        end
    end

    // High for one 100 MHz cycle just before CLK_25MHz falls.
    // The VGA uses this enable so its logic stays on the 100 MHz clock.
    assign pixel_tick = !reset_sync && CLK_25MHz && (count_25MHz == 1);

    // For another output, add a counter and toggle it every N input cycles:
    // output frequency = 100,000,000 / (2 * N).
endmodule

`default_nettype wire
