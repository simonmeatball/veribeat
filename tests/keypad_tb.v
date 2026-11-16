`timescale 1ns / 1ps
`default_nettype none
module keypad_tb;
    localparam CC = 50;               // cycles per column; one sweep = 200 cycles
    reg clk = 0, reset = 1;
    reg [15:0] held = 0;              // physical keys, indexed by hex label
    wire [3:0] cols;
    reg  [3:0] rows, rv;
    wire [15:0] keys, pressed, released;
    wire [3:0] lane_press;
    reg  [3:0] lane_prev = 0;
    integer npress [0:15];
    integer nrel [0:15];
    integer nlane [0:3];
    integer i, j, r, c, errors = 0;
    reg [63:0] layout = 64'h123A_456B_789C_0FED;   // row-major, ROW1/COL1 first
    always #5 clk = ~clk;

    keypad #(.COL_CYCLES(CC)) dut (.clk(clk), .reset(reset), .rows(rows), .cols(cols),
        .keys(keys), .pressed(pressed), .released(released), .lane_press(lane_press));

    // Keypad model: a held key ties its row to its column; rows pulled up.
    always @(held or cols) begin
        rv = 4'hF;
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                if (held[layout[63 - 4*(4*r+c) -: 4]] && cols[3-c] === 1'b0) rv[3-r] = 1'b0;
        rows = rv;
    end

    always @(posedge clk) begin
        for (j = 0; j < 16; j = j + 1) begin
            if (pressed[j]) npress[j] = npress[j] + 1;
            if (released[j]) nrel[j] = nrel[j] + 1;
        end
        for (j = 0; j < 4; j = j + 1) if (lane_press[j]) nlane[j] = nlane[j] + 1;
        if (lane_press & lane_prev) begin $display("FAIL lane pulse longer than 1 cycle"); errors = errors + 1; end
        if (lane_press !== {pressed[4'hD], pressed[4'hE], pressed[4'hF], pressed[4'h0]}) begin
            $display("FAIL lane_press=%b", lane_press); errors = errors + 1; end
        lane_prev = lane_press;
        if (!((cols === 4'bzzz0) || (cols === 4'bzz0z) || (cols === 4'bz0zz) || (cols === 4'b0zzz))) begin
            $display("FAIL: cols = %b", cols); errors = errors + 1; end
    end

    task sweeps(input integer n); repeat (n * 4 * CC) @(posedge clk); endtask
    task expect_keys(input [15:0] k);
        if (keys !== k) begin $display("FAIL t=%0t keys=%h want %h", $time, keys, k); errors = errors + 1; end
    endtask

    initial begin
        for (i = 0; i < 16; i = i + 1) begin npress[i] = 0; nrel[i] = 0; end
        for (i = 0; i < 4; i = i + 1) nlane[i] = 0;
        repeat (5) @(posedge clk); reset = 0;
        sweeps(3); expect_keys(0);
        for (i = 0; i < 16; i = i + 1) begin
            held = 16'b1 << i; sweeps(3); expect_keys(held);
            held = 0;          sweeps(3); expect_keys(0);
        end
        for (i = 0; i < 16; i = i + 1)
            if (npress[i] != 1 || nrel[i] != 1) begin
                $display("FAIL key %h press=%0d rel=%0d", i, npress[i], nrel[i]); errors = errors + 1; end
        for (i = 0; i < 4; i = i + 1)
            if (nlane[i] != 1) begin $display("FAIL lane %0d pulses=%0d", i, nlane[i]); errors = errors + 1; end
        // same-row (1, A) and same-column (A, D) chords; all four lanes at once
        held = (16'b1 << 4'h1) | (16'b1 << 4'hA); sweeps(3); expect_keys(held);
        held = (16'b1 << 4'hA) | (16'b1 << 4'hD); sweeps(3); expect_keys(held);
        held = 0; sweeps(3);
        held = 16'hE001; sweeps(3); expect_keys(16'hE001);    // keys 0, D, E, F
        held = 0; sweeps(3); expect_keys(0);
        for (i = 0; i < 4; i = i + 1)
            if (nlane[i] != 2 + (i == 3)) begin $display("FAIL lane %0d chord pulses=%0d", i, nlane[i]); errors = errors + 1; end
        // bounce: lane 0 key chatters for under one sweep, then is held
        for (i = 0; i < 6; i = i + 1) begin held[0] = ~held[0]; repeat (CC / 2 + 7) @(posedge clk); end
        held[0] = 1; sweeps(4); expect_keys(16'h0001);
        if (nlane[0] != 3) begin $display("FAIL bounce gave %0d lane-0 pulses", nlane[0] - 2); errors = errors + 1; end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        $finish;
    end
endmodule
