`timescale 1ns / 1ps
`default_nettype none

// Initial hardware bring-up: eight vertical bars and a white screen border.
// Replace the color logic with display.v when the game renderer is ready.
module veribeat (
    input  wire       clk,
    input  wire       btnC,
    output wire       Hsync,
    output wire       Vsync,
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue
);
    wire reset;
    wire pixel_tick;
    wire [9:0] x;
    wire [9:0] y;
    wire video_on;
    wire frame_tick;
    reg [11:0] color;

    clock clocks (
        .clk(clk), .reset(btnC),
        .reset_sync(reset), .pixel_tick(pixel_tick)
    );

    always @* begin
        if      (x < 10'd80)  color = 12'hFFF; // White
        else if (x < 10'd160) color = 12'hFF0; // Yellow
        else if (x < 10'd240) color = 12'h0FF; // Cyan
        else if (x < 10'd320) color = 12'h0F0; // Green
        else if (x < 10'd400) color = 12'hF0F; // Magenta
        else if (x < 10'd480) color = 12'hF00; // Red
        else if (x < 10'd560) color = 12'h00F; // Blue
        else                 color = 12'h000; // Black

        if ((x == 10'd0) || (x == 10'd639) ||
            (y == 10'd0) || (y == 10'd479))
            color = 12'hFFF;
    end

    vga video (
        .clk(clk), .reset(reset), .pixel_tick(pixel_tick),
        .red_in(color[11:8]), .green_in(color[7:4]), .blue_in(color[3:0]),
        .x(x), .y(y), .video_on(video_on), .frame_tick(frame_tick),
        .hsync(Hsync), .vsync(Vsync),
        .red(vgaRed), .green(vgaGreen), .blue(vgaBlue)
    );
endmodule

`default_nettype wire
