`timescale 1ns / 1ps

module game_tb;
    reg clk = 0;
    reg reset_button = 1;
    localparam KEYPAD_COL_CYCLES = 50;
    reg [3:0] held_lanes = 0;
    wire [3:0] rows;
    wire [3:0] cols;
    reg frame_enable = 0;
    reg [9:0] pixel_x = 0;
    reg [9:0] pixel_y = 0;

    veribeat #(.KEYPAD_COL_CYCLES(KEYPAD_COL_CYCLES)) dut (
        .clk(clk), .btnC(reset_button), .rows(rows), .cols(cols)
    );

    // The lane keys share the bottom row. A closed switch pulls that row
    // low only when the scanner drives the key's column low.
    assign rows = {3'b111, !((held_lanes[0] && cols[3] === 1'b0) ||
                            (held_lanes[1] && cols[2] === 1'b0) ||
                            (held_lanes[2] && cols[1] === 1'b0) ||
                            (held_lanes[3] && cols[0] === 1'b0))};

    always #5 clk = ~clk;

    task advance;
        input integer count;
        integer step;
        begin
            for (step = 0; step < count; step = step + 1) begin
                @(negedge clk);
                frame_enable = 1;
                @(negedge clk);
                frame_enable = 0;
            end
        end
    endtask

    task set_keys;
        input [3:0] lanes;
        begin
            @(negedge clk);
            held_lanes = lanes;
            // Allow three sweeps, including one that may have started before
            // the key state changed. The one-cycle output has already ended.
            repeat (12 * KEYPAD_COL_CYCLES) @(negedge clk);
            if (dut.game.lane_press !== 4'b0) $stop;
        end
    endtask

    task check_pixel;
        input [9:0] x;
        input [9:0] y;
        input [11:0] expected;
        begin
            pixel_x = x;
            pixel_y = y;
            #1;
            if (dut.video_color !== expected) begin
                $display("FAIL pixel (%0d,%0d): expected %h, got %h",
                         x, y, expected, dut.video_color);
                $stop;
            end
        end
    endtask

    initial begin
        force dut.frame_tick = frame_enable;
        force dut.x = pixel_x;
        force dut.y = pixel_y;
        repeat (4) @(negedge clk);
        reset_button = 0;
        repeat (4) @(negedge clk);

        check_pixel(64, 404, 12'hb8f);
        check_pixel(80, 410, 12'h96e);
        check_pixel(122, 439, 12'hfff); // Bottom stroke of 0.
        check_pixel(258, 439, 12'h324); // Blank bottom right of F.
        check_pixel(386, 439, 12'hfff); // Bottom stroke of E.
        check_pixel(514, 439, 12'h324); // D's bottom-right corner.
        advance(79);
        check_pixel(336, 398, 12'h6ef);
        check_pixel(336, 403, 12'h113);
        advance(1);
        check_pixel(336, 403, 12'h6ef);
        set_keys(4'b0100);
        set_keys(4'b0000);
        advance(1);
        if (dut.game.points !== 1 || dut.game.visible[0] !== 0) $stop;
        check_pixel(334, 430, 12'hfff);
        advance(5);
        check_pixel(329, 430, 12'haaa);
        advance(7);
        check_pixel(329, 430, 12'h113);

        advance(30); // Frame 123, last eligible frame is 124.
        advance(1);
        set_keys(4'b0001);
        set_keys(4'b0000);
        advance(1);
        if (dut.game.points !== 2) $stop;

        advance(35); // Frame 160.
        set_keys(4'b0110);
        advance(1);
        if (dut.game.points !== 4) $stop;
        check_pixel(206, 430, 12'hfff);
        check_pixel(334, 430, 12'hfff);
        advance(44); // Advance through lane 4's unplayed note at frame 200.
        if (dut.game.points !== 4 || dut.game.visible[4] !== 0) $stop;
        check_pixel(462, 430, 12'hf00);
        advance(1);
        check_pixel(461, 430, 12'he00); // Miss ages without retriggering.
        advance(11);
        check_pixel(461, 430, 12'h113);
        advance(68); // Lane 2 stays held through its next note.
        check_pixel(206, 430, 12'hf00);
        if (dut.game.points !== 4) $stop;
        set_keys(4'b0000);
        set_keys(4'b0001);
        set_keys(4'b0000);
        advance(1);
        check_pixel(78, 430, 12'hf00);
        if (dut.game.points !== 4) $stop;

        @(negedge clk);
        reset_button = 1;
        repeat (4) @(negedge clk);
        if (dut.game.points !== 0 || dut.game.pulse_ages !== 16'hcccc) $stop;
        $display("PASS: keypad through VGA game, timing boundary, chord, hold, miss, pulses and reset");
        $finish;
    end
endmodule
