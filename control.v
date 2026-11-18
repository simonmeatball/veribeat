`timescale 1ns / 1ps
`default_nettype none

module control #(
    parameter integer NOTE_COUNT = 8,
    parameter integer PRE_ROLL_MS = 1400,
    parameter integer HIT_WINDOW_MS = 100
) (
    input wire clk,
    input wire reset,
    input wire frame_tick,
    input wire publish_tick,
    input wire running,
    input wire [31:0] elapsed_ms,
    input wire [3:0] lane_press,
    output wire [9:0] chart_address,
    output wire chart_enable,
    input wire [39:0] chart_data,
    output reg front_bank,
    output reg front_valid,
    output wire mask_write,
    output wire mask_clear,
    output wire [10:0] mask_address,
    output wire [1:0] mask_bits,
    output reg [15:0] pulse_ages,
    output reg [3:0] pulse_hit,
    output reg [3:0] hits,
    output reg [10:0] resolved_count,
    output reg overrun
);
    localparam IDLE=0, CLEAR=1, REQUEST=2, WAIT_ROM=3, JUDGE=4,
               COMMIT=5, GEOMETRY=6, PAINT=7, READY=8;
    reg [3:0] state;
    reg painting;
    reg [10:0] index;
    reg [10:0] clear_address;
    reg [1023:0] resolved;
    reg signed [32:0] snapshot_time;
    reg signed [32:0] delta;
    reg [3:0] pending_press;
    reg [3:0] captured_press;
    reg [3:0] missed;
    reg [3:0] candidate_valid;
    reg [9:0] candidate_index [0:3];
    reg [6:0] candidate_distance [0:3];
    reg [8:0] paint_row;
    reg [8:0] tile_bottom;
    reg [8:0] tile_top;
    reg [1:0] paint_lane;
    reg [3:0] selected_hits;
    reg [2:0] hit_count;
    integer lane;

    wire [1:0] note_lane = chart_data[1:0];
    wire signed [32:0] next_delta = snapshot_time - $signed({1'b0, chart_data[33:2]});
    wire eligible = delta >= -HIT_WINDOW_MS && delta <= HIT_WINDOW_MS;
    wire [6:0] distance = delta < 0 ? -delta[6:0] : delta[6:0];
    // Only evaluate this narrow geometry for notes within the visible interval.
    wire signed [15:0] offset_pixels = ($signed(delta[15:0]) * 16'sd5) >>> 4;
    wire signed [15:0] bottom = 16'sd404 + offset_pixels;

    assign chart_address = index[9:0];
    assign chart_enable = state == REQUEST;
    assign mask_write = state == CLEAR || state == PAINT;
    assign mask_clear = state == CLEAR;
    assign mask_address = state == CLEAR ? clear_address : {paint_lane, paint_row};
    assign mask_bits = {paint_row < tile_top + 9'd2 || paint_row >= tile_bottom - 9'd2, 1'b1};

    always @* begin
        selected_hits = candidate_valid & captured_press;
        hit_count = {2'b0,selected_hits[0]} + {2'b0,selected_hits[1]} +
                    {2'b0,selected_hits[2]} + {2'b0,selected_hits[3]};
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            painting <= 0;
            index <= 0;
            clear_address <= 0;
            resolved <= 0;
            snapshot_time <= 0;
            delta <= 0;
            pending_press <= 0;
            captured_press <= 0;
            missed <= 0;
            candidate_valid <= 0;
            front_bank <= 0;
            front_valid <= 0;
            pulse_ages <= 16'hcccc;
            pulse_hit <= 0;
            hits <= 0;
            resolved_count <= 0;
            overrun <= 0;
            paint_row <= 0;
            tile_top <= 0;
            tile_bottom <= 0;
            paint_lane <= 0;
            for (lane=0; lane<4; lane=lane+1) begin
                candidate_index[lane] <= 0;
                candidate_distance[lane] <= 127;
            end
        end else begin
            hits <= 0;
            if (running) pending_press <= pending_press | lane_press;
            else pending_press <= 0;
            if (frame_tick) begin
                for (lane=0; lane<4; lane=lane+1)
                    if (pulse_ages[4*lane +: 4] < 12)
                        pulse_ages[4*lane +: 4] <= pulse_ages[4*lane +: 4] + 1'b1;
                if (running && state == IDLE) begin
                    snapshot_time <= $signed({1'b0,elapsed_ms}) - PRE_ROLL_MS;
                    captured_press <= pending_press | lane_press;
                    pending_press <= 0;
                    missed <= 0;
                    candidate_valid <= 0;
                    for (lane=0; lane<4; lane=lane+1)
                        candidate_distance[lane] <= 127;
                    clear_address <= 0;
                    painting <= 0;
                    state <= CLEAR;
                end
            end
            case (state)
                CLEAR: begin
                    if (clear_address == 2047) begin
                        index <= 0;
                        state <= NOTE_COUNT == 0 ? COMMIT : REQUEST;
                    end else clear_address <= clear_address + 1'b1;
                end
                REQUEST: state <= WAIT_ROM;
                WAIT_ROM: begin
                    // Register the time difference before judgment or geometry.
                    delta <= next_delta;
                    state <= painting ? GEOMETRY : JUDGE;
                end
                JUDGE: begin
                    if (chart_data[39] && !resolved[index[9:0]]) begin
                        if (eligible && captured_press[note_lane] &&
                            distance < candidate_distance[note_lane]) begin
                            candidate_valid[note_lane] <= 1;
                            candidate_index[note_lane] <= index[9:0];
                            candidate_distance[note_lane] <= distance;
                        end
                        // The inclusive late boundary is judged before expiry.
                        if (delta > HIT_WINDOW_MS) begin
                            resolved[index[9:0]] <= 1;
                            resolved_count <= resolved_count + 1'b1;
                            missed[note_lane] <= 1;
                        end
                    end
                    if (index + 11'd1 == NOTE_COUNT) state <= COMMIT;
                    else begin index <= index + 1'b1; state <= REQUEST; end
                end
                COMMIT: begin
                    hits <= selected_hits;
                    resolved_count <= resolved_count + hit_count;
                    for (lane=0; lane<4; lane=lane+1) begin
                        if (selected_hits[lane]) resolved[candidate_index[lane]] <= 1;
                        if (selected_hits[lane] || missed[lane] || captured_press[lane]) begin
                            pulse_ages[4*lane +: 4] <= 0;
                            pulse_hit[lane] <= selected_hits[lane];
                        end
                    end
                    painting <= 1;
                    index <= 0;
                    state <= NOTE_COUNT == 0 ? READY : REQUEST;
                end
                GEOMETRY: begin
                    if (chart_data[39] && !resolved[index[9:0]] &&
                        delta >= -1200 && delta <= HIT_WINDOW_MS && bottom > 48) begin
                        tile_top <= bottom - 16'sd36;
                        tile_bottom <= bottom[8:0];
                        paint_row <= bottom < 84 ? 9'd48 : bottom - 16'sd36;
                        paint_lane <= note_lane;
                        state <= PAINT;
                    end else if (index + 11'd1 == NOTE_COUNT) state <= READY;
                    else begin index <= index + 1'b1; state <= REQUEST; end
                end
                PAINT: begin
                    if (paint_row + 9'd1 == tile_bottom) begin
                        if (index + 11'd1 == NOTE_COUNT) state <= READY;
                        else begin index <= index + 1'b1; state <= REQUEST; end
                    end else paint_row <= paint_row + 1'b1;
                end
                default: begin end
            endcase
            if (publish_tick && state != IDLE) begin
                if (state == READY) begin
                    front_bank <= ~front_bank;
                    front_valid <= 1;
                    state <= IDLE;
                end else begin
                    overrun <= 1;
                    state <= IDLE;
                end
            end
        end
    end
endmodule

`default_nettype wire
