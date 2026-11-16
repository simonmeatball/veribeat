`timescale 1ns / 1ps
`default_nettype none

module control (
    input  wire        clk,
    input  wire        reset,
    input  wire        frame_tick,
    input  wire [3:0]  lane_press,
    input  wire [15:0] lanes,
    input  wire [79:0] targets,
    output reg  [7:0]  visible,
    output reg  [71:0] tile_bottoms,
    output reg  [15:0] pulse_ages,
    output reg  [3:0]  pulse_hit,
    output reg  [3:0]  hits
);
    localparam HIT_Y = 404;
    localparam integer WINDOW = 4;
    localparam [2:0] NO_MATCH = WINDOW + 1;
    localparam PULSE_FRAMES = 12;
    localparam LAST_FRAME = 340;

    reg [9:0] frame;
    reg [7:0] resolved;
    reg [3:0] previous_press;
    reg [3:0] pending_press;
    // Catch rising edges at 100 MHz, including an edge on frame_tick itself.
    wire [3:0] pressed = lane_press & ~previous_press;
    wire [3:0] frame_press = pending_press | pressed;

    reg [7:0] resolved_next;
    reg [3:0] misses;
    reg [7:0] expiring;
    reg [11:0] best_slots;
    reg [11:0] best_distances;
    integer slot;
    integer lane;
    integer delta;
    integer distance;
    integer bottom;
    integer pad;

    always @* begin
        resolved_next = resolved;
        hits = 0;
        misses = 0;
        expiring = 0;
        visible = 0;
        tile_bottoms = 0;
        best_slots = 0;
        best_distances = {4{NO_MATCH}};

        for (slot = 0; slot < 8; slot = slot + 1) begin
            lane = {30'b0, lanes[2*slot +: 2]};
            delta = {22'b0, frame};
            delta = delta - $signed({22'b0, targets[10*slot +: 10]});
            distance = delta < 0 ? -delta : delta;
            bottom = HIT_Y + 5 * delta;

            if (!resolved[slot]) begin
                if (bottom > 48 && bottom <= HIT_Y + 5 * WINDOW) begin
                    visible[slot] = 1;
                    tile_bottoms[9*slot +: 9] = bottom[8:0];
                end
                expiring[slot] = delta >= WINDOW;
                if (frame_press[lane] && distance < best_distances[3*lane +: 3]) begin
                    best_slots[3*lane +: 3] = slot[2:0];
                    best_distances[3*lane +: 3] = distance[2:0];
                end
            end
        end

        for (pad = 0; pad < 4; pad = pad + 1) begin
            if (best_distances[3*pad +: 3] <= WINDOW) begin
                hits[pad] = 1;
                resolved_next[best_slots[3*pad +: 3]] = 1;
            end else if (frame_press[pad]) begin
                misses[pad] = 1;
            end
        end
        // Accept a hit on the last eligible frame before expiring the note.
        for (slot = 0; slot < 8; slot = slot + 1) begin
            if (expiring[slot] && !resolved_next[slot]) begin
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
