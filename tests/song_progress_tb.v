`timescale 1ns / 1ps
module song_progress_tb;
    reg clk=0, reset=1, frame_tick=0;
    reg [31:0] elapsed=0, duration=0;
    wire [9:0] pixels;
    reg [63:0] scaled;
    reg [9:0] expected;
    integer song, sample, checks=0;
    always #5 clk=~clk;
    song_progress dut(.clk(clk),.reset(reset),.frame_tick(frame_tick),
        .elapsed_ms(elapsed),.duration_ms(duration),.pixels(pixels));

    task check_progress;
        input [31:0] time_ms, length_ms;
        begin
            if(length_ms==0 || time_ms<=1400) expected=0;
            else if(time_ms-1400>=length_ms) expected=512;
            else begin
                scaled=time_ms-1400;
                expected=(scaled*512)/length_ms;
            end
            @(negedge clk);
            elapsed=time_ms; duration=length_ms; frame_tick=1;
            @(negedge clk); frame_tick=0;
            repeat(12) @(negedge clk);
            if(pixels !== expected) begin
                $display("FAIL progress: elapsed=%0d duration=%0d pixels=%0d expected=%0d",
                    time_ms,length_ms,pixels,expected); $stop;
            end
            checks=checks+1;
        end
    endtask

    initial begin
        repeat(3) @(negedge clk); reset=0;
        check_progress(0,262177);
        check_progress(1399,262177);
        check_progress(1400,262177);
        for(song=0;song<3;song=song+1) begin
            case(song)
                0: duration=262177;
                1: duration=173425;
                2: duration=158065;
            endcase
            // Sweep from start through all fill positions and past the end.
            for(sample=0;sample<=513;sample=sample+1)
                check_progress(1400+(duration*sample)/512,duration);
        end
        check_progress(1401,1);
        check_progress(1500,0);
        check_progress(32'h7fffffff,32'hffffffff);
        check_progress(32'hffffffff,32'hffffffff);
        check_progress(1400+500,1000);
        // A paused session keeps elapsed time fixed across frames.
        repeat(3) check_progress(1900,1000);
        // A restart and song change must allow progress to go backwards.
        check_progress(1400,158065);
        check_progress(1400+158065,158065);
        @(negedge clk); reset=1;
        @(negedge clk);
        if(pixels!==0) $stop;
        reset=0;
        // Inputs are captured once per frame, not continuously displayed.
        elapsed=1900; duration=1000; frame_tick=1;
        @(negedge clk); frame_tick=0; elapsed=0; duration=1;
        repeat(12) @(negedge clk);
        if(pixels!==256) $stop;
        repeat(20) @(negedge clk);
        if(pixels!==256) $stop;
        $display("PASS: progress ratio, all songs, lead-in, pause, completion, reset and frame snapshots (%0d checks)",checks);
        $finish;
    end
endmodule
