`timescale 1ns / 1ps
module session_tb;
    reg clk=0, reset=1;
    reg [3:0] buttons=0;
    reg [2:0] song_press=0;
    reg any_key=0;
    reg ready=0, error=0, busy=0;
    wire load,play,stop,pause,resume,game_reset,running,paused,finished,failed,home,loading;
    wire [1:0] song;
    wire [31:0] elapsed;
    integer starts=0, loads=0, selection;
    reg [31:0] paused_time;
    always #5 clk=~clk;
    game_session #(.CYCLES_PER_MS(2),.PRE_ROLL_MS(40)) dut (
        .clk(clk),.reset(reset),.buttons(buttons),.audio_ready(ready),.audio_error(error),
        .audio_busy(busy),.resolved_count(11'd0),.chart_note_count(11'd0),
        .chart_duration_ms(32'd200),.song_press(song_press),.any_key(any_key),
        .song_index(song),.home(home),.loading(loading),.cmd_load(load),.cmd_play(play),
        .cmd_stop(stop),.cmd_pause(pause),.cmd_resume(resume),.game_reset(game_reset),
        .running(running),.elapsed_ms(elapsed),.paused(paused),.finished(finished),.failed(failed)
    );
    always @(posedge clk) begin
        if(play) starts=starts+1;
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
        if(loads != 0 || !home || running) $stop;
        for(selection=0;selection<3;selection=selection+1) begin
            ready=0;
            @(negedge clk); song_press=1<<selection; any_key=1;
            @(negedge clk); song_press=0; any_key=0;
            repeat(40) @(negedge clk);
            if(loads != selection+1 || song !== selection || !loading || running) $stop;
            ready=1;
            wait(elapsed==60);
            if(selection==0) begin
                button_press(4'b0010);
                if(!paused || starts != 1) $stop;
                paused_time=elapsed;
                repeat(30) @(negedge clk);
                if(elapsed != paused_time) $stop;
                button_press(4'b0100);
                if(!running) $stop;
            end
            wait(finished);
            if(starts != selection+1) $stop;
            // A numeric key returns home and cannot also start a song.
            @(negedge clk); song_press=2; any_key=1;
            @(negedge clk); song_press=0; any_key=0;
            repeat(30) @(negedge clk);
            if(!home || running || loads != selection+1 || elapsed != 0) $stop;
        end
        ready=0;
        @(negedge clk); song_press=1;
        @(negedge clk); song_press=0;
        repeat(40) @(negedge clk); error=1;
        repeat(20) @(negedge clk);
        if(!failed) $stop;
        button_press(4'b0100);
        if(!home) $stop;
        $display("PASS: home, all song selections, audio handshake, pause/resume, results return and errors");
        $finish;
    end
    initial begin #150000; $display("FAIL session timeout"); $stop; end
endmodule
