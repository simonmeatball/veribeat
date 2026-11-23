`timescale 1ns / 1ps
`default_nettype none

module hit_timing_tb;
    reg clk=0, reset=1, frame_tick=0, publish_tick=0;
    reg [31:0] elapsed=0;
    reg [3:0] press=0;
    wire [9:0] address;
    wire enable;
    wire [39:0] data;
    wire front, valid, write_enable, clear_pixel, overrun;
    wire [10:0] write_address, resolved_count;
    reg [10:0] read_address=0;
    wire [1:0] bits, pixel;
    wire [15:0] ages, digits;
    wire [3:0] hit_color, hits;
    wire [10:0] points;
    integer cycles;
    always #5 clk=~clk;
    notes chart(clk,enable,address,data);
    control dut (
        .clk(clk),.reset(reset),.frame_tick(frame_tick),.publish_tick(publish_tick),
        .running(1'b1),.elapsed_ms(elapsed),.lane_press(press),
        .chart_address(address),.chart_enable(enable),.chart_data(data),.chart_note_count(11'd4),
        .front_bank(front),.front_valid(valid),.mask_write(write_enable),
        .mask_clear(clear_pixel),.mask_address(write_address),.mask_bits(bits),
        .pulse_ages(ages),.pulse_hit(hit_color),.hits(hits),
        .resolved_count(resolved_count),.overrun(overrun)
    );
    tile_mask mask(clk,front,write_enable,clear_pixel,write_address,bits,read_address,pixel);
    event_counter tally(clk,reset,hits,points,digits);

    task restart;
        begin
            @(negedge clk); reset=1; press=0;
            repeat(3) @(negedge clk);
            reset=0;
        end
    endtask
    task build;
        input [31:0] time_ms;
        begin
            @(negedge clk); elapsed=time_ms; frame_tick=1;
            @(negedge clk); frame_tick=0;
            cycles=0;
            while(dut.state != dut.READY && cycles < 150000) begin
                @(negedge clk); cycles=cycles+1;
            end
            if(cycles >= 150000) $stop;
            publish_tick=1;
            @(negedge clk); publish_tick=0;
            if(overrun || !valid) $stop;
        end
    endtask
    task check_one_hit;
        begin
            if(points !== 1 || resolved_count !== 1 || dut.resolved[1:0] !== 2'b01 || !hit_color[0]) begin
                $display("FAIL: one press must resolve only the oldest eligible note");
                $stop;
            end
        end
    endtask
    initial begin
        #1;
        chart.chart[0]=40'h8000000000 | (40'd1000 << 2);
        chart.chart[1]=40'h8000000000 | (40'd1120 << 2);
        chart.chart[2]=40'h8000000000 | (40'd1500 << 2) | 1;
        chart.chart[3]=40'h8000000000 | (40'd2000 << 2) | 2;
        restart;
        build(2400);
        read_address={2'd0,9'd433}; #1;
        if(pixel !== 2'b01) begin $display("FAIL: tile center must align with pad center"); $stop; end
        read_address={2'd0,9'd450}; #1; if(pixel !== 2'b11) $stop;
        read_address={2'd0,9'd451}; #1; if(pixel !== 0) $stop;

        @(negedge clk); elapsed=2480; press=1;
        build(2480); // Both notes are eligible. The newer note is closer.
        check_one_hit;
        read_address={2'd0,9'd433}; #1;
        if(pixel[0] !== 1'b1) begin $display("FAIL: second tile disappeared"); $stop; end
        build(2500); // Holding the input cannot consume the next note.
        check_one_hit;
        @(negedge clk); press=0;
        repeat(2) @(negedge clk);
        elapsed=2520; press=1;
        build(2520);
        if(points !== 2 || resolved_count !== 2 || dut.resolved[1:0] !== 2'b11) $stop;

        // A press at the inclusive late boundary is judged at its timestamp,
        // even when it is processed 17 ms later.
        restart;
        elapsed=2560; press=1;
        @(negedge clk); press=0;
        build(2577);
        check_one_hit;

        restart;
        elapsed=2240; press=1;
        build(2240); // Inclusive early boundary.
        check_one_hit;

        restart;
        elapsed=2239; press=1;
        build(2239);
        if(points !== 0 || hit_color[0] !== 0 || resolved_count !== 0) $stop;

        restart;
        elapsed=3061; press=2; // Lane 1 has a single note, now 161 ms late.
        build(3061);
        if(points !== 0 || hit_color[1] !== 0 || dut.resolved[2] !== 1'b1) $stop;
        $display("PASS: centered tiles, overlapping windows, oldest-note consumption, held keys, buffered boundaries and misses");
        $finish;
    end
endmodule
`default_nettype wire
