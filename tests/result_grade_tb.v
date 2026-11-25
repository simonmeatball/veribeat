`timescale 1ns / 1ps
module result_grade_tb;
    reg clk=0,reset=1;
    reg [10:0] notes=0,hits=0,misses=0;
    reg [13:0] misclicks=0;
    wire [7:0] grade[0:2];
    integer n,h,bad,setting,checks=0,credit,factor;
    reg [7:0] expected;
    always #5 clk=~clk;
    result_grade dut(clk,reset,notes,hits,misses,misclicks,grade[0]);
    result_grade #(.PENALTY_PERCENT(0)) no_penalty(clk,reset,notes,hits,misses,misclicks,grade[1]);
    result_grade #(.PENALTY_PERCENT(100)) full_penalty(clk,reset,notes,hits,misses,misclicks,grade[2]);
    task check_grade;
        input integer count,hit_total,miss_total,bad_total;
        begin
            @(negedge clk); notes=count; hits=hit_total; misses=miss_total; misclicks=bad_total;
            repeat(6) @(negedge clk);
            for(setting=0;setting<3;setting=setting+1) begin
                factor=setting==0 ? 25 : setting==1 ? 0 : 100;
                credit=100*hit_total-factor*(miss_total+bad_total);
                if(count==0) expected="F";
                else if(credit>=count*95) expected="S";
                else if(credit>=count*90) expected="A";
                else if(credit>=count*80) expected="B";
                else if(credit>=count*70) expected="C";
                else if(credit>=count*60) expected="D";
                else expected="F";
                if(grade[setting]!==expected) begin
                    $display("FAIL grade: factor=%0d notes=%0d hits=%0d misses=%0d bad=%0d got=%c expected=%c",
                        factor,count,hit_total,miss_total,bad_total,grade[setting],expected); $stop;
                end
                checks=checks+1;
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        check_grade(0,0,0,0);
        for(n=1;n<=31;n=n+1)
            for(h=0;h<=n;h=h+1)
                for(bad=0;bad<=4;bad=bad+1) check_grade(n,h,n-h,bad);
        for(n=419;n<=1024;n=n+1)
            if(n==419 || n==540 || n==854 || n==1024)
                for(h=0;h<=n;h=h+1) check_grade(n,h,n-h,0);
        // Real photographed result: previously F from combo score, now A.
        check_grade(854,808,46,45);
        if(grade[0]!=="A") $stop;
        // Penalties below zero must stay F rather than unsigned-wrap to S.
        check_grade(1024,0,1024,9999);
        check_grade(1024,1024,0,9999);
        check_grade(1024,1024,0,0);
        // Test exact quarter-hit boundaries for every tier.
        for(h=60;h<=95;h=h+5) begin
            check_grade(100,h+1,0,4);
            check_grade(100,h+1,0,5);
        end
        @(negedge clk); reset=1;
        @(negedge clk); if(grade[0]!=="F") $stop;
        $display("PASS: hit-based grades, configurable penalties, photographed A result, tier boundaries, negative totals and reset (%0d checks)",checks);
        $finish;
    end
endmodule
