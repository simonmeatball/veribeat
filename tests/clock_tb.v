`timescale 1ns / 1ps
`default_nettype none

module clock_tb;
    reg clk = 0;
    reg reset = 0;
    wire reset_sync;
    wire CLK_100MHz, CLK_50MHz, CLK_25MHz, pixel_tick;
    integer phase = 0;
    integer checks = 0;

    always #5 clk = ~clk;
    clock dut (
        .clk(clk), .reset(reset), .reset_sync(reset_sync),
        .CLK_100MHz(CLK_100MHz), .CLK_50MHz(CLK_50MHz),
        .CLK_25MHz(CLK_25MHz), .pixel_tick(pixel_tick)
    );

    task fail;
        begin
            $display("FAIL: clock frequency, duty cycle, enable or reset at %0t", $time);
            $stop;
            $finish;
        end
    endtask

    always begin
        @(posedge clk);
        if (reset_sync) begin
            phase = 0;
        end else begin
            if (pixel_tick !== (phase == 3)) fail;
            phase = (phase + 1) % 4;
        end
        #1;
        if (CLK_100MHz !== clk || CLK_50MHz !== (phase % 2 == 1) ||
            CLK_25MHz !== (phase >= 2)) fail;
        if (pixel_tick !== (!reset_sync && phase == 3)) fail;
        checks = checks + 1;
    end

    initial begin
        repeat (103) @(negedge clk);
        #2 reset = 1;
        #1;
        if (reset_sync !== 1'b1 || pixel_tick !== 1'b0) fail;
        repeat (3) @(negedge clk);
        #2 reset = 0;
        @(posedge clk); #1;
        if (reset_sync !== 1'b1) fail;
        @(posedge clk); #1;
        if (reset_sync !== 1'b0) fail;
        repeat (120) @(negedge clk);
        $display("PASS: 25/50/100 MHz clocks, 50%% duty cycle, pixel enable and reset (%0d cycles)", checks);
        $finish;
    end
endmodule

`default_nettype wire
