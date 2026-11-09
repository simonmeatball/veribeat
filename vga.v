`timescale 1ns / 1ps
`default_nettype none

// 640x480, approximately 60 Hz, negative-polarity horizontal/vertical sync.
// With a 25 MHz pixel enable: 31.25 kHz lines and 59.524 Hz frames.
// RGB inputs must be combinational functions of the CURRENT x/y coordinates.
module vga (
    input  wire       clk,
    input  wire       reset,       // Synchronized, active high.
    input  wire       pixel_tick,
    input  wire [3:0] red_in,
    input  wire [3:0] green_in,
    input  wire [3:0] blue_in,
    output wire [9:0] x,
    output wire [9:0] y,
    output wire       video_on,
    output wire       frame_tick,  // One clk cycle at the end of each frame.
    output wire       hsync,
    output wire       vsync,
    output wire [3:0] red,
    output wire [3:0] green,
    output wire [3:0] blue
);
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (pixel_tick) begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Coordinates include blanking: x=0..799, y=0..524.
    // Only render visible pixels when video_on is high.
    assign x = h_count;
    assign y = v_count;
    assign video_on = !reset && (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign frame_tick = !reset && pixel_tick &&
                        (h_count == H_TOTAL - 1) && (v_count == V_TOTAL - 1);
    assign hsync = reset || !((h_count >= H_VISIBLE + H_FRONT) &&
                             (h_count < H_VISIBLE + H_FRONT + H_SYNC));
    assign vsync = reset || !((v_count >= V_VISIBLE + V_FRONT) &&
                             (v_count < V_VISIBLE + V_FRONT + V_SYNC));
    assign red   = video_on ? red_in   : 4'h0;
    assign green = video_on ? green_in : 4'h0;
    assign blue  = video_on ? blue_in  : 4'h0;
endmodule

`default_nettype wire
