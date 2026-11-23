`timescale 1ns / 1ps
module integration_tb #(
    parameter integer SONG_ID = 0
);
    reg clk=0, reset=1, rx=1;
    wire tx;
    wire [15:0] led;
    wire [3:0] cols;
    reg [3:0] held=0;
    reg [15:0] held_keys=0;
    reg [3:0] rows;
    integer row, column;
    reg [63:0] layout=64'h123A_456B_789C_0FED;
    always @* begin
        rows=4'hf;
        for(row=0;row<4;row=row+1)
            for(column=0;column<4;column=column+1)
                if(held_keys[layout[63-4*(4*row+column) -: 4]] && cols[3-column] === 1'b0)
                    rows[3-row]=0;
    end
    wire [7:0] command;
    wire command_valid;
    integer commands=0;
    reg [31:0] first_target;
    always #5 clk=~clk;
    veribeat #(.KEYPAD_COL_CYCLES(50),.UART_CLKS_PER_BIT(8),.CYCLES_PER_MS(100000),
               .SONG0_FILE("charts/song_0.mem"),.SONG1_FILE("charts/song_1.mem"),
               .SONG2_FILE("charts/song_2.mem")) dut (
        .clk(clk),.btnC(reset),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.btnD(1'b0),
        .RsRx(rx),.RsTx(tx),.rows(rows),.cols(cols),.led(led)
    );
    uart_rx #(.CLKS_PER_BIT(8)) monitor(clk,reset,tx,command,command_valid);
    always @(negedge clk) if(command_valid) begin
        case(commands)
            0: if(command !== "S") $stop;
            1: if(command !== "S") $stop;
            2: if(command !== "L") $stop;
            3: if(command !== 8'd48 + SONG_ID) $stop;
            default: begin end
        endcase
        commands=commands+1;
    end
    task send_ready;
        integer bit_index;
        reg [7:0] value;
        begin
            value="K";
            @(negedge clk); rx=0;
            repeat(8) @(negedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                rx=value[bit_index]; repeat(8) @(negedge clk);
            end
            rx=1; repeat(10) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); reset=0;
        wait(commands==1);
        if(dut.game.running || !dut.game.home) $stop;
        held_keys=16'b1 << (SONG_ID+1);
        repeat(700) @(negedge clk);
        held_keys=0;
        wait(commands==4);
        if(dut.game.running) $stop;
        send_ready;
        wait(dut.game.running);
        // Advance to the first chart note while exercising the real VGA,
        // scanner, UART handshake and bank publish signals.
        case(SONG_ID)
            1: first_target=dut.game.chart.song1.chart[0][33:2]+32'd1400;
            2: first_target=dut.game.chart.song2.chart[0][33:2]+32'd1400;
            default: first_target=dut.game.chart.song0.chart[0][33:2]+32'd1400;
        endcase
        force dut.game.session.elapsed_ms=first_target;
        case(SONG_ID)
            1: held=4'b0001 << dut.game.chart.song1.chart[0][1:0];
            2: held=4'b0001 << dut.game.chart.song2.chart[0][1:0];
            default: held=4'b0001 << dut.game.chart.song0.chart[0][1:0];
        endcase
        held_keys = {held[1],held[2],held[3],12'b0,held[0]};
        wait(dut.game.points==1);
        held=0; held_keys=0;
        wait(dut.game.front_valid);
        if(dut.game.overrun || dut.game.failed || dut.game.misclick_count !== 0 ||
           dut.game.total_score !== 100 || dut.game.combo !== 1 || dut.game.longest_streak !== 1) $stop;
        // A non-lane key during play is a misclick, independent of song selection.
        held_keys=16'h0010;
        wait(dut.game.misclick_count==1);
        if(dut.game.combo !== 0 || dut.game.longest_streak !== 1) $stop;
        held_keys=0;
        // Resolve the rest of the selected chart and display its final stats.
        first_target=dut.game.chart_duration_ms+32'd1900;
        wait(dut.game.finished);
        wait(dut.game.screen==2);
        if(dut.game.points !== 1 || dut.game.miss_count !== dut.game.chart_note_count-1 ||
           dut.game.misclick_count !== 1 || dut.game.overrun || dut.game.total_score !== 100 ||
           dut.game.combo !== 0 || dut.game.longest_streak !== 1) $stop;
        release dut.game.session.elapsed_ms;
        held_keys=16'b1 << (SONG_ID+1);
        wait(dut.game.home);
        repeat(1000) @(negedge clk);
        if(!dut.game.home || dut.game.loading || dut.game.points !== 0 ||
           dut.game.miss_count !== 0 || dut.game.misclick_count !== 0 ||
           dut.game.total_score !== 0 || dut.game.longest_streak !== 0) $stop;
        $display("PASS: song menu, UART, combo scoring, penalties, longest streak, results and restart");
        $finish;
    end
    initial begin #100000000; $display("FAIL integration timeout"); $stop; end
endmodule
