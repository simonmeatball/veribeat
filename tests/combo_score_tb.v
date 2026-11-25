`timescale 1ns / 1ps
module combo_score_tb;
    reg clk=0,reset=1;
    reg [3:0] hits=0;
    reg [11:0] hit_judgments={4{`JUDGMENT_PERFECT}};
    reg miss=0;
    reg [15:0] misclicks=0;
    wire [19:0] points;
    wire [23:0] digits;
    wire [10:0] combo,best;
    wire [15:0] combo_digits,best_digits;
    integer note,expected,base;
    always #5 clk=~clk;
    combo_score dut(.clk(clk),.reset(reset),.hits(hits),.hit_judgments(hit_judgments),
        .note_miss(miss),.misclicks(misclicks),.total_score(points),.score_digits(digits),
        .combo(combo),.combo_digits(combo_digits),.longest_streak(best),.longest_digits(best_digits));
    function [23:0] decimal_digits;
        input integer value;
        integer digit;
        begin
            decimal_digits=0;
            for(digit=0;digit<6;digit=digit+1) begin
                decimal_digits[4*digit +: 4]=value%10;
                value=value/10;
            end
        end
    endfunction
    // Binary score and decimal display must always publish the same snapshot.
    always @(negedge clk) if(!reset && digits!==decimal_digits(points)) $stop;
    task submit;
        input [3:0] hit_mask;
        input missed;
        input [15:0] invalid;
        begin
            @(negedge clk); hits=hit_mask; miss=missed; misclicks=invalid;
            @(negedge clk); hits=0; miss=0; misclicks=0; hit_judgments=0;
            repeat(64) @(negedge clk);
            hit_judgments={4{`JUDGMENT_PERFECT}};
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        for(note=0;note<3;note=note+1) submit(1,0,0);
        if(points !== 300 || combo !== 3 || best !== 3) $stop;
        submit(0,1,0);
        if(points !== 300 || combo !== 0 || best !== 3) $stop;
        for(note=0;note<10;note=note+1) submit(1,0,0);
        if(points !== 1400 || combo !== 10 || best !== 10) $stop;
        submit(0,0,1);
        if(combo !== 0 || best !== 10) $stop;
        submit(15,0,0);
        if(points !== 1800 || combo !== 4 || best !== 10) $stop;
        submit(15,0,1);
        if(points !== 2200 || combo !== 0 || best !== 10) $stop;
        // A miss arriving while a chord is being drained cancels its streak.
        @(negedge clk); hits=15;
        @(negedge clk); hits=0; miss=1;
        @(negedge clk); miss=0;
        repeat(32) @(negedge clk);
        if(points !== 2600 || combo !== 0 || best !== 10) $stop;
        @(negedge clk); reset=1;
        @(negedge clk); reset=0;
        for(note=0;note<8;note=note+1) submit(1,0,0);
        submit(15,0,0); // A chord crosses from the 1x into the 2x tier.
        if(points !== 1500 || combo !== 12 || best !== 12) $stop;
        @(negedge clk); reset=1;
        @(negedge clk); reset=0;
        expected=0;
        for(note=1;note<=1024;note=note+1) begin
            submit(1,0,0);
            expected=expected+(note>=30 ? 400 : note>=20 ? 300 : note>=10 ? 200 : 100);
            if(points !== expected || combo !== note || best !== note) begin
                $display("FAIL multiplier/streak at note %0d, score %0d",note,points); $stop;
            end
        end
        if(points !== 403900 || digits !== 24'h403900 || combo_digits !== 16'h1024 || best_digits !== 16'h1024) $stop;
        submit(0,1,0);
        if(combo !== 0 || combo_digits !== 0 || best !== 1024 || points !== 403900) $stop;
        @(negedge clk); reset=1;
        @(negedge clk);
        if(points !== 0 || best !== 0 || digits !== 0 || best_digits !== 0) $stop;
        reset=0;
        // Mixed-quality chords retain lane order when crossing a combo tier.
        for(note=0;note<8;note=note+1) submit(1,0,0);
        hit_judgments={`JUDGMENT_GOOD,`JUDGMENT_PERFECT,`JUDGMENT_GREAT,`JUDGMENT_GOOD};
        submit(15,0,0);
        if(points!==1340 || combo!==12) $stop;
        submit(0,1,0);
        if(points!==1340 || combo!==0) $stop;
        hit_judgments={`JUDGMENT_GOOD,`JUDGMENT_GREAT,`JUDGMENT_GOOD,`JUDGMENT_PERFECT};
        submit(15,0,16'hffff);
        if(points!==1640 || combo!==0 || best!==12) $stop;
        @(negedge clk); reset=1;
        @(negedge clk); reset=0;
        expected=0;
        for(note=1;note<=1024;note=note+1) begin
            case(note%3)
                0: begin hit_judgments={4{`JUDGMENT_PERFECT}}; base=100; end
                1: begin hit_judgments={4{`JUDGMENT_GREAT}}; base=80; end
                2: begin hit_judgments={4{`JUDGMENT_GOOD}}; base=60; end
            endcase
            submit(1,0,0);
            expected=expected+base*(note>=30 ? 4 : note>=20 ? 3 : note>=10 ? 2 : 1);
            if(points!==expected || digits!==decimal_digits(expected) || combo!==note) $stop;
        end
        $display("PASS: weighted timing scores, combo tiers, mixed chords, penalties, coherent BCD, 1024-note games and restart");
        $finish;
    end
endmodule
