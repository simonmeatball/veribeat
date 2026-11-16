`timescale 1ns / 1ps
`default_nettype none

// Basys 3 VGA game, with the original diagnostic available at elaboration.
module veribeat #(
    parameter integer START_X = 1,
    parameter integer START_Y = 1,
    parameter DIAGNOSTIC = 0,
    parameter integer KEYPAD_COL_CYCLES = 100_000
) (
    input  wire       clk,
    input  wire       btnC,
    output wire       Hsync,
    output wire       Vsync,
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    input  wire [3:0] rows,
    output wire [3:0] cols
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

    wire [11:0] video_color;
    generate
        if (DIAGNOSTIC) begin : diagnostic
            assign video_color = color;
            assign cols = 4'bzzzz;
        end else begin : game
            localparam [15:0] LANE_KEYS = 16'hDEF0;
            wire [3:0] lane_press;
            wire [15:0] lanes;
            wire [79:0] targets;
            wire [7:0] visible;
            wire [71:0] tile_bottoms;
            wire [15:0] pulse_ages;
            wire [3:0] pulse_hit;
            wire [3:0] hits;
            wire [3:0] points;

            keypad #(
                .COL_CYCLES(KEYPAD_COL_CYCLES),
                .LANE0_KEY(LANE_KEYS[3:0]), .LANE1_KEY(LANE_KEYS[7:4]),
                .LANE2_KEY(LANE_KEYS[11:8]), .LANE3_KEY(LANE_KEYS[15:12])
            ) numpad (
                .clk(clk), .reset(reset), .rows(rows), .cols(cols),
                .keys(), .pressed(), .released(), .lane_press(lane_press)
            );
            notes chart (.lanes(lanes), .targets(targets));
            control gameplay (
                .clk(clk), .reset(reset), .frame_tick(frame_tick),
                .lane_press(lane_press), .lanes(lanes), .targets(targets),
                .visible(visible), .tile_bottoms(tile_bottoms),
                .pulse_ages(pulse_ages), .pulse_hit(pulse_hit), .hits(hits)
            );
            score tally (
                .clk(clk), .reset(reset), .frame_tick(frame_tick),
                .hits(hits), .points(points)
            );
            display #(.LANE_KEYS(LANE_KEYS)) renderer (
                .x(x), .y(y), .lanes(lanes), .visible(visible),
                .tile_bottoms(tile_bottoms), .pulse_ages(pulse_ages),
                .pulse_hit(pulse_hit), .points(points), .color(video_color)
            );
        end
    endgenerate

    vga video (
        .clk(clk), .reset(reset), .pixel_tick(pixel_tick),
        .red_in(video_color[11:8]), .green_in(video_color[7:4]), .blue_in(video_color[3:0]),
        .x(x), .y(y), .video_on(video_on), .frame_tick(frame_tick),
        .hsync(Hsync), .vsync(Vsync),
        .red(vgaRed), .green(vgaGreen), .blue(vgaBlue)
    );
endmodule

`default_nettype wire
