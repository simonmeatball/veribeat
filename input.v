`timescale 1ns / 1ps
`default_nettype none

// Digilent PmodKYPD (16-key matrix) scanner.
//
// Keypad layout (pin numbers are on the Pmod header):
//               COL1(4) COL2(3) COL3(2) COL4(1)
//     ROW1(10)    1       2       3       A
//     ROW2(9)     4       5       6       B
//     ROW3(8)     7       8       9       C
//     ROW4(7)     0       F       E       D
//
// Wire header pin 1..4 to cols[0..3] and pin 7..10 to rows[0..3], so
// cols[3] = COL1 and rows[3] = ROW1 (same order as Digilent's demo).
//
// One column is pulled low at a time; the others are released (high-Z) so two
// keys in the same row never short two driven outputs. The Pmod pulls the rows
// high, so a pressed key reads 0 on its row while its column is selected.
// Rows are sampled at the end of each column's slot, leaving the lines the
// whole slot to settle.
//
// keys[h] is high while the key labelled with hex digit h is held, e.g.
// keys[4'hA]. A new state is accepted only when two consecutive full sweeps
// agree, which filters contact bounce (about 2 sweeps = 8 ms of latency at
// the default rate). pressed/released pulse high for one clk cycle.
// Three keys at the corners of a rectangle can make the fourth corner appear
// pressed (ghosting); the keypad has no diodes, so this cannot be avoided.
//
// lane_press[i] is pressed[] for the key chosen as lane i (bit 0 = leftmost
// lane). By default the lanes are the bottom row, 0 F E D, left to right.
module keypad #(
    parameter integer COL_CYCLES = 100_000,  // 100 MHz / 100,000 = 1 ms per column
    parameter [3:0] LANE0_KEY = 4'h0,
    parameter [3:0] LANE1_KEY = 4'hF,
    parameter [3:0] LANE2_KEY = 4'hE,
    parameter [3:0] LANE3_KEY = 4'hD
) (
    input  wire        clk,                  // Basys 3: 100 MHz
    input  wire        reset,
    input  wire [3:0]  rows,
    output wire [3:0]  cols,
    output reg  [15:0] keys,
    output reg  [15:0] pressed,
    output reg  [15:0] released,
    output wire [3:0]  lane_press
);
    reg [$clog2(COL_CYCLES)-1:0] scan_timer;
    reg [1:0] col_sel;                       // 0..3 = COL1..COL4
    (* ASYNC_REG = "TRUE" *) reg [3:0] rows_meta, rows_sync;
    reg [15:0] sweep;                        // latest full scan
    reg [15:0] prev_sweep;
    reg sweep_done;

    initial begin
        scan_timer = 0;
        col_sel = 0;
        rows_meta = 4'hF;
        rows_sync = 4'hF;
        sweep = 0;
        prev_sweep = 0;
        sweep_done = 0;
        keys = 0;
        pressed = 0;
        released = 0;
    end

    // Drive only the selected column low: COL1 is cols[3], COL4 is cols[0].
    assign cols[3] = (col_sel == 2'd0) ? 1'b0 : 1'bz;
    assign cols[2] = (col_sel == 2'd1) ? 1'b0 : 1'bz;
    assign cols[1] = (col_sel == 2'd2) ? 1'b0 : 1'bz;
    assign cols[0] = (col_sel == 2'd3) ? 1'b0 : 1'bz;

    // Bit selects of a register, so each lane pulse is glitch-free and one
    // clk cycle long, once per debounced press.
    assign lane_press = {pressed[LANE3_KEY], pressed[LANE2_KEY],
                         pressed[LANE1_KEY], pressed[LANE0_KEY]};

    // The keypad is asynchronous to clk; two flip-flops avoid metastability.
    always @(posedge clk) begin
        rows_meta <= rows;
        rows_sync <= rows_meta;
    end

    always @(posedge clk) begin
        sweep_done <= 1'b0;
        pressed <= 0;
        released <= 0;

        if (reset) begin
            scan_timer <= 0;
            col_sel <= 0;
            sweep <= 0;
            prev_sweep <= 0;
            keys <= 0;
        end else begin
            if (scan_timer == COL_CYCLES - 1) begin
                scan_timer <= 0;
                col_sel <= col_sel + 1'b1;
                if (col_sel == 2'd3) sweep_done <= 1'b1;

                // ~rows_sync is {ROW1, ROW2, ROW3, ROW4} with 1 = pressed.
                case (col_sel)
                    2'd0: {sweep[4'h1], sweep[4'h4], sweep[4'h7], sweep[4'h0]} <= ~rows_sync;
                    2'd1: {sweep[4'h2], sweep[4'h5], sweep[4'h8], sweep[4'hF]} <= ~rows_sync;
                    2'd2: {sweep[4'h3], sweep[4'h6], sweep[4'h9], sweep[4'hE]} <= ~rows_sync;
                    2'd3: {sweep[4'hA], sweep[4'hB], sweep[4'hC], sweep[4'hD]} <= ~rows_sync;
                endcase
            end else begin
                scan_timer <= scan_timer + 1'b1;
            end

            // sweep holds all four columns one cycle after the last sample.
            if (sweep_done) begin
                prev_sweep <= sweep;
                if (sweep == prev_sweep) begin
                    keys <= sweep;
                    pressed <= sweep & ~keys;
                    released <= ~sweep & keys;
                end
            end
        end
    end
endmodule

`default_nettype wire
