`timescale 1ns / 1ps
module chart_size_case #(parameter COUNT=0)(output reg done=0);
    reg clk=0, reset=1, frame_tick=0, publish_tick=0;
    reg [31:0] elapsed=2400;
    reg [3:0] press=0;
    wire [9:0] address;
    wire enable;
    wire [39:0] data;
    wire [3:0] hits;
    wire [10:0] points, resolved_count;
    wire [15:0] digits;
    wire overrun;
    integer i;
    reg [31:0] target;
    always #5 clk=~clk;
    notes chart(clk,enable,address,data);
    control dut (
        .clk(clk),.reset(reset),.frame_tick(frame_tick),.publish_tick(publish_tick),
        .running(1'b1),.elapsed_ms(elapsed),.lane_press(press),
        .chart_address(address),.chart_enable(enable),.chart_data(data),.chart_note_count(COUNT[10:0]),
        .front_bank(),.front_valid(),.mask_write(),.mask_clear(),.mask_address(),.mask_bits(),
        .pulse_ages(),.pulse_hit(),.hits(hits),.resolved_count(resolved_count),.overrun(overrun)
    );
    event_counter tally(clk,reset,hits,points,digits);
    task start_frame;
        begin
            @(negedge clk); frame_tick=1;
            @(negedge clk); frame_tick=0;
        end
    endtask
    task publish;
        begin
            wait(dut.state==dut.READY);
            @(negedge clk); publish_tick=1;
            @(negedge clk); publish_tick=0;
            if(overrun) $stop;
        end
    endtask
    initial begin
        #1;
        for(i=0;i<COUNT;i=i+1) begin
            target=1000+i*50;
            chart.chart[i]=40'h8000000000 | ({8'b0,target} << 2) | (i%4);
        end
        repeat(3) @(negedge clk); reset=0;
        start_frame;
        // A pulse received during the scan must survive for the next frame.
        repeat(100) @(negedge clk); press=1;
        @(negedge clk); press=0;
        publish;
        if(points !== 0) $stop;
        start_frame;
        publish;
        if(points !== (COUNT==0 ? 0 : 1)) $stop;
        elapsed=10000;
        start_frame;
        publish;
        if(resolved_count !== COUNT) $stop;
        // Force an incomplete frame at the deadline. The previous bank stays.
        start_frame;
        @(negedge clk); publish_tick=1;
        @(negedge clk); publish_tick=0;
        if(!overrun) $stop;
        done=1;
    end
endmodule
module chart_sizes_tb;
    wire zero_done, eight_done;
    chart_size_case #(.COUNT(0)) empty(zero_done);
    chart_size_case #(.COUNT(8)) eight_notes(eight_done);
    initial begin
        wait(zero_done && eight_done);
        $display("PASS: empty/eight-note charts, mid-scan press buffering, expiry and overrun detection");
        $finish;
    end
    initial begin #2000000; $display("FAIL sizes timeout"); $stop; end
endmodule
