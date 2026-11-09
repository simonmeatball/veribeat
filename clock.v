`timescale 1ns / 1ps
`default_nettype none

// Clock hub for a 100 MHz Basys 3 oscillator. Named CLK outputs are real
// square-wave clocks; pixel_tick is a one-cycle enable in the 100 MHz domain.
// The current VGA/game logic uses clk + enables to avoid clock-domain crossings.
module clock (
    input  wire clk,
    input  wire reset,
    output wire reset_sync,
    output wire CLK_100MHz,
    output wire CLK_50MHz,
    output wire CLK_25MHz,
    output wire pixel_tick
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe = 2'b11;
    wire unused_tick_50;

    always @(posedge clk or posedge reset) begin
        if (reset)
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0], 1'b0};
    end
    assign reset_sync = reset_pipe[1];
    assign CLK_100MHz = clk;

    clock_divider #(.DIVIDE(2)) clk50 (
        .clk(clk), .reset(reset_sync),
        .clk_out(CLK_50MHz), .tick(unused_tick_50)
    );
    clock_divider #(.DIVIDE(4)) clk25 (
        .clk(clk), .reset(reset_sync),
        .clk_out(CLK_25MHz), .tick(pixel_tick)
    );
    // Add another even-integer divider here and expose a matching named port.
    // Non-integer ratios (e.g. 25.2 MHz) require an MMCM/Clocking Wizard.
endmodule

// Reusable even-integer divider: output frequency = input frequency / DIVIDE.
// DIVIDE must be even and >= 2. Both half-periods have exactly DIVIDE/2 cycles.
module clock_divider #(
    parameter integer DIVIDE = 4
) (
    input  wire clk,
    input  wire reset,
    output wire clk_out,
    output wire tick
);
    function integer bits_for;
        input integer value;
        integer remaining;
        begin
            remaining = value - 1;
            bits_for = 0;
            while (remaining > 0) begin
                bits_for = bits_for + 1;
                remaining = remaining >> 1;
            end
            if (bits_for == 0) bits_for = 1;
        end
    endfunction

    localparam integer WIDTH = bits_for(DIVIDE);
    reg [WIDTH-1:0] count = 0;
    reg square = 1'b0;

    always @(posedge clk) begin
        if (reset) begin
            count <= 0;
            square <= 1'b0;
        end else if (count == DIVIDE - 1) begin
            count <= 0;
            square <= 1'b0;
        end else begin
            count <= count + 1'b1;
            if (count == DIVIDE / 2 - 1)
                square <= 1'b1;
        end
    end
    assign tick = !reset && (count == DIVIDE - 1);

    // Vivado uses a dedicated global clock buffer for real clock consumers.
    // Generic simulation uses the same divider waveform without buffer delay.
`ifdef SYNTHESIS
    BUFG clock_buffer (.I(square), .O(clk_out));
`else
    assign clk_out = square;
    initial begin
        if (DIVIDE < 2 || DIVIDE % 2 != 0) begin
            $display("ERROR: clock_divider DIVIDE must be even and >= 2");
            $stop;
            $finish;
        end
    end
`endif
endmodule

`default_nettype wire
