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
    reg [11:0] expected_color = 12'h000;
    reg expected_hsync = 1'b1;
    reg expected_vsync = 1'b1;
    integer box_x = 573;
    integer box_y = 414;
    integer dx = 2;
    integer dy = 1;

    always #5 clk = ~clk;

    veribeat #(.START_X(573), .START_Y(414)) dut (
        .clk(clk), .btnC(btnC), .Hsync(hsync), .Vsync(vsync),
        .vgaRed(red), .vgaGreen(green), .vgaBlue(blue)
    );

    // Standard Verilog has no $fatal. Stop on failure; vvp -N turns
    // $stop into a nonzero process exit for command-line test runs.
    task fail;
        input [1279:0] message;
        begin
            $display("FAIL at time %0t: %0s", $time, message);
            $display("Expected x,y=%0d,%0d; actual x,y=%0d,%0d",
                     mx, my, dut.x, dut.y);
            $stop;
            $finish;
        end
    endtask

    // Independent raster model, checked at every 100 MHz edge. This also
    // checks that coordinates are held during all three non-pixel cycles.
    always begin
        @(posedge clk);
        sampled_reset = dut.reset;
        sampled_tick = dut.pixel_tick;
        if (sampled_reset) begin
            mx = 0;
            my = 0;
            box_x = 573;
            box_y = 414;
            dx = 2;
            dy = 1;
            expected_color = 12'h000;
            expected_hsync = 1'b1;
            expected_vsync = 1'b1;
            phase = 0;
            visible_pixels = 0;
            hsync_pixels = 0;
            vsync_pixels = 0;
        end else begin
            if (sampled_tick !== (phase == 3))
                fail("Pixel enable is not one cycle in four");
            phase = (phase + 1) % 4;
            if (sampled_tick) begin
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
                if (mx % 64 == 0 || my % 64 == 0) expected_color = 12'h444;
                if (mx >= box_x && mx < box_x + 64 && my >= box_y && my < box_y + 64)
                    expected_color = 12'hFFF;
                if (mx == 0 || mx == 639 || my == 0 || my == 479)
                    expected_color = 12'hFFF;
                if (!(mx < 640 && my < 480)) expected_color = 12'h000;
                expected_hsync = !(mx >= 656 && mx < 752);
                expected_vsync = !(my >= 490 && my < 492);
                if (mx < 640 && my < 480) visible_pixels = visible_pixels + 1;
                if (mx >= 656 && mx < 752) hsync_pixels = hsync_pixels + 1;
                if (my >= 490 && my < 492) vsync_pixels = vsync_pixels + 1;
                if (mx == 799 && my == 524) begin
                    if (visible_pixels != 307200 || hsync_pixels != 50400 ||
                        vsync_pixels != 1600)
                        fail("Incorrect frame pixel/sync totals");
                    visible_pixels = 0;
                    hsync_pixels = 0;
                    vsync_pixels = 0;
                    frames = frames + 1;
                    box_x = box_x + dx;
                    box_y = box_y + dy;
                    if (box_x >= 575) begin box_x = 575; dx = -2; end
                    if (box_x <= 1) begin box_x = 1; dx = 2; end
                    if (box_y >= 415) begin box_y = 415; dy = -1; end
                    if (box_y <= 1) begin box_y = 1; dy = 1; end
                end
                if (mx == 799) begin
                    mx = 0;
                    my = (my + 1) % 525;
                end else mx = mx + 1;
            end
        end
        #1;
        if (dut.x !== mx || dut.y !== my)
            fail("Coordinate mismatch");
        expected_visible = !dut.reset && mx < 640 && my < 480;
        if (dut.video_on !== expected_visible)
            fail("Visible region mismatch");
        if (hsync !== expected_hsync)
            fail("Horizontal sync mismatch");
        if (vsync !== expected_vsync)
            fail("Vertical sync mismatch");
        if (dut.frame_tick !== (!dut.reset && dut.pixel_tick && mx == 799 && my == 524))
            fail("Frame enable mismatch");

        if ({red, green, blue} !== expected_color)
            fail("Registered color/blanking mismatch");
        if (dut.box_x !== box_x || dut.box_y !== box_y)
            fail("Animation changed outside frame boundary or bounced incorrectly");
        if (dut.CLK_100MHz !== clk || dut.CLK_50MHz !== (phase % 2 == 1) ||
            dut.CLK_25MHz !== (phase >= 2))
            fail("Named clock frequency/duty cycle mismatch");
        checks = checks + 1;
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
            fail("Reset did not immediately blank video and suppress ticks");
        repeat (4) @(negedge clk);
        #2 btnC = 1'b0;
        @(posedge clk); #1;
        if (dut.reset !== 1'b1) fail("Reset released too early");
        @(posedge clk); #1;
        if (dut.reset !== 1'b0) fail("Reset did not release after two clocks");
        wait (frames == 3);
        @(negedge clk);
        $display("PASS: %0d complete frames, %0d system cycles; startup, reset, named clocks, coordinates, registered sync/RGB, blanking, animation/bounce", frames, checks);
        $finish;
    end

    initial begin
        #60000000;
        fail("Simulation timeout");
    end
endmodule

`default_nettype wire
