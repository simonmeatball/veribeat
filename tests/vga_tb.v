`timescale 1ns / 1ps
`default_nettype none

// Test the timing modules directly. The reference raster is independent of
// the counters in vga, and RGB encodes coordinates to expose pixel shifts.
module vga_tb;
    reg clk=0, reset_button=0;
    wire reset, pixel_tick, visible, frame_tick, hsync,vsync;
    wire [9:0] x,y;
    wire [3:0] red,green,blue;
    wire [11:0] pattern={x[3:0],y[3:0],x[7:4]^y[7:4]};
    integer mx=0,my=0,phase=0,frames=0,pixels=0,cycles=0;
    reg [11:0] expected_rgb;
    reg expected_hsync,expected_vsync;
    reg sampled_reset,sampled_tick;
    always #5 clk=~clk;
    clock clocks(clk,reset_button,reset,pixel_tick);
    vga dut(clk,reset,pixel_tick,pattern[11:8],pattern[7:4],pattern[3:0],
            x,y,visible,frame_tick,hsync,vsync,red,green,blue);

    task fail;
        input [511:0] reason;
        begin $display("FAIL VGA: %0s at %0t",reason,$time); $stop; end
    endtask
    always begin
        @(posedge clk);
        sampled_reset=reset;
        sampled_tick=pixel_tick;
        if(sampled_reset) begin
            mx=0; my=0; phase=0; frames=0; pixels=0;
            expected_rgb=0; expected_hsync=1; expected_vsync=1;
        end else begin
            if(pixel_tick !== (phase==3)) fail("pixel enable phase");
            if(x !== mx || y !== my) fail("coordinates");
            if(visible !== (mx<640 && my<480)) fail("visible area");
            if(frame_tick !== (pixel_tick && mx==799 && my==524)) fail("frame boundary");
            if(pixel_tick) begin
                expected_rgb=mx<640 && my<480 ? {mx[3:0],my[3:0],mx[7:4]^my[7:4]} : 12'b0;
                expected_hsync=!(mx>=656 && mx<752);
                expected_vsync=!(my>=490 && my<492);
                if(mx<640 && my<480) pixels=pixels+1;
                if(mx==799) begin
                    mx=0;
                    if(my==524) begin
                        my=0; frames=frames+1;
                        if(pixels!=307200) fail("visible pixel count");
                        pixels=0;
                    end else my=my+1;
                end else mx=mx+1;
            end
            phase=(phase+1)%4;
        end
        #1;
        if({red,green,blue} !== expected_rgb || hsync !== expected_hsync || vsync !== expected_vsync)
            fail("registered RGB/sync alignment or blanking");
        if(x !== mx || y !== my) fail("counter update");
        cycles=cycles+1;
        if(frames==3) begin
            $display("PASS: three VGA frames, reset, coordinates, frame enable, blanking and registered RGB/sync (%0d cycles)",cycles);
            $finish;
        end
    end
    initial begin
        // Exercise clock-synchronous assertion during a partial frame.
        repeat(10000) @(negedge clk);
        #2 reset_button=1;
        #1;
        if(reset !== 0) fail("reset asserted between clock edges");
        @(posedge clk); #1; if(reset !== 0) fail("reset asserted before synchronization");
        @(posedge clk); #1;
        if(reset !== 1 || pixel_tick !== 0) fail("reset assertion");
        repeat(3) @(negedge clk);
        #2 reset_button=0;
        @(posedge clk); #1; if(reset !== 1) fail("reset released early");
        @(posedge clk); #1; if(reset !== 0) fail("reset release");
    end
endmodule
`default_nettype wire
