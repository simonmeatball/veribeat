`timescale 1ns / 1ps
`default_nettype none

// Three 100 MHz stages fit inside the four-cycle pixel interval:
// layout/coordinates -> character lookup -> glyph/color. VGA samples the
// settled result for its current x/y on the following pixel enable.
module menu_display (
    input wire clk,
    input wire reset,
    input wire [9:0] x, y,
    input wire [1:0] screen, // HOME=0, GAME=1, RESULTS=2, LOADING=3
    input wire [1:0] song,
    input wire failed,
    input wire [15:0] hit_digits, miss_digits, misclick_digits,
    input wire [23:0] score_digits,
    input wire [15:0] combo_digits, longest_digits,
    output reg hud_pixel,
    output reg [11:0] color
);
    `include "game_defs.vh"
    localparam [4:0] TEXT_TITLE = 5'd0;
    localparam [4:0] TEXT_SELECT_SONG = 5'd1;
    localparam [4:0] TEXT_SONG0_CHOICE = 5'd2;
    localparam [4:0] TEXT_SONG1_CHOICE = 5'd3;
    localparam [4:0] TEXT_SONG2_CHOICE = 5'd4;
    localparam [4:0] TEXT_SELECT_KEYS = 5'd5;
    localparam [4:0] TEXT_RESULTS = 5'd6;
    localparam [4:0] TEXT_HITS = 5'd7;
    localparam [4:0] TEXT_MISSES = 5'd8;
    localparam [4:0] TEXT_MISCLICKS = 5'd9;
    localparam [4:0] TEXT_RETURN_HOME = 5'd10;
    localparam [4:0] TEXT_LOADING = 5'd11;
    localparam [4:0] TEXT_WAIT_AUDIO = 5'd12;
    localparam [4:0] TEXT_SONG0_TITLE = 5'd13;
    localparam [4:0] TEXT_SONG1_TITLE = 5'd14;
    localparam [4:0] TEXT_SONG2_TITLE = 5'd15;
    localparam [4:0] TEXT_AUDIO_ERROR = 5'd16;
    localparam [4:0] TEXT_SCORE = 5'd17;
    localparam [4:0] TEXT_COMBO = 5'd18;
    localparam [4:0] TEXT_BEST_STREAK = 5'd19;

    localparam TEXT_HEIGHT = 20;
    localparam CELL_WIDTH = 16;
    localparam RESULTS_LABEL_X = 112;
    localparam COUNT_VALUE_X = 432;
    localparam SCORE_VALUE_X = 400;
    localparam VALUE_RIGHT_X = 496;
    localparam RESULTS_SCORE_Y = 160;
    localparam RESULTS_HITS_Y = 200;
    localparam RESULTS_MISSES_Y = 240;
    localparam RESULTS_MISCLICKS_Y = 280;
    localparam RESULTS_STREAK_Y = 320;
    localparam COLOR_BACKGROUND = 12'h012;
    localparam COLOR_PANEL = 12'h113;
    localparam COLOR_GRID = 12'h124;
    localparam COLOR_TEXT = 12'hfff;
    localparam COLOR_ACCENT = 12'h6ef;
    localparam COLOR_PURPLE = 12'hb8f;
    localparam COLOR_CARD = 12'h235;
    localparam COLOR_LINE = 12'h436;
    localparam COLOR_ERROR = 12'hf44;

    function [7:0] text_character;
        input [4:0] message;
        input [4:0] column;
        reg [255:0] line;
        begin
            case(message)
                TEXT_TITLE: line = "VERIBEAT                        ";
                TEXT_SELECT_SONG: line = "SELECT A SONG                   ";
                TEXT_SONG0_CHOICE: line = "1 YORU NI KAKERU                ";
                TEXT_SONG1_CHOICE: line = "2 APT.                          ";
                TEXT_SONG2_CHOICE: line = "3 SUNFLOWER                     ";
                TEXT_SELECT_KEYS: line = "PRESS 1 2 3 TO START            ";
                TEXT_RESULTS: line = "RESULTS                         ";
                TEXT_HITS: line = "HITS                            ";
                TEXT_MISSES: line = "MISSES                          ";
                TEXT_MISCLICKS: line = "MISCLICKS                       ";
                TEXT_RETURN_HOME: line = "PRESS ANY BUTTON                ";
                TEXT_LOADING: line = "LOADING                         ";
                TEXT_WAIT_AUDIO: line = "WAITING FOR AUDIO               ";
                TEXT_SONG0_TITLE: line = "YORU NI KAKERU                  ";
                TEXT_SONG1_TITLE: line = "APT.                            ";
                TEXT_SONG2_TITLE: line = "SUNFLOWER                       ";
                TEXT_AUDIO_ERROR: line = "AUDIO ERROR                     ";
                TEXT_SCORE: line = "SCORE                           ";
                TEXT_COMBO: line = "COMBO                           ";
                TEXT_BEST_STREAK: line = "BEST STREAK                     ";
                default: line = {32{" "}};
            endcase
            text_character = line[255-8*column -: 8];
        end
    endfunction

    `include "font3x5.vh"


    reg [4:0] message;
    reg [9:0] text_x, text_y;
    reg text_enabled, number_enabled, wide_number;
    reg [23:0] number;
    reg [11:0] background, ink;
    // Stage 1 captures layout results before the text/numeric lookup.
    reg [4:0] layout_message;
    reg [4:0] layout_text_column;
    reg [2:0] layout_digit_index;
    reg [23:0] layout_number;
    reg layout_numeric;
    reg layout_text_visible;
    reg [1:0] layout_column;
    reg [2:0] layout_row;
    reg [11:0] layout_background, layout_ink;
    reg layout_hud;

    // Stage 2 holds a character and its matching glyph/color coordinates.
    reg [7:0] character;
    reg [2:0] column_reg, row_reg;
    reg [11:0] background_reg, ink_reg;
    reg hud_reg;
    wire [9:0] dx = x-text_x;
    wire [9:0] dy = y-text_y;
    wire [14:0] bitmap = glyph3x5(character);

    always @* begin
        background=COLOR_BACKGROUND;
        ink=COLOR_TEXT;
        message=TEXT_TITLE;
        text_x=0;
        text_y=0;
        text_enabled=0;
        number_enabled=0;
        wide_number=0;
        number=0;
        if (x >= `FIELD_LEFT && x < `FIELD_RIGHT && y >= `FIELD_TOP && y < 448) begin
            background=COLOR_PANEL;
            if (y[4:0]==0) background=COLOR_GRID;
            if (x==`FIELD_LEFT || x==`FIELD_RIGHT-1) background=COLOR_LINE;
        end
        case(screen)
            `SCREEN_HOME: begin
                if (x>=112 && x<528 && ((y>=160 && y<208) ||
                    (y>=240 && y<288) || (y>=320 && y<368))) begin
                    background=COLOR_CARD;
                    if (x==112 || x==527) background=COLOR_ACCENT;
                end
                if (y>=64 && y<84) begin
                    message=TEXT_TITLE;
                    text_x=256;
                    text_y=64;
                    ink=COLOR_ACCENT;
                end
                else if (y>=112 && y<132) begin
                    message=TEXT_SELECT_SONG;
                    text_x=216;
                    text_y=112;
                end
                else if (y>=176 && y<196) begin
                    message=TEXT_SONG0_CHOICE;
                    text_x=144;
                    text_y=176;
                end
                else if (y>=256 && y<276) begin
                    message=TEXT_SONG1_CHOICE;
                    text_x=144;
                    text_y=256;
                end
                else if (y>=336 && y<356) begin
                    message=TEXT_SONG2_CHOICE;
                    text_x=144;
                    text_y=336;
                end
                else if (y>=416 && y<436) begin
                    message=TEXT_SELECT_KEYS;
                    text_x=160;
                    text_y=416;
                    ink=COLOR_PURPLE;
                end
                text_enabled=1;
            end
            `SCREEN_GAME: begin
                if(y>=15 && y<35) begin
                    text_y=15;
                    text_enabled=1;
                    if(x<320) begin
                        message=TEXT_SCORE; text_x=64;
                        if(x>=160 && x<256) begin
                            text_x=160; number=score_digits;
                            number_enabled=1; wide_number=1;
                        end
                    end else begin
                        message=TEXT_COMBO; text_x=352; ink=COLOR_ACCENT;
                        if(x>=448 && x<512) begin
                            text_x=448; number={8'b0,combo_digits}; number_enabled=1;
                        end
                    end
                end
            end
            `SCREEN_RESULTS: begin
                if (y>=64 && y<84) begin
                    message=failed ? TEXT_AUDIO_ERROR : TEXT_RESULTS;
                    text_x=failed ? 232 : 264; text_y=64;
                    ink=failed ? COLOR_ERROR : COLOR_ACCENT;
                end else if (y>=112 && y<132) begin
                    message=TEXT_SONG0_TITLE+song;
                    text_x=song==0 ? 208 : song==1 ? 288 : 248;
                    text_y=112;
                end
                else if (y>=RESULTS_SCORE_Y && y<RESULTS_SCORE_Y+TEXT_HEIGHT) begin
                    message=TEXT_SCORE;
                    text_x=RESULTS_LABEL_X;
                    text_y=RESULTS_SCORE_Y;
                end
                else if (y>=RESULTS_HITS_Y && y<RESULTS_HITS_Y+TEXT_HEIGHT) begin
                    message=TEXT_HITS;
                    text_x=RESULTS_LABEL_X;
                    text_y=RESULTS_HITS_Y;
                end
                else if (y>=RESULTS_MISSES_Y && y<RESULTS_MISSES_Y+TEXT_HEIGHT) begin
                    message=TEXT_MISSES;
                    text_x=RESULTS_LABEL_X;
                    text_y=RESULTS_MISSES_Y;
                end
                else if (y>=RESULTS_MISCLICKS_Y && y<RESULTS_MISCLICKS_Y+TEXT_HEIGHT) begin
                    message=TEXT_MISCLICKS;
                    text_x=RESULTS_LABEL_X;
                    text_y=RESULTS_MISCLICKS_Y;
                end
                else if (y>=RESULTS_STREAK_Y && y<RESULTS_STREAK_Y+TEXT_HEIGHT) begin
                    message=TEXT_BEST_STREAK;
                    text_x=RESULTS_LABEL_X;
                    text_y=RESULTS_STREAK_Y;
                end
                else if (y>=400 && y<420) begin
                    message=TEXT_RETURN_HOME;
                    text_x=192;
                    text_y=400;
                    ink=COLOR_PURPLE;
                end
                text_enabled=1;
                if (x>=SCORE_VALUE_X && x<VALUE_RIGHT_X) begin
                    if (y>=RESULTS_SCORE_Y && y<RESULTS_SCORE_Y+TEXT_HEIGHT) begin
                        number=score_digits; text_y=RESULTS_SCORE_Y; number_enabled=1; wide_number=1;
                    end
                    if (x>=COUNT_VALUE_X) begin
                        if (y>=RESULTS_HITS_Y && y<RESULTS_HITS_Y+TEXT_HEIGHT) begin
                            number={8'b0,hit_digits};
                            text_y=RESULTS_HITS_Y;
                            number_enabled=1;
                        end
                        if (y>=RESULTS_MISSES_Y && y<RESULTS_MISSES_Y+TEXT_HEIGHT) begin
                            number={8'b0,miss_digits};
                            text_y=RESULTS_MISSES_Y;
                            number_enabled=1;
                        end
                        if (y>=RESULTS_MISCLICKS_Y && y<RESULTS_MISCLICKS_Y+TEXT_HEIGHT) begin
                            number={8'b0,misclick_digits};
                            text_y=RESULTS_MISCLICKS_Y;
                            number_enabled=1;
                        end
                        if (y>=RESULTS_STREAK_Y && y<RESULTS_STREAK_Y+TEXT_HEIGHT) begin
                            number={8'b0,longest_digits};
                            text_y=RESULTS_STREAK_Y;
                            number_enabled=1;
                        end
                    end
                    if (number_enabled) text_x=wide_number ? SCORE_VALUE_X : COUNT_VALUE_X;
                end
            end
            `SCREEN_LOADING: begin
                if (y>=160 && y<180) begin
                    message=TEXT_LOADING;
                    text_x=264;
                    text_y=160;
                    ink=COLOR_ACCENT;
                end
                else if (y>=224 && y<244) begin
                    message=TEXT_SONG0_TITLE+song;
                    text_x=song==0 ? 208 : song==1 ? 288 : 248;
                    text_y=224;
                end
                else if (y>=288 && y<308) begin
                    message=TEXT_WAIT_AUDIO;
                    text_x=184;
                    text_y=288;
                    ink=COLOR_PURPLE;
                end
                text_enabled=1;
            end
            default: begin end
        endcase
        text_enabled = text_enabled && text_y != 0;
    end

    always @(posedge clk) begin
        if (reset) begin
            layout_message <= TEXT_TITLE;
            layout_text_column <= 0;
            layout_digit_index <= 0;
            layout_number <= 0;
            layout_numeric <= 0;
            layout_text_visible <= 0;
            layout_column <= 0;
            layout_row <= 0;
            layout_background <= COLOR_BACKGROUND;
            layout_ink <= COLOR_TEXT;
            layout_hud <= 0;
            character <= " ";
            hud_reg <= 0;
            hud_pixel <= 0;
            column_reg <= 0;
            row_reg <= 0;
            background_reg <= COLOR_BACKGROUND;
            ink_reg <= COLOR_TEXT;
            color <= COLOR_BACKGROUND;
        end else begin
            // Decode screen regions and local coordinates in their own stage.
            layout_message <= message;
            layout_text_column <= dx[8:4];
            layout_digit_index <= wide_number ? 3'd5-dx[6:4] : 3'd3-{1'b0,dx[5:4]};
            layout_number <= number;
            layout_numeric <= number_enabled;
            layout_text_visible <= text_enabled && x>=text_x &&
                dx<32*CELL_WIDTH && dy<TEXT_HEIGHT && dx[3:2]<3;
            layout_column <= dx[3:2];
            layout_row <= dy[4:2];
            layout_background <= background;
            layout_ink <= ink;
            layout_hud <= screen==`SCREEN_GAME && y<`FIELD_TOP;

            // Character lookup now starts at layout registers, separating it
            // from the VGA row counter and region/coordinate calculations.
            character <= " ";
            if (layout_text_visible) begin
                if (layout_numeric)
                    character <= 8'd48 + {4'b0,layout_number[4*layout_digit_index +: 4]};
                else
                    character <= text_character(layout_message,layout_text_column);
            end
            column_reg <= {1'b0,layout_column};
            row_reg <= layout_row;
            background_reg <= layout_background;
            ink_reg <= layout_ink;
            hud_reg <= layout_hud;

            // Stage 3 resolves the glyph pixel. Delay HUD selection alongside
            // RGB so the top-level game/menu multiplexer uses the same pixel.
            color <= background_reg;
            if (column_reg<3 && row_reg<5 && bitmap[14-3*row_reg-column_reg])
                color <= ink_reg;
            hud_pixel <= hud_reg;
        end
    end
endmodule
`default_nettype wire
