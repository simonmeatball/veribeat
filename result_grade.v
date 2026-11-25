`timescale 1ns / 1ps
`default_nettype none

// Grade = (hits - factor * (misses + misclicks)) / total chart notes.
// PENALTY_PERCENT=25 represents factor=0.25. Integer comparisons avoid
// division and rounding. Arithmetic is pipelined outside the VGA path.
module result_grade #(
    parameter integer PENALTY_PERCENT = 25
) (
    input wire clk, reset,
    input wire [10:0] note_count, hit_count, miss_count,
    input wire [13:0] misclick_count,
    output reg [7:0] grade
);
    reg [16:0] hit_credit, delayed_credit;
    reg [14:0] errors;
    reg [30:0] penalty;
    reg signed [31:0] net_credit;
    reg has_notes;
    reg [16:0] threshold_s, threshold_a, threshold_b, threshold_c, threshold_d;
    always @(posedge clk) begin
        if (reset) begin
            hit_credit <= 0; delayed_credit <= 0;
            errors <= 0; penalty <= 0; net_credit <= 0;
            has_notes <= 0;
            threshold_s <= 0; threshold_a <= 0; threshold_b <= 0;
            threshold_c <= 0; threshold_d <= 0;
            grade <= "F";
        end else begin
            hit_credit <= hit_count * 17'd100;
            errors <= {4'b0,miss_count}+{1'b0,misclick_count};
            delayed_credit <= hit_credit;
            penalty <= errors * PENALTY_PERCENT;
            net_credit <= $signed({15'b0,delayed_credit})-$signed({1'b0,penalty});
            threshold_s <= note_count * 17'd95;
            threshold_a <= note_count * 17'd90;
            threshold_b <= note_count * 17'd80;
            threshold_c <= note_count * 17'd70;
            threshold_d <= note_count * 17'd60;
            has_notes <= note_count != 0;
            if (!has_notes) grade <= "F";
            else if (net_credit >= $signed({15'b0,threshold_s})) grade <= "S";
            else if (net_credit >= $signed({15'b0,threshold_a})) grade <= "A";
            else if (net_credit >= $signed({15'b0,threshold_b})) grade <= "B";
            else if (net_credit >= $signed({15'b0,threshold_c})) grade <= "C";
            else if (net_credit >= $signed({15'b0,threshold_d})) grade <= "D";
            else grade <= "F";
        end
    end
endmodule

`default_nettype wire
