`timescale 1ns / 1ps
`default_nettype none

// VGA diagnostic: static bars/grid, fixed border, and a bouncing white square.
// Replace the color logic with display.v when the game renderer is ready.
module veribeat #(
    parameter integer START_X = 1,
    parameter integer START_Y = 1
) (
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
    wire CLK_100MHz;
    wire CLK_50MHz;
    wire CLK_25MHz;
    reg [9:0] box_x;
    reg [9:0] box_y;
    reg move_left;
    reg move_up;

    // 64x64 square: 2 pixels horizontally and 1 vertically per frame.
    // Update only at the frame boundary, keeping every visible frame coherent.
    always @(posedge clk) begin
        if (reset) begin
            box_x <= START_X;
            box_y <= START_Y;
            move_left <= 1'b0;
            move_up <= 1'b0;
        end else if (frame_tick) begin
            if (!move_left) begin
                if (box_x >= 10'd573) begin
                    box_x <= 10'd575;
                    move_left <= 1'b1;
                end else box_x <= box_x + 10'd2;
            end else begin
                if (box_x <= 10'd3) begin
                    box_x <= 10'd1;
                    move_left <= 1'b0;
                end else box_x <= box_x - 10'd2;
            end
            if (!move_up) begin
                if (box_y >= 10'd414) begin
                    box_y <= 10'd415;
                    move_up <= 1'b1;
                end else box_y <= box_y + 10'd1;
            end else begin
                if (box_y <= 10'd2) begin
                    box_y <= 10'd1;
                    move_up <= 1'b0;
                end else box_y <= box_y - 10'd1;
            end
        end
    end

    clock clocks (
        .clk(clk), .reset(btnC),
        .reset_sync(reset), .pixel_tick(pixel_tick),
        .CLK_100MHz(CLK_100MHz), .CLK_50MHz(CLK_50MHz), .CLK_25MHz(CLK_25MHz)
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

        // Fixed dark grid gives a stationary reference for image jitter.
        if ((x[5:0] == 0) || (y[5:0] == 0)) color = 12'h444;
        if ((x >= box_x) && (x < box_x + 10'd64) &&
            (y >= box_y) && (y < box_y + 10'd64)) color = 12'hFFF;

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
