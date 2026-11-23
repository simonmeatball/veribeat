`timescale 1ns / 1ps
`default_nettype none

// Two 100 MHz stages fit inside the four-cycle pixel interval. VGA samples
// the settled result for its current x/y, preserving its existing sync delay.
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
    function [7:0] text_character;
        input [4:0] message;
        input [4:0] column;
        begin
            case ({message,column})
                10'd0: text_character = "V";
                10'd1: text_character = "E";
                10'd2: text_character = "R";
                10'd3: text_character = "I";
                10'd4: text_character = "B";
                10'd5: text_character = "E";
                10'd6: text_character = "A";
                10'd7: text_character = "T";
                10'd32: text_character = "S";
                10'd33: text_character = "E";
                10'd34: text_character = "L";
                10'd35: text_character = "E";
                10'd36: text_character = "C";
                10'd37: text_character = "T";
                10'd39: text_character = "A";
                10'd41: text_character = "S";
                10'd42: text_character = "O";
                10'd43: text_character = "N";
                10'd44: text_character = "G";
                10'd64: text_character = "1";
                10'd66: text_character = "Y";
                10'd67: text_character = "O";
                10'd68: text_character = "R";
                10'd69: text_character = "U";
                10'd71: text_character = "N";
                10'd72: text_character = "I";
                10'd74: text_character = "K";
                10'd75: text_character = "A";
                10'd76: text_character = "K";
                10'd77: text_character = "E";
                10'd78: text_character = "R";
                10'd79: text_character = "U";
                10'd96: text_character = "2";
                10'd98: text_character = "A";
                10'd99: text_character = "P";
                10'd100: text_character = "T";
                10'd101: text_character = ".";
                10'd128: text_character = "3";
                10'd130: text_character = "S";
                10'd131: text_character = "U";
                10'd132: text_character = "N";
                10'd133: text_character = "F";
                10'd134: text_character = "L";
                10'd135: text_character = "O";
                10'd136: text_character = "W";
                10'd137: text_character = "E";
                10'd138: text_character = "R";
                10'd160: text_character = "0";
                10'd162: text_character = "F";
                10'd164: text_character = "E";
                10'd166: text_character = "D";
                10'd168: text_character = "T";
                10'd169: text_character = "O";
                10'd171: text_character = "P";
                10'd172: text_character = "L";
                10'd173: text_character = "A";
                10'd174: text_character = "Y";
                10'd192: text_character = "R";
                10'd193: text_character = "E";
                10'd194: text_character = "S";
                10'd195: text_character = "U";
                10'd196: text_character = "L";
                10'd197: text_character = "T";
                10'd198: text_character = "S";
                10'd224: text_character = "H";
                10'd225: text_character = "I";
                10'd226: text_character = "T";
                10'd227: text_character = "S";
                10'd256: text_character = "M";
                10'd257: text_character = "I";
                10'd258: text_character = "S";
                10'd259: text_character = "S";
                10'd260: text_character = "E";
                10'd261: text_character = "S";
                10'd288: text_character = "M";
                10'd289: text_character = "I";
                10'd290: text_character = "S";
                10'd291: text_character = "C";
                10'd292: text_character = "L";
                10'd293: text_character = "I";
                10'd294: text_character = "C";
                10'd295: text_character = "K";
                10'd296: text_character = "S";
                10'd320: text_character = "P";
                10'd321: text_character = "R";
                10'd322: text_character = "E";
                10'd323: text_character = "S";
                10'd324: text_character = "S";
                10'd326: text_character = "A";
                10'd327: text_character = "N";
                10'd328: text_character = "Y";
                10'd330: text_character = "B";
                10'd331: text_character = "U";
                10'd332: text_character = "T";
                10'd333: text_character = "T";
                10'd334: text_character = "O";
                10'd335: text_character = "N";
                10'd352: text_character = "L";
                10'd353: text_character = "O";
                10'd354: text_character = "A";
                10'd355: text_character = "D";
                10'd356: text_character = "I";
                10'd357: text_character = "N";
                10'd358: text_character = "G";
                10'd384: text_character = "W";
                10'd385: text_character = "A";
                10'd386: text_character = "I";
                10'd387: text_character = "T";
                10'd388: text_character = "I";
                10'd389: text_character = "N";
                10'd390: text_character = "G";
                10'd392: text_character = "F";
                10'd393: text_character = "O";
                10'd394: text_character = "R";
                10'd396: text_character = "A";
                10'd397: text_character = "U";
                10'd398: text_character = "D";
                10'd399: text_character = "I";
                10'd400: text_character = "O";
                10'd416: text_character = "Y";
                10'd417: text_character = "O";
                10'd418: text_character = "R";
                10'd419: text_character = "U";
                10'd421: text_character = "N";
                10'd422: text_character = "I";
                10'd424: text_character = "K";
                10'd425: text_character = "A";
                10'd426: text_character = "K";
                10'd427: text_character = "E";
                10'd428: text_character = "R";
                10'd429: text_character = "U";
                10'd448: text_character = "A";
                10'd449: text_character = "P";
                10'd450: text_character = "T";
                10'd451: text_character = ".";
                10'd480: text_character = "S";
                10'd481: text_character = "U";
                10'd482: text_character = "N";
                10'd483: text_character = "F";
                10'd484: text_character = "L";
                10'd485: text_character = "O";
                10'd486: text_character = "W";
                10'd487: text_character = "E";
                10'd488: text_character = "R";
                10'd512: text_character = "A";
                10'd513: text_character = "U";
                10'd514: text_character = "D";
                10'd515: text_character = "I";
                10'd516: text_character = "O";
                10'd518: text_character = "E";
                10'd519: text_character = "R";
                10'd520: text_character = "R";
                10'd521: text_character = "O";
                10'd522: text_character = "R";
                10'd544: text_character = "S";
                10'd545: text_character = "C";
                10'd546: text_character = "O";
                10'd547: text_character = "R";
                10'd548: text_character = "E";
                10'd576: text_character = "C";
                10'd577: text_character = "O";
                10'd578: text_character = "M";
                10'd579: text_character = "B";
                10'd580: text_character = "O";
                10'd608: text_character = "B";
                10'd609: text_character = "E";
                10'd610: text_character = "S";
                10'd611: text_character = "T";
                10'd613: text_character = "S";
                10'd614: text_character = "T";
                10'd615: text_character = "R";
                10'd616: text_character = "E";
                10'd617: text_character = "A";
                10'd618: text_character = "K";
                default: text_character = " ";
            endcase
        end
    endfunction

    function [14:0] glyph;
        input [7:0] character;
        begin
            case(character)
                "0": glyph = 15'b111_101_101_101_111;
                "1": glyph = 15'b010_110_010_010_111;
                "2": glyph = 15'b111_001_111_100_111;
                "3": glyph = 15'b111_001_111_001_111;
                "4": glyph = 15'b101_101_111_001_001;
                "5": glyph = 15'b111_100_111_001_111;
                "6": glyph = 15'b111_100_111_101_111;
                "7": glyph = 15'b111_001_010_010_010;
                "8": glyph = 15'b111_101_111_101_111;
                "9": glyph = 15'b111_101_111_001_111;
                "A": glyph = 15'b010_101_111_101_101;
                "B": glyph = 15'b110_101_110_101_110;
                "C": glyph = 15'b111_100_100_100_111;
                "D": glyph = 15'b110_101_101_101_110;
                "E": glyph = 15'b111_100_110_100_111;
                "F": glyph = 15'b111_100_110_100_100;
                "G": glyph = 15'b111_100_101_101_111;
                "H": glyph = 15'b101_101_111_101_101;
                "I": glyph = 15'b111_010_010_010_111;
                "J": glyph = 15'b001_001_001_101_111;
                "K": glyph = 15'b101_101_110_101_101;
                "L": glyph = 15'b100_100_100_100_111;
                "M": glyph = 15'b101_111_111_101_101;
                "N": glyph = 15'b101_111_111_111_101;
                "O": glyph = 15'b111_101_101_101_111;
                "P": glyph = 15'b111_101_111_100_100;
                "Q": glyph = 15'b111_101_101_111_001;
                "R": glyph = 15'b110_101_110_101_101;
                "S": glyph = 15'b111_100_111_001_111;
                "T": glyph = 15'b111_010_010_010_010;
                "U": glyph = 15'b101_101_101_101_111;
                "V": glyph = 15'b101_101_101_101_010;
                "W": glyph = 15'b101_101_111_111_101;
                "X": glyph = 15'b101_101_010_101_101;
                "Y": glyph = 15'b101_101_010_010_010;
                "Z": glyph = 15'b111_001_010_100_111;
                ".": glyph = 15'b000_000_000_000_010;
                default: glyph = 0;
            endcase
        end
    endfunction

    reg [4:0] message;
    reg [9:0] text_x, text_y;
    reg text_enabled, number_enabled, wide_number;
    reg [23:0] number;
    reg [11:0] background, ink;
    reg [7:0] character;
    reg [2:0] column_reg, row_reg;
    reg [11:0] background_reg, ink_reg;
    reg hud_reg;
    wire [9:0] dx = x-text_x;
    wire [9:0] dy = y-text_y;
    wire [14:0] bitmap = glyph(character);

    always @* begin
        background=12'h012;
        ink=12'hfff;
        message=0;
        text_x=0;
        text_y=0;
        text_enabled=0;
        number_enabled=0;
        wide_number=0;
        number=0;
        if (x >= 64 && x < 576 && y >= 48 && y < 448) begin
            background=12'h113;
            if (y[4:0]==0) background=12'h124;
            if (x==64 || x==575) background=12'h436;
        end
        case(screen)
            0: begin
                if (x>=112 && x<528 && ((y>=160 && y<208) ||
                    (y>=240 && y<288) || (y>=320 && y<368))) begin
                    background=12'h235;
                    if (x==112 || x==527) background=12'h6ef;
                end
                if (y>=64 && y<84) begin message=0; text_x=256; text_y=64; ink=12'h6ef; end
                else if (y>=112 && y<132) begin message=1; text_x=216; text_y=112; end
                else if (y>=176 && y<196) begin message=2; text_x=144; text_y=176; end
                else if (y>=256 && y<276) begin message=3; text_x=144; text_y=256; end
                else if (y>=336 && y<356) begin message=4; text_x=144; text_y=336; end
                else if (y>=416 && y<436) begin message=5; text_x=208; text_y=416; ink=12'hb8f; end
                text_enabled=1;
            end
            1: begin
                if(y>=15 && y<35) begin
                    text_y=15;
                    text_enabled=1;
                    if(x<320) begin
                        message=17; text_x=64;
                        if(x>=160 && x<256) begin
                            text_x=160; number=score_digits;
                            number_enabled=1; wide_number=1;
                        end
                    end else begin
                        message=18; text_x=352; ink=12'h6ef;
                        if(x>=448 && x<512) begin
                            text_x=448; number={8'b0,combo_digits}; number_enabled=1;
                        end
                    end
                end
            end
            2: begin
                if (y>=64 && y<84) begin
                    message=failed ? 16 : 6;
                    text_x=failed ? 232 : 264; text_y=64;
                    ink=failed ? 12'hf44 : 12'h6ef;
                end else if (y>=112 && y<132) begin message=13+song; text_x=song==0 ? 208 : song==1 ? 288 : 248; text_y=112; end
                else if (y>=160 && y<180) begin message=17; text_x=112; text_y=160; end
                else if (y>=200 && y<220) begin message=7; text_x=112; text_y=200; end
                else if (y>=240 && y<260) begin message=8; text_x=112; text_y=240; end
                else if (y>=280 && y<300) begin message=9; text_x=112; text_y=280; end
                else if (y>=320 && y<340) begin message=19; text_x=112; text_y=320; end
                else if (y>=400 && y<420) begin message=10; text_x=192; text_y=400; ink=12'hb8f; end
                text_enabled=1;
                if (x>=400 && x<496) begin
                    if (y>=160 && y<180) begin
                        number=score_digits; text_y=160; number_enabled=1; wide_number=1;
                    end
                    if (x>=432) begin
                        if (y>=200 && y<220) begin number={8'b0,hit_digits}; text_y=200; number_enabled=1; end
                        if (y>=240 && y<260) begin number={8'b0,miss_digits}; text_y=240; number_enabled=1; end
                        if (y>=280 && y<300) begin number={8'b0,misclick_digits}; text_y=280; number_enabled=1; end
                        if (y>=320 && y<340) begin number={8'b0,longest_digits}; text_y=320; number_enabled=1; end
                    end
                    if (number_enabled) text_x=wide_number ? 400 : 432;
                end
            end
            3: begin
                if (y>=160 && y<180) begin message=11; text_x=264; text_y=160; ink=12'h6ef; end
                else if (y>=224 && y<244) begin message=13+song; text_x=song==0 ? 208 : song==1 ? 288 : 248; text_y=224; end
                else if (y>=288 && y<308) begin message=12; text_x=184; text_y=288; ink=12'hb8f; end
                text_enabled=1;
            end
            default: begin end
        endcase
        text_enabled = text_enabled && text_y != 0;
    end

    always @(posedge clk) begin
        if (reset) begin
            character <= " ";
            hud_reg <= 0;
            hud_pixel <= 0;
            column_reg <= 0;
            row_reg <= 0;
            background_reg <= 12'h012;
            ink_reg <= 12'hfff;
            color <= 12'h012;
        end else begin
            hud_reg <= screen==1 && y<48;
            hud_pixel <= hud_reg;
            background_reg <= background;
            ink_reg <= ink;
            column_reg <= dx[3:2];
            row_reg <= dy[4:2];
            character <= " ";
            if (text_enabled && x>=text_x && dx<512 && dy<20 && dx[3:2]<3) begin
                if (number_enabled) begin
                    if(wide_number) character <= 8'd48 + {4'b0,number[4*(5-dx[6:4]) +: 4]};
                    else character <= 8'd48 + {4'b0,number[4*(3-dx[5:4]) +: 4]};
                end
                else character <= text_character(message,dx[8:4]);
            end
            color <= background_reg;
            if (column_reg<3 && row_reg<5 && bitmap[14-3*row_reg-column_reg])
                color <= ink_reg;
        end
    end
endmodule
`default_nettype wire
