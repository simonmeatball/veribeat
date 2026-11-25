`timescale 1ns / 1ps
`default_nettype none

// Grade relative to a perfect run with the existing 1x/2x/3x/4x combos.
// Work in hundreds of points so no divider is needed. Threshold products
// are registered separately from comparisons and the VGA text pipeline.
module result_grade (
    input wire clk, reset,
    input wire [10:0] note_count,
    input wire [19:0] total_score,
    output reg [7:0] grade
);
    wire [12:0] notes = {2'b0,note_count};
    reg [12:0] maximum_hundreds;
    reg has_notes, thresholds_valid;
    reg [19:0] threshold_s, threshold_a, threshold_b, threshold_c, threshold_d;
    always @(posedge clk) begin
        if (reset) begin
            maximum_hundreds <= 0;
            has_notes <= 0;
            thresholds_valid <= 0;
            threshold_s <= 0; threshold_a <= 0; threshold_b <= 0;
            threshold_c <= 0; threshold_d <= 0;
            grade <= "F";
        end else begin
            if (note_count < 10) maximum_hundreds <= notes;
            else if (note_count < 20) maximum_hundreds <= (notes<<1)-13'd9;
            else if (note_count < 30) maximum_hundreds <= (notes<<1)+notes-13'd28;
            else maximum_hundreds <= (notes<<2)-13'd57;
            has_notes <= note_count != 0;
            // score >= (perfect_score / 100) * percentage is equivalent
            // to score / perfect_score >= percentage / 100.
            threshold_s <= maximum_hundreds * 20'd95;
            threshold_a <= maximum_hundreds * 20'd90;
            threshold_b <= maximum_hundreds * 20'd80;
            threshold_c <= maximum_hundreds * 20'd70;
            threshold_d <= maximum_hundreds * 20'd60;
            thresholds_valid <= has_notes;
            if (!thresholds_valid) grade <= "F";
            else if (total_score >= threshold_s) grade <= "S";
            else if (total_score >= threshold_a) grade <= "A";
            else if (total_score >= threshold_b) grade <= "B";
            else if (total_score >= threshold_c) grade <= "C";
            else if (total_score >= threshold_d) grade <= "D";
            else grade <= "F";
        end
    end
endmodule

`default_nettype wire
