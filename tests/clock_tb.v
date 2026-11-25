`timescale 1ns / 1ps
`default_nettype none

module clock_tb;
    reg clk = 0;
    reg reset = 0;
    wire reset_sync;
    wire pixel_tick;
    integer phase = 0;
    integer checks = 0;

    always #5 clk = ~clk;
    clock dut (.clk(clk), .reset(reset), .reset_sync(reset_sync), .pixel_tick(pixel_tick));

    task fail;
        begin
            $display("FAIL: pixel enable or reset at %0t", $time);
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
        if (pixel_tick !== (!reset_sync && phase == 3)) fail;
        checks = checks + 1;
    end

    initial begin
        repeat (103) @(negedge clk);
        #2 reset = 1;
        #1;
        if (reset_sync !== 1'b0) fail;
        @(posedge clk); #1;
        if (reset_sync !== 1'b0) fail;
        @(posedge clk); #1;
        if (reset_sync !== 1'b1 || pixel_tick !== 1'b0) fail;
        repeat (3) @(negedge clk);
        #2 reset = 0;
        @(posedge clk); #1;
        if (reset_sync !== 1'b1) fail;
        @(posedge clk); #1;
        if (reset_sync !== 1'b0) fail;
        repeat (120) @(negedge clk);
        $display("PASS: one-in-four pixel enable, startup phase and clock-synchronous reset edges (%0d cycles)", checks);
        $finish;
    end
endmodule

`default_nettype wire
