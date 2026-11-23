`timescale 1ns / 1ps
`default_nettype none

// Exercise the actual ROM, sequential judge, mask banks, renderer and score.
module game_tb;
    reg clk=0, reset=1, frame_tick=0, publish_tick=0;
    reg [31:0] elapsed=0;
    reg [3:0] press=0;
    wire [9:0] address;
    wire enable;
    wire [39:0] data;
    wire front, valid, write_enable, clear_pixel, overrun;
    wire [10:0] write_address, resolved_count;
    wire [1:0] bits, pixel;
    reg [10:0] read_address=0;
    wire [15:0] ages, digits;
    wire [3:0] hit_color, hits;
    wire [10:0] points, miss_count;
    wire note_miss;
    wire [3:0] misclicks;
    wire [10:0] misclick_count;
    integer i, group, cycles;
    reg [31:0] target;
    reg [9:0] x=0, y=0;
    wire [11:0] color;
    always #5 clk=~clk;

    notes chart(clk, enable, address, data);
    control dut (
        .clk(clk), .reset(reset), .frame_tick(frame_tick), .publish_tick(publish_tick),
        .running(1'b1), .elapsed_ms(elapsed), .lane_press(press),
        .chart_address(address), .chart_enable(enable), .chart_data(data),.chart_note_count(11'd1024),
        .front_bank(front), .front_valid(valid), .mask_write(write_enable),
        .mask_clear(clear_pixel), .mask_address(write_address), .mask_bits(bits),
        .pulse_ages(ages), .pulse_hit(hit_color), .hits(hits),
        .resolved_count(resolved_count), .overrun(overrun),
        .note_miss(note_miss), .misclicks(misclicks)
    );
    tile_mask mask(clk,front,write_enable,clear_pixel,write_address,bits,read_address,pixel);
    event_counter tally(clk,reset,hits,points,digits);
    event_counter missed(.clk(clk),.reset(reset),.hits({3'b0,note_miss}),.points(miss_count),.digits());
    event_counter invalid_presses(.clk(clk),.reset(reset),.hits(misclicks),.points(misclick_count),.digits());
    display renderer(x,y,valid ? pixel : 2'b0,ages,hit_color,color);

    task build_frame;
        input [31:0] time_ms;
        input [3:0] lanes;
        begin
            @(negedge clk); elapsed=time_ms; press=lanes; frame_tick=1;
            @(negedge clk); frame_tick=0; press=0;
            cycles=0;
            while (dut.state != dut.READY && cycles < 150000) begin
                @(negedge clk); cycles=cycles+1;
            end
            if (cycles >= 150000) begin $display("FAIL frame deadline"); $stop; end
            publish_tick=1;
            @(negedge clk); publish_tick=0;
            if (overrun || !valid) $stop;
        end
    endtask
    task restart;
        begin
            @(negedge clk); reset=1;
            repeat(3) @(negedge clk);
            reset=0;
        end
    endtask
    initial begin
        #1;
        // Dense chart: all 1024 notes are on screen at once.
        for(i=0;i<1024;i=i+1) begin
            target=3000+i/4;
            chart.chart[i]=(40'h8000000000 | ({8'b0,target} << 2) | (i%4));
        end
        restart;
        build_frame(4400,0);
        $display("Dense 1024-note frame completed in %0d cycles",cycles);
        read_address={2'd0,9'd403}; #1;
        if(pixel !== 2'b11) $stop;
        read_address={2'd0,9'd380}; #1;
        if(pixel[0] !== 1'b1) $stop;
        build_frame(4500,4'b1111); // one oldest eligible note per pressed lane
        if(points !== 4 || resolved_count !== 4 || dut.resolved[3:0] !== 4'hf) $stop;
        build_frame(5000,0);
        if(resolved_count !== 1024 || points !== 4 || miss_count !== 1020) $stop;

        // A full chart with four-note chords every 500 ms.
        for(i=0;i<1024;i=i+1) begin
            target=3000+(i/4)*500;
            chart.chart[i]=(40'h8000000000 | ({8'b0,target} << 2) | (i%4));
        end
        restart;
        build_frame(4239,4'b1111); // 161 ms early
        if(points !== 0 || hit_color !== 0 || misclick_count !== 4) $stop;
        for(group=0;group<256;group=group+1) begin
            // Alternate inclusive early/late boundaries and exact hits.
            target=4400+group*500;
            if(group%3==0) target=target-160;
            if(group%3==1) target=target+160;
            build_frame(target,4'b1111);
            if(points !== (group+1)*4 || resolved_count !== (group+1)*4) begin
                $display("FAIL score at chord %0d: %0d",group,points); $stop;
            end
        end
        if(points !== 1024 || digits !== 16'h1024 || miss_count !== 0 || misclick_count !== 4) $stop;
        // Last address was fetched and scored. All resolved masks are empty.
        read_address={2'd3,9'd403}; #1; if(pixel !== 0) $stop;
        x=78; y=430; #1; if(color !== 12'hfff) $stop;
        restart;
        build_frame(4561,0); // 161 ms late: four misses
        if(points !== 0 || resolved_count !== 4) $stop;
        x=78; y=430; #1; if(color !== 12'hf00) $stop;
        $display("PASS: 1024 notes, dense masks, oldest-note selection, boundaries, score 1024, white/red effects");
        $finish;
    end
endmodule
`default_nettype wire
