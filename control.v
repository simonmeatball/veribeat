`timescale 1ns / 1ps
`default_nettype none

module control (
    input  wire        clk,
    input  wire        reset,
    input  wire        frame_tick,
    input  wire [3:0]  lane_press,
    input  wire [15:0] lanes,
    input  wire [79:0] targets,
    output wire [7:0]  visible,
    output reg  [71:0] tile_bottoms,
    output reg  [15:0] pulse_ages,
    output reg  [3:0]  pulse_hit,
    output reg  [3:0]  hits
);
    localparam [8:0] HIT_Y = 9'd404;
    localparam [8:0] FALL_STEP = 9'd5;
    localparam [8:0] FIELD_TOP = 9'd48;
    // Render the note once its bottom reaches the visible field.
    localparam [9:0] VISIBLE_LEAD = (HIT_Y - FIELD_TOP - 1) / FALL_STEP;
    localparam [9:0] WINDOW = 10'd6;
    localparam [2:0] NO_MATCH = WINDOW + 1;
    localparam PULSE_FRAMES = 12;
    localparam LAST_FRAME = 340;

    reg [9:0] frame;
    reg [7:0] resolved;
    wire [7:0] entered;
    assign visible = entered & ~resolved;
    reg [3:0] previous_press;
    reg [3:0] pending_press;
    // Catch rising edges at 100 MHz, including an edge on frame_tick itself.
    wire [3:0] pressed = lane_press & ~previous_press;
    wire [3:0] frame_press = pending_press | pressed;

    reg [7:0] resolved_next;
    reg [3:0] misses;
    wire [7:0] in_window;
    wire [7:0] at_deadline;
    wire [23:0] distances;

    genvar note;
    generate
        for (note = 0; note < 8; note = note + 1) begin : note_state
            wire [9:0] target = targets[10*note +: 10];
            wire [10:0] deadline = {1'b0, target} + {1'b0, WINDOW};
            wire [9:0] earliest = target >= WINDOW ? target - WINDOW : 10'd0;
            assign in_window[note] = frame >= earliest && {1'b0, frame} <= deadline;
            assign at_deadline[note] = {1'b0, frame} >= deadline;

            // Within the window the signed difference fits in four bits.
            wire [3:0] offset = frame[3:0] - target[3:0];
            wire [2:0] magnitude = offset[3] ? -offset[2:0] : offset[2:0];
            assign distances[3*note +: 3] = magnitude;

            reg entered_field;
            assign entered[note] = entered_field;
            always @(posedge clk) begin
                if (reset) begin
                    entered_field <= target <= VISIBLE_LEAD;
                    // Off-screen positions can wrap. The visible interval
                    // is wholly within the 9-bit coordinate range.
                    tile_bottoms[9*note +: 9] <= HIT_Y - FALL_STEP * target[8:0];
                end else if (frame_tick && frame < LAST_FRAME) begin
                    if (frame == target - VISIBLE_LEAD - 10'd1)
                        entered_field <= 1'b1;
                    tile_bottoms[9*note +: 9] <= tile_bottoms[9*note +: 9] + FALL_STEP;
                end
            end
        end
    endgenerate
    reg [11:0] best_slots;
    reg [11:0] best_distances;
    integer slot;
    integer lane;
    reg [2:0] distance;
    integer pad;

    always @* begin
        resolved_next = resolved;
        hits = 0;
        misses = 0;
        best_slots = 0;
        best_distances = {4{NO_MATCH}};

        for (slot = 0; slot < 8; slot = slot + 1) begin
            lane = {30'b0, lanes[2*slot +: 2]};
            distance = distances[3*slot +: 3];
            if (!resolved[slot] && in_window[slot] &&
                distance < best_distances[3*lane +: 3]) begin
                best_slots[3*lane +: 3] = slot[2:0];
                best_distances[3*lane +: 3] = distance;
            end
        end

        for (pad = 0; pad < 4; pad = pad + 1) begin
            if (frame_press[pad]) begin
                if (best_distances[3*pad +: 3] <= WINDOW) begin
                    hits[pad] = 1;
                    resolved_next[best_slots[3*pad +: 3]] = 1;
                end else begin
                    misses[pad] = 1;
                end
            end
        end
        // Accept a hit on the last eligible frame before expiring the note.
        for (slot = 0; slot < 8; slot = slot + 1) begin
            if (at_deadline[slot] && !resolved_next[slot]) begin
                resolved_next[slot] = 1;
                misses[lanes[2*slot +: 2]] = 1;
            end
        end
    end

    integer effect_lane;
    always @(posedge clk) begin
        if (reset) begin
            previous_press <= 0;
            pending_press <= 0;
            frame <= 0;
            resolved <= 0;
            pulse_ages <= {4{4'd12}};
            pulse_hit <= 0;
        end else begin
            previous_press <= lane_press;
            pending_press <= frame_press;
            if (frame_tick) begin
                pending_press <= 0;
                if (frame < LAST_FRAME)
                    frame <= frame + 1'b1;
                resolved <= resolved_next;

                for (effect_lane = 0; effect_lane < 4; effect_lane = effect_lane + 1) begin
                    if (hits[effect_lane] || misses[effect_lane]) begin
                        pulse_ages[4*effect_lane +: 4] <= 0;
                        pulse_hit[effect_lane] <= hits[effect_lane];
                    end else if (pulse_ages[4*effect_lane +: 4] < PULSE_FRAMES) begin
                        pulse_ages[4*effect_lane +: 4] <=
                            pulse_ages[4*effect_lane +: 4] + 1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
