`timescale 1ns / 1ps
module result_grade_tb;
    reg clk=0,reset=1;
    reg [10:0] notes=0;
    reg [19:0] score=0;
    wire [7:0] grade;
    integer n,i,perfect,points,checks=0;
    reg [7:0] expected;
    always #5 clk=~clk;
    result_grade dut(clk,reset,notes,score,grade);
    task check_grade;
        input integer count,value;
        begin
            perfect=0;
            // Independent reference sums the award for every perfect hit.
            for(i=1;i<=count;i=i+1)
                perfect=perfect+(i>=30 ? 400 : i>=20 ? 300 : i>=10 ? 200 : 100);
            if(count==0) expected="F";
            else if(value*100>=perfect*95) expected="S";
            else if(value*100>=perfect*90) expected="A";
            else if(value*100>=perfect*80) expected="B";
            else if(value*100>=perfect*70) expected="C";
            else if(value*100>=perfect*60) expected="D";
            else expected="F";
            @(negedge clk); notes=count; score=value;
            repeat(4) @(negedge clk);
            if(grade!==expected) begin
                $display("FAIL grade: notes=%0d score=%0d got=%c expected=%c",count,value,grade,expected); $stop;
            end
            checks=checks+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        check_grade(0,0);
        for(n=1;n<=31;n=n+1)
            for(points=0;points<=7500;points=points+100) check_grade(n,points);
        // Exact integer thresholds and their immediately preceding scores,
        // including the actual library sizes and the full chart capacity.
        for(n=419;n<=1024;n=n+1) begin
            if(n==419 || n==540 || n==854 || n==1024) begin
                for(points=60;points<=95;points=points+5) begin
                    check_grade(n,(4*n-57)*points);
                    check_grade(n,(4*n-57)*points-1);
                end
                check_grade(n,(4*n-57)*100);
            end
        end
        @(negedge clk); reset=1;
        @(negedge clk); if(grade!=="F") $stop;
        $display("PASS: song-relative S/A/B/C/D/F grades, combo thresholds, exact boundaries and reset (%0d checks)",checks);
        $finish;
    end
endmodule
