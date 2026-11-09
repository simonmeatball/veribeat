`timescale 1ns / 1ps
`default_nettype none

// Exercise non-power-of-two ratios to verify the reusable divider's extension.
module clock_tb;
    reg clk = 0;
    reg reset = 1;
    wire clock6, tick6, clock10, tick10;
    integer phase6 = 0;
    integer phase10 = 0;
    integer checks = 0;

    always #5 clk = ~clk;
    clock_divider #(.DIVIDE(6)) div6 (
        .clk(clk), .reset(reset), .clk_out(clock6), .tick(tick6)
    );
    clock_divider #(.DIVIDE(10)) div10 (
        .clk(clk), .reset(reset), .clk_out(clock10), .tick(tick10)
    );

    task fail;
        begin
            $display("FAIL: divider frequency, duty cycle, or reset at %0t", $time);
            $stop;
            $finish;
        end
    endtask

    always begin
        @(posedge clk);
        if (reset) begin
            phase6 = 0;
            phase10 = 0;
        end else begin
            if (tick6 !== (phase6 == 5) || tick10 !== (phase10 == 9)) fail;
            phase6 = (phase6 + 1) % 6;
            phase10 = (phase10 + 1) % 10;
        end
        #1;
        if (clock6 !== (phase6 >= 3) || clock10 !== (phase10 >= 5)) fail;
        checks = checks + 1;
    end

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (101) @(negedge clk);
        reset = 1;
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (120) @(negedge clk);
        $display("PASS: reusable divide-by-6/divide-by-10, 50%% duty cycle and reset (%0d cycles)", checks);
        $finish;
    end
endmodule

`default_nettype wire
