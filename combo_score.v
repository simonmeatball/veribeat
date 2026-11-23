`timescale 1ns / 1ps
`default_nettype none

// The judge emits at most four hits per frame. Drain them individually so
// each note in a chord advances the streak and uses its own multiplier.
module combo_score (
    input wire clk,
    input wire reset,
    input wire [3:0] hits,
    input wire note_miss,
    input wire [15:0] misclicks,
    output wire [19:0] total_score,
    output wire [23:0] score_digits,
    output reg [10:0] combo,
    output reg [15:0] combo_digits,
    output reg [10:0] longest_streak,
    output reg [15:0] longest_digits
);
    reg [10:0] pending_hits;
    reg suppressed;
    wire broken = note_miss || |misclicks;
    wire [2:0] incoming = {2'b0,hits[0]} + {2'b0,hits[1]} +
                          {2'b0,hits[2]} + {2'b0,hits[3]};
    wire consume = pending_hits != 0;
    wire [10:0] next_combo = combo == 1024 ? combo : combo + 1'b1;
    wire [2:0] multiplier = broken || suppressed ? 3'd1 :
        next_combo >= 30 ? 3'd4 : next_combo >= 20 ? 3'd3 :
        next_combo >= 10 ? 3'd2 : 3'd1;
    wire [3:0] awards = consume ? 4'b1111 >> (4-multiplier) : 4'b0;
    wire [12:0] hundreds;
    wire [15:0] hundred_digits;
    // Every award is a multiple of 100. Four BCD digits plus two zeroes
    // represent the maximum perfect-game score of 403900 without a divider.
    score #(.WIDTH(13),.LIMIT(9999)) weighted_points (
        .clk(clk),.reset(reset),.hits(awards),.points(hundreds),.digits(hundred_digits)
    );
    assign total_score = {7'b0,hundreds} * 20'd100;
    assign score_digits = {hundred_digits,8'h00};

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
            suppressed<=0;
            combo<=0;
            combo_digits<=0;
            longest_streak<=0;
            longest_digits<=0;
        end else begin
            pending_hits<=pending_hits+incoming-consume;
            if(pending_hits==0 && incoming!=0) suppressed<=broken;
            else if(broken) suppressed<=1;
            if(broken) begin
                combo<=0;
                combo_digits<=0;
            end else if(consume && !suppressed) begin
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
