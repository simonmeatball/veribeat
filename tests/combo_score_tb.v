`timescale 1ns / 1ps
module combo_score_tb;
    reg clk=0,reset=1;
    reg [3:0] hits=0;
    reg miss=0;
    reg [15:0] misclicks=0;
    wire [19:0] points;
    wire [23:0] digits;
    wire [10:0] combo,best;
    wire [15:0] combo_digits,best_digits;
    integer note,expected;
    always #5 clk=~clk;
    combo_score dut(clk,reset,hits,miss,misclicks,points,digits,combo,combo_digits,best,best_digits);
    task submit;
        input [3:0] hit_mask;
        input missed;
        input [15:0] invalid;
        begin
            @(negedge clk); hits=hit_mask; miss=missed; misclicks=invalid;
            @(negedge clk); hits=0; miss=0; misclicks=0;
            repeat(32) @(negedge clk);
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
        $display("PASS: combo multipliers, chords, penalty resets, longest streak, perfect 1024-note score and restart");
        $finish;
    end
endmodule
