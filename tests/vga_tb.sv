`timescale 1ns / 1ps
`default_nettype none

module vga_tb;
    reg clk = 1'b0;
    reg btnC = 1'b0;
    wire hsync, vsync;
    wire [3:0] red, green, blue;
    integer mx = 0;
    integer my = 0;
    integer phase = 0;
    integer frames = 0;
    integer visible_pixels = 0;
    integer hsync_pixels = 0;
    integer vsync_pixels = 0;
    integer checks = 0;
    reg sampled_reset;
    reg sampled_tick;
    reg expected_visible;
    reg [11:0] expected_color;

    always #5 clk = ~clk;

    veribeat dut (
        .clk(clk), .btnC(btnC), .Hsync(hsync), .Vsync(vsync),
        .vgaRed(red), .vgaGreen(green), .vgaBlue(blue)
    );

    // Independent raster model, checked at every 100 MHz edge. This also
    // checks that coordinates are held during all three non-pixel cycles.
    always begin
        @(posedge clk);
        sampled_reset = dut.reset;
        sampled_tick = dut.pixel_tick;
        if (sampled_reset) begin
            mx = 0;
            my = 0;
            phase = 0;
            visible_pixels = 0;
            hsync_pixels = 0;
            vsync_pixels = 0;
        end else begin
            if (sampled_tick !== (phase == 3))
                $fatal(1, "Pixel enable is not one cycle in four");
            phase = (phase + 1) % 4;
            if (sampled_tick) begin
                if (mx < 640 && my < 480) visible_pixels++;
                if (mx >= 656 && mx < 752) hsync_pixels++;
                if (my >= 490 && my < 492) vsync_pixels++;
                if (mx == 799 && my == 524) begin
                    if (visible_pixels != 307200 || hsync_pixels != 50400 ||
                        vsync_pixels != 1600)
                        $fatal(1, "Incorrect frame pixel/sync totals");
                    visible_pixels = 0;
                    hsync_pixels = 0;
                    vsync_pixels = 0;
                    frames++;
                end
                if (mx == 799) begin
                    mx = 0;
                    my = (my + 1) % 525;
                end else mx++;
            end
        end
        #1;
        if (dut.x !== mx || dut.y !== my)
            $fatal(1, "Coordinate mismatch: expected %0d,%0d got %0d,%0d",
                   mx, my, dut.x, dut.y);
        expected_visible = !dut.reset && mx < 640 && my < 480;
        if (dut.video_on !== expected_visible)
            $fatal(1, "Visible region mismatch");
        if (hsync !== (dut.reset || !(mx >= 656 && mx < 752)))
            $fatal(1, "Horizontal sync mismatch");
        if (vsync !== (dut.reset || !(my >= 490 && my < 492)))
            $fatal(1, "Vertical sync mismatch");
        if (dut.frame_tick !== (!dut.reset && dut.pixel_tick && mx == 799 && my == 524))
            $fatal(1, "Frame enable mismatch");

        case (mx / 80)
            0: expected_color = 12'hFFF;
            1: expected_color = 12'hFF0;
            2: expected_color = 12'h0FF;
            3: expected_color = 12'h0F0;
            4: expected_color = 12'hF0F;
            5: expected_color = 12'hF00;
            6: expected_color = 12'h00F;
            default: expected_color = 12'h000;
        endcase
        if (mx == 0 || mx == 639 || my == 0 || my == 479)
            expected_color = 12'hFFF;
        if (!expected_visible) expected_color = 12'h000;
        if ({red, green, blue} !== expected_color)
            $fatal(1, "Color/blanking mismatch at %0d,%0d", mx, my);
        checks++;
    end

    initial begin
        // Startup without pressing reset must work (FPGA initialization).
        wait (frames == 2);
        repeat (12345) @(negedge clk);
        // Exercise an external reset in the middle of a frame, off clock edge.
        #2 btnC = 1'b1;
        #1;
        if (dut.reset !== 1'b1 || dut.pixel_tick !== 1'b0 ||
            {red, green, blue} !== 12'h000 || !hsync || !vsync)
            $fatal(1, "Reset did not immediately blank video and suppress ticks");
        repeat (4) @(negedge clk);
        #2 btnC = 1'b0;
        @(posedge clk); #1;
        if (dut.reset !== 1'b1) $fatal(1, "Reset released too early");
        @(posedge clk); #1;
        if (dut.reset !== 1'b0) $fatal(1, "Reset did not release after two clocks");
        wait (frames == 3);
        @(negedge clk);
        $display("PASS: %0d complete frames, %0d system cycles; startup, reset, divider, coordinates, sync, RGB, blanking", frames, checks);
        $finish;
    end

    initial begin
        #60000000;
        $fatal(1, "Simulation timeout");
    end
endmodule

`default_nettype wire
