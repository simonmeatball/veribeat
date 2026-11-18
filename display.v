`timescale 1ns / 1ps
`default_nettype none

module display #(
    parameter [15:0] LANE_KEYS = 16'hDEF0
) (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [1:0] tile_pixel,
    input  wire [15:0] pulse_ages,
    input  wire [3:0]  pulse_hit,
    input  wire [15:0] digits,
    output reg  [11:0] color
);
    localparam FIELD_LEFT = 64;
    localparam FIELD_RIGHT = 576;
    localparam FIELD_TOP = 48;
    localparam HIT_Y = 404;
    localparam PAD_TOP = 410;
    localparam PAD_BOTTOM = 456;

    // Three by five pixel font, most significant bit at the top left.
    function [14:0] digit;
        input [3:0] value;
        begin
            case (value)
                0: digit = 15'b111_101_101_101_111;
                1: digit = 15'b010_110_010_010_111;
                2: digit = 15'b111_001_111_100_111;
                3: digit = 15'b111_001_111_001_111;
                4: digit = 15'b101_101_111_001_001;
                5: digit = 15'b111_100_111_001_111;
                6: digit = 15'b111_100_111_101_111;
                7: digit = 15'b111_001_010_010_010;
                8: digit = 15'b111_101_111_101_111;
                9: digit = 15'b111_101_111_001_111;
                4'hD: digit = 15'b110_101_101_101_110;
                4'hE: digit = 15'b111_100_110_100_111;
                4'hF: digit = 15'b111_100_110_100_100;
                default: digit = 0;
            endcase
        end
    endfunction

    function glyph_pixel;
        input [14:0] glyph;
        input [4:0] dx;
        input [4:0] dy;
        reg [2:0] row;
        reg [2:0] column;
        begin
            row = dy[4:2];
            column = dx[4:2];
            glyph_pixel = 0;
            if (row < 5 && column < 3)
                glyph_pixel = glyph[14 - 3 * row - column];
        end
    endfunction

    // The four lanes are 128 pixels wide, so a single lane owns each pixel.
    wire [9:0] field_x = x - 10'd64;
    wire [1:0] pixel_lane = field_x[8:7];
    wire [6:0] lane_x = field_x[6:0];
    wire [3:0] pad_key = LANE_KEYS[4*pixel_lane +: 4];
    wire [3:0] age = pulse_ages[4*pixel_lane +: 4];
    // Keep the hit outline full white for the first three frames.
    // The miss outline uses only the red channel throughout the fade.
    wire is_hit = pulse_hit[pixel_lane];
    wire [3:0] red_level = 4'd15 - age;
    wire [3:0] white_level = age < 4'd3 ? 4'hf : 4'd15 - (age - 4'd2);
    wire [11:0] pulse_color = is_hit ? {3{white_level}} : {red_level, 8'h00};
    wire [11:0] glow_color = (pulse_color >> 1) & 12'h777;
    wire [6:0] spread = 7'd2 + {3'b0, age};
    wire [6:0] pulse_left = 7'd16 - spread;
    wire [6:0] pulse_right = 7'd111 + spread;
    wire [9:0] pulse_top = PAD_TOP - spread;
    wire [9:0] pulse_bottom = PAD_BOTTOM - 1 + spread;

    wire [1:0] digit_index = x[5:4];
    wire [3:0] score_digit = digits[4*(3-digit_index) +: 4];
    always @* begin
        color = 12'h012;
        if (x >= 64 && x < 128 && y >= 15 && y < 35 && x[3:0] < 12 &&
            glyph_pixel(digit(score_digit), {1'b0,x[3:0]}, y[4:0] - 5'd15))
            color = 12'hfff;

        if (x >= FIELD_LEFT && x < FIELD_RIGHT && y >= FIELD_TOP && y < 470) begin
            color = 12'h113;
            if (y[4:0] == 0)
                color = 12'h224;
            if (lane_x == 0 || lane_x == 127)
                color = 12'h436;

            if (tile_pixel[0] && lane_x >= 16 && lane_x < 112) begin
                color = 12'h158;
                if (tile_pixel[1] || lane_x < 18 || lane_x >= 110)
                    color = 12'h6ef;
            end

            if (y == HIT_Y)
                color = 12'hb8f;
            if (y >= PAD_TOP && y < PAD_BOTTOM && lane_x >= 16 && lane_x < 112) begin
                color = 12'h324;
                if (y < PAD_TOP + 2 || y >= PAD_BOTTOM - 2 ||
                    lane_x < 18 || lane_x >= 110)
                    color = 12'h96e;
                if (lane_x >= 58 && lane_x < 70 && y >= 423 && y < 443 &&
                    glyph_pixel(digit(pad_key), lane_x[4:0] - 5'd26, y[4:0] - 5'd7))
                    color = 12'hfff;
            end

            if (age < 12 && lane_x >= pulse_left && lane_x <= pulse_right &&
                y >= pulse_top && y <= pulse_bottom) begin
                if (lane_x == pulse_left || lane_x == pulse_right ||
                    y == pulse_top || y == pulse_bottom)
                    color = pulse_color;
                else if (lane_x == pulse_left + 1'b1 || lane_x == pulse_right - 1'b1 ||
                         y == pulse_top + 1'b1 || y == pulse_bottom - 1'b1)
                    color = glow_color;
            end
        end
    end
endmodule

`default_nettype wire
