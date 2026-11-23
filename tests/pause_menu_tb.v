`timescale 1ns / 1ps
module pause_menu_tb;
    reg clk=0,reset=1,ready=0;
    reg [3:0] buttons=0;
    reg [2:0] keys=0;
    reg any_key=0;
    wire home,loading,running,paused,game_reset;
    wire load,play,stop,pause,resume;
    wire [1:0] song,countdown;
    wire [31:0] elapsed;
    integer loads=0,plays=0,stops=0,pauses=0,resumes=0,resets=0;
    integer button;
    reg [31:0] frozen_time;
    time mark;
    always #5 clk=~clk;
    game_session #(.CYCLES_PER_MS(2),.PRE_ROLL_MS(40)) dut(
        .clk(clk),.reset(reset),.buttons(buttons),.audio_ready(ready),
        .audio_error(1'b0),.audio_busy(1'b0),.resolved_count(11'd0),
        .chart_note_count(11'd1),.chart_duration_ms(32'd100000),
        .song_press(keys),.any_key(any_key),.song_index(song),
        .home(home),.loading(loading),.cmd_load(load),.cmd_play(play),
        .cmd_stop(stop),.cmd_pause(pause),.cmd_resume(resume),
        .game_reset(game_reset),.running(running),.elapsed_ms(elapsed),
        .paused(paused),.countdown(countdown),.finished(),.failed());
    always @(negedge clk) begin
        if(load) loads=loads+1;
        if(play) plays=plays+1;
        if(stop) stops=stops+1;
        if(pause) pauses=pauses+1;
        if(resume) resumes=resumes+1;
        if(game_reset) resets=resets+1;
        if(countdown!=0 && (running || elapsed!=0 || play)) begin
            $display("FAIL: gameplay/audio advanced during countdown"); $stop;
        end
    end
    task key;
        input [2:0] value;
        begin
            @(negedge clk); keys=value; any_key=1;
            @(negedge clk); keys=0; any_key=0;
            @(negedge clk);
        end
    endtask
    task pause_button;
        input [3:0] mask;
        begin
            @(negedge clk); buttons=mask;
            repeat(30) @(negedge clk);
            buttons=0;
            repeat(30) @(negedge clk);
            if(!paused) $stop;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); reset=0;
        repeat(4) @(negedge clk);
        key(2); // Select song 1.
        wait(loads==1); ready=1;
        wait(elapsed==60);
        pause_button(4'b0010);
        if(pauses!=1 || song!=1) $stop;
        frozen_time=elapsed;
        repeat(100) @(negedge clk);
        if(elapsed!=frozen_time) $stop;
        // A non-menu keypad key does nothing while paused.
        @(negedge clk); any_key=1;
        @(negedge clk); any_key=0;
        if(!paused) $stop;
        key(1);
        if(!running || resumes!=1 || elapsed<frozen_time || song!=1) $stop;
        // All four outer buttons pause. Further outer presses must keep
        // the game paused, without restarting, stopping, or resuming it.
        for(button=0;button<4;button=button+1) begin
            pause_button(4'b0001 << button);
            frozen_time=elapsed;
            pause_button(4'b1111);
            if(elapsed!=frozen_time || pauses!=button+2 || resumes!=button+1 ||
               loads!=1 || song!=1 || stops!=2) $stop;
            key(1);
            if(!running || resumes!=button+2) $stop;
        end
        pause_button(4'b0010);
        ready=0;
        key(2); // Restart the selected song, preserving the selection.
        wait(loads==2);
        repeat(20) @(negedge clk);
        if(!loading || countdown!=0 || elapsed!=0 || song!=1) $stop;
        ready=1;
        wait(countdown==3); mark=$time;
        wait(countdown==2);
        if($time-mark!=20000) $stop;
        mark=$time;
        wait(countdown==1);
        if($time-mark!=20000) $stop;
        mark=$time;
        wait(countdown==0);
        if($time-mark!=20000 || !running || plays!=1) $stop;
        wait(elapsed==60);
        if(plays!=2) $stop;
        pause_button(4'b0010);
        key(4); // Return home without selecting song 2 with the same press.
        repeat(40) @(negedge clk);
        if(!home || loading || elapsed!=0 || loads!=2 || song!=1 || resets<3) $stop;
        repeat(100) @(negedge clk);
        if(!home || loads!=2) $stop;
        // A fresh press selects a song normally after returning home.
        ready=0; key(1);
        wait(loads==3); ready=1;
        wait(running);
        if(countdown!=0 || song!=0) $stop;
        // Pausing during lead-in must not send a hold/resume for unstarted audio.
        pause_button(4'b0010);
        if(pauses!=7) $stop;
        key(1);
        if(!running || resumes!=5) $stop;
        // Restart remains a keypad menu choice.
        pause_button(4'b0001);
        ready=0; key(2);
        wait(loads==4); ready=1;
        wait(countdown==3);
        if(song!=0 || elapsed!=0 || stops<5) $stop;
        // The reset driven by the center button also cancels a countdown
        // and returns the entire session to its startup state.
        @(negedge clk); reset=1;
        repeat(3) @(negedge clk);
        if(!home || running || paused || loading || countdown!=0 ||
           song!=0 || elapsed!=0 || !game_reset) $stop;
        reset=0;
        repeat(5) @(negedge clk);
        if(!home || running || countdown!=0) $stop;
        $display("PASS: all four outer buttons pause, keypad menu actions, audio commands and exact 3-2-1 countdown");
        $finish;
    end
    initial begin #200000; $display("FAIL pause-menu timeout"); $stop; end
endmodule
