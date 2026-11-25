`timescale 1ns / 1ps
`default_nettype none

// The judge emits one batch of up to four hits per video frame. Drain its
// lanes in order, retaining each timing quality and combo multiplier.
module combo_score (
    input wire clk,
    input wire reset,
    input wire [3:0] hits,
    input wire [11:0] hit_judgments,
    input wire note_miss,
    input wire [15:0] misclicks,
    output reg [19:0] total_score,
    output reg [23:0] score_digits,
    output reg [10:0] combo,
    output reg [15:0] combo_digits,
    output reg [10:0] longest_streak,
    output reg [15:0] longest_digits
);
    `include "game_defs.vh"
    reg [3:0] pending_hits;
    reg [11:0] pending_judgments;
    // A penalty cancels combo growth for already-queued hits. The next
    // batch can start a new streak once those hits have drained.
    reg block_pending_combo;
    wire penalty = note_miss || |misclicks;
    wire [1:0] next_lane = pending_hits[0] ? 2'd0 : pending_hits[1] ? 2'd1 :
                           pending_hits[2] ? 2'd2 : 2'd3;
    wire consume = pending_hits != 0;
    wire [10:0] next_combo = combo == 1024 ? combo : combo + 1'b1;
    wire [2:0] multiplier = penalty || block_pending_combo ? 3'd1 :
        next_combo >= 30 ? 3'd4 : next_combo >= 20 ? 3'd3 :
        next_combo >= 10 ? 3'd2 : 3'd1;
    reg [6:0] base_points;
    always @* begin
        case(pending_judgments[3*next_lane +: 3])
            `JUDGMENT_PERFECT: base_points=100;
            `JUDGMENT_GREAT: base_points=80;
            `JUDGMENT_GOOD: base_points=60;
            default: base_points=0;
        endcase
    end
    wire [8:0] award = multiplier==4 ? {base_points,2'b0} :
        multiplier==3 ? {1'b0,base_points,1'b0}+{2'b0,base_points} :
        multiplier==2 ? {1'b0,base_points,1'b0} : {2'b0,base_points};
    reg [8:0] awarded_points;
    reg [19:0] accumulated_score;

    // Convert a snapshot over twenty cycles, avoiding a long decimal carry
    // or divider path. Publish binary score and all six digits together.
    reg [19:0] snapshot, binary_shift;
    reg [23:0] bcd;
    reg [4:0] remaining_bits;
    function [23:0] adjust_bcd;
        input [23:0] value;
        integer digit;
        begin
            adjust_bcd=value;
            for(digit=0;digit<6;digit=digit+1)
                if(value[4*digit +: 4]>=5)
                    adjust_bcd[4*digit +: 4]=value[4*digit +: 4]+4'd3;
        end
    endfunction
    wire [23:0] corrected_bcd=adjust_bcd(bcd);
    wire [23:0] shifted_bcd={corrected_bcd[22:0],binary_shift[19]};
    always @(posedge clk) begin
        if(reset) begin
            awarded_points<=0; accumulated_score<=0;
            total_score<=0; score_digits<=0;
            snapshot<=0; binary_shift<=0; bcd<=0; remaining_bits<=0;
        end else begin
            awarded_points<=consume ? award : 9'd0;
            accumulated_score<=accumulated_score+{11'b0,awarded_points};
            if(remaining_bits==0) begin
                snapshot<=accumulated_score;
                binary_shift<=accumulated_score;
                bcd<=0;
                remaining_bits<=20;
            end else begin
                bcd<=shifted_bcd;
                binary_shift<={binary_shift[18:0],1'b0};
                remaining_bits<=remaining_bits-1'b1;
                if(remaining_bits==1) begin
                    total_score<=snapshot;
                    score_digits<=shifted_bcd;
                end
            end
        end
    end

    function [15:0] increment_bcd;
        input [15:0] value;
        reg [15:0] result;
        begin
            result=value;
            if(value[3:0] != 9) result[3:0]=value[3:0]+1'b1;
            else begin
                result[3:0]=0;
                if(value[7:4] != 9) result[7:4]=value[7:4]+1'b1;
                else begin
                    result[7:4]=0;
                    if(value[11:8] != 9) result[11:8]=value[11:8]+1'b1;
                    else begin
                        result[11:8]=0;
                        result[15:12]=value[15:12]+1'b1;
                    end
                end
            end
            increment_bcd=result;
        end
    endfunction
    wire [15:0] next_digits = combo == 1024 ? combo_digits : increment_bcd(combo_digits);

    always @(posedge clk) begin
        if(reset) begin
            pending_hits<=0;
            pending_judgments<=0;
            block_pending_combo<=0;
            combo<=0;
            combo_digits<=0;
            longest_streak<=0;
            longest_digits<=0;
        end else begin
            if(|hits) begin
                pending_hits<=hits;
                pending_judgments<=hit_judgments;
                block_pending_combo<=penalty;
            end else if(consume) pending_hits[next_lane]<=0;
            if(!(|hits) && penalty) block_pending_combo<=1;
            if(penalty) begin
                combo<=0;
                combo_digits<=0;
            end else if(consume && !block_pending_combo) begin
                combo<=next_combo;
                combo_digits<=next_digits;
                if(next_combo>longest_streak) begin
                    longest_streak<=next_combo;
                    longest_digits<=next_digits;
                end
            end
        end
    end
endmodule
`default_nettype wire
