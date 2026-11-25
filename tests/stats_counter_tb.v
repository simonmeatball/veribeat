`timescale 1ns / 1ps
module stats_counter_tb;
    reg clk=0,reset=1;
    reg [15:0] events=0;
    wire [13:0] count;
    wire [15:0] digits;
    integer i;
    always #5 clk=~clk;
    event_counter #(.WIDTH(14),.LIMIT(9999),.INPUT_BITS(16)) dut(clk,reset,events,count,digits);
    initial begin
        repeat(3) @(negedge clk); reset=0;
        events=16'hffff;
        @(negedge clk); events=0;
        repeat(20) @(negedge clk);
        if(count !== 16 || digits !== 16'h0016) $stop;
        // Saturate the four-digit display cleanly under a burst of events.
        events=16'hffff;
        repeat(700) @(negedge clk);
        events=0;
        repeat(11000) @(negedge clk);
        if(count !== 9999 || digits !== 16'h9999) $stop;
        reset=1;
        @(negedge clk);
        if(count !== 0 || digits !== 0) $stop;
        $display("PASS: simultaneous misclicks, decimal counters, saturation and reset");
        $finish;
    end
endmodule
