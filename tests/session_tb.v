`timescale 1ns / 1ps
module session_tb;
    reg clk=0, reset=1;
    reg [3:0] buttons=0;
    reg ready=0, error=0, busy=0;
    wire load,play,stop,pause,resume,game_reset,running,paused,finished,failed;
    wire [31:0] elapsed;
    integer starts=0, stops=0, loads=0;
    reg [31:0] paused_time;
    always #5 clk=~clk;
    game_session #(.CYCLES_PER_MS(2),.PRE_ROLL_MS(40),.DURATION_MS(200),.NOTE_COUNT(0)) dut (
        .clk(clk),.reset(reset),.buttons(buttons),.audio_ready(ready),.audio_error(error),
        .audio_busy(busy),.resolved_count(11'd0),.cmd_load(load),.cmd_play(play),
        .cmd_stop(stop),.cmd_pause(pause),.cmd_resume(resume),.game_reset(game_reset),
        .running(running),.elapsed_ms(elapsed),.paused(paused),.finished(finished),.failed(failed)
    );
    always @(posedge clk) begin
        if(play) starts=starts+1;
        if(stop) stops=stops+1;
        if(load) loads=loads+1;
    end
    task button_press;
        input [3:0] b;
        begin
            @(negedge clk); buttons=b;
            repeat(30) @(negedge clk);
            buttons=0;
            repeat(30) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        repeat(40) @(negedge clk);
        if(loads != 1 || running || elapsed != 0) $stop;
        ready=1;
        wait(elapsed==60);
        button_press(4'b0010);
        if(!paused || starts != 1) $stop;
        paused_time=elapsed;
        repeat(30) @(negedge clk);
        if(elapsed != paused_time) $stop;
        button_press(4'b0100);
        if(!running) $stop;
        wait(finished);
        if(starts != 1) $stop;
        ready=0;
        button_press(4'b0001);
        if(loads != 2 || elapsed != 0 || running) $stop;
        error=1;
        repeat(20) @(negedge clk);
        if(!failed) $stop;
        $display("PASS: load handshake, pre-roll, play, pause, resume, finish, restart and audio failure");
        $finish;
    end
    initial begin #100000; $display("FAIL session timeout"); $stop; end
endmodule
