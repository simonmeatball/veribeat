`timescale 1ns / 1ps
`default_nettype none

// Basys 3 game integration. Each group follows one step of the gameplay flow.
module veribeat #(
    parameter integer KEYPAD_COL_CYCLES = 100_000,
    parameter SONG0_FILE = "charts/song_0.mem",
    parameter SONG1_FILE = "charts/song_1.mem",
    parameter SONG2_FILE = "charts/song_2.mem",
    parameter integer CYCLES_PER_MS = 100000,
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer GRADE_PENALTY_PERCENT = 25
) (
    input  wire       clk,
    input  wire       btnC,
    output wire       Hsync,
    output wire       Vsync,
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    input  wire [3:0] rows,
    output wire [3:0] cols,
    input wire btnU, btnL, btnR, btnD,
    input wire RsRx,
    output wire RsTx,
    output wire [15:0] led
);
    `include "game_defs.vh"

    // Raster timing and the system-clock pixel enable.
    wire reset;
    wire pixel_tick;
    wire [9:0] x, y;
    wire frame_tick;
    wire [11:0] video_color;
    clock clocks (.clk(clk), .reset(btnC), .reset_sync(reset), .pixel_tick(pixel_tick));

    localparam [15:0] LANE_KEYS = 16'hDEF0;
    wire [3:0] lane_press;
    wire [15:0] key_pressed;
    wire [1:0] song_index;
    wire [10:0] chart_note_count;
    wire [31:0] chart_duration_ms;
    wire home, loading;
    wire note_miss;
    wire [3:0] lane_misclicks;
    wire [15:0] miss_digits, misclick_digits;
    wire [10:0] miss_count;
    wire [13:0] misclick_count;
    wire [11:0] game_color, menu_color;
    wire hud_pixel;
    wire [19:0] total_score;
    wire [7:0] grade;
    wire [11:0] judgments;
    wire [11:0] hit_judgments;
    wire [19:0] judgment_ages;
    wire [23:0] score_digits;
    wire [10:0] combo, longest_streak;
    wire [15:0] combo_digits, longest_digits;
    reg [2:0] screen;
    wire [1:0] countdown;
    wire [15:0] misclick_events;
    wire [9:0] chart_address;
    wire chart_enable;
    wire [34:0] chart_data;
    wire front_bank, front_valid, mask_write, mask_clear, overrun;
    wire [10:0] mask_address;
    wire [1:0] mask_bits, tile_pixel;
    wire [15:0] pulse_ages, hit_digits;
    wire [3:0] pulse_hit, hits;
    wire [10:0] hit_count, resolved_count;
    wire [31:0] elapsed_ms;
    wire [9:0] progress_pixels;
    wire cmd_load, cmd_play, cmd_stop, cmd_pause, cmd_resume;
    wire audio_ready, audio_error, audio_busy;
    wire game_reset, running, paused, finished, failed;
    assign misclick_events =
        (running ? key_pressed & ~16'hE001 : 16'b0) |
        {lane_misclicks[1],lane_misclicks[2],lane_misclicks[3],12'b0,lane_misclicks[0]};
    wire reset_game = reset | game_reset;
    wire [9:0] field_x = x - `FIELD_LEFT;
    wire publish_tick = pixel_tick && x == 0 && y == `FIELD_TOP-1;
    assign led = {overrun, failed, finished, paused, running, hit_count};

    // Session and laptop audio commands.
    audio #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) soundtrack (
        .clk(clk), .rst(reset), .cmd_load(cmd_load), .song_id({2'b0,song_index}),
        .cmd_play(cmd_play), .cmd_stop(cmd_stop), .cmd_pause(cmd_pause),
        .cmd_resume(cmd_resume), .audio_ready(audio_ready), .audio_error(audio_error),
        .busy(audio_busy), .rx_data(), .rx_valid(), .RsRx(RsRx), .RsTx(RsTx)
    );
    always @(posedge clk) begin
        if (reset) screen <= `SCREEN_HOME;
        else if (frame_tick) begin
            if (home) screen <= `SCREEN_HOME;
            else if (finished || failed) screen <= `SCREEN_RESULTS;
            else if (loading) screen <= `SCREEN_LOADING;
            else if (paused) screen <= `SCREEN_PAUSED;
            else if (countdown != 0) screen <= `SCREEN_COUNTDOWN;
            else screen <= `SCREEN_GAME;
        end
    end
    assign video_color = screen == `SCREEN_GAME && !hud_pixel ? game_color : menu_color;
    song_progress progress (
        .clk(clk), .reset(reset_game), .frame_tick(frame_tick),
        .elapsed_ms(elapsed_ms), .duration_ms(chart_duration_ms), .pixels(progress_pixels)
    );
    menu_display menus (
        .clk(clk), .reset(reset), .x(x), .y(y), .screen(screen),
        .song(song_index), .failed(failed), .hit_digits(hit_digits),
        .miss_digits(miss_digits), .misclick_digits(misclick_digits),
        .score_digits(score_digits), .combo_digits(combo_digits), .longest_digits(longest_digits),
        .progress_pixels(progress_pixels),
        .countdown(countdown),
        .grade(grade), .judgments(judgments), .judgment_ages(judgment_ages),
        .hud_pixel(hud_pixel), .color(menu_color)
    );
    game_session #(.CYCLES_PER_MS(CYCLES_PER_MS)) session (
        .clk(clk), .reset(reset), .buttons({btnD,btnR,btnL,btnU}),
        .audio_ready(audio_ready), .audio_error(audio_error), .audio_busy(audio_busy),
        .resolved_count(resolved_count), .chart_note_count(chart_note_count),
        .chart_duration_ms(chart_duration_ms),
        .song_press({key_pressed[3],key_pressed[2],key_pressed[1]}),
        .any_key(|key_pressed), .song_index(song_index), .home(home), .loading(loading),
        .cmd_load(cmd_load), .cmd_play(cmd_play),
        .cmd_stop(cmd_stop), .cmd_pause(cmd_pause), .cmd_resume(cmd_resume),
        .game_reset(game_reset), .running(running), .elapsed_ms(elapsed_ms),
        .paused(paused), .countdown(countdown), .finished(finished), .failed(failed)
    );

    // Physical keypad input.
    keypad #(
        .COL_CYCLES(KEYPAD_COL_CYCLES),
        .LANE0_KEY(LANE_KEYS[3:0]), .LANE1_KEY(LANE_KEYS[7:4]),
        .LANE2_KEY(LANE_KEYS[11:8]), .LANE3_KEY(LANE_KEYS[15:12])
    ) numpad (
        .clk(clk), .reset(reset), .rows(rows), .cols(cols),
        .keys(), .pressed(key_pressed), .released(), .lane_press(lane_press)
    );
    // Selected chart, judgment, and the next frame of tiles.
    song_library #(.SONG0_FILE(SONG0_FILE), .SONG1_FILE(SONG1_FILE),
                   .SONG2_FILE(SONG2_FILE)) chart (
        .clk(clk), .song(song_index), .enable(chart_enable), .address(chart_address),
        .data(chart_data), .note_count(chart_note_count), .duration_ms(chart_duration_ms)
    );
    control gameplay (
        .clk(clk), .reset(reset_game), .frame_tick(frame_tick),
        .publish_tick(publish_tick), .running(running), .elapsed_ms(elapsed_ms),
        .lane_press(lane_press), .chart_address(chart_address), .chart_enable(chart_enable),
        .chart_data(chart_data), .chart_note_count(chart_note_count), .front_bank(front_bank), .front_valid(front_valid),
        .mask_write(mask_write), .mask_clear(mask_clear), .mask_address(mask_address),
        .mask_bits(mask_bits), .pulse_ages(pulse_ages), .pulse_hit(pulse_hit),
        .judgments(judgments), .judgment_ages(judgment_ages),
        .hits(hits), .hit_judgments(hit_judgments), .resolved_count(resolved_count), .overrun(overrun),
        .note_miss(note_miss), .misclicks(lane_misclicks)
    );
    tile_mask mask (
        .clk(clk), .front_bank(front_bank), .write_enable(mask_write),
        .clear_pixel(mask_clear), .write_address(mask_address), .write_bits(mask_bits),
        .read_address({field_x[8:7],y[8:0]}), .pixel(tile_pixel)
    );
    // Statistics and combo scoring.
    result_grade #(.PENALTY_PERCENT(GRADE_PENALTY_PERCENT)) grading (
        .clk(clk), .reset(reset_game), .note_count(chart_note_count),
        .hit_count(hit_count), .miss_count(miss_count), .misclick_count(misclick_count), .grade(grade)
    );
    combo_score scoring (
        .clk(clk), .reset(reset_game), .hits(hits), .note_miss(note_miss),
        .hit_judgments(hit_judgments),
        .misclicks(misclick_events), .total_score(total_score), .score_digits(score_digits),
        .combo(combo), .combo_digits(combo_digits),
        .longest_streak(longest_streak), .longest_digits(longest_digits)
    );
    event_counter tally (.clk(clk), .reset(reset_game), .hits(hits), .points(hit_count), .digits(hit_digits));
    event_counter misses (.clk(clk), .reset(reset_game), .hits({3'b0,note_miss}),
                  .points(miss_count), .digits(miss_digits));
    event_counter #(.WIDTH(14), .LIMIT(9999), .INPUT_BITS(16)) misclicks (
        .clk(clk), .reset(reset_game), .hits(misclick_events),
        .points(misclick_count), .digits(misclick_digits)
    );
    // Gameplay pixels. Menu/HUD pixels are selected above.
    display #(.LANE_KEYS(LANE_KEYS)) renderer (
        .x(x), .y(y), .tile_pixel(front_valid ? tile_pixel : 2'b0),
        .pulse_ages(pulse_ages), .pulse_hit(pulse_hit), .color(game_color)
    );

    vga video (
        .clk(clk), .reset(reset), .pixel_tick(pixel_tick),
        .red_in(video_color[11:8]), .green_in(video_color[7:4]), .blue_in(video_color[3:0]),
        .x(x), .y(y), .video_on(), .frame_tick(frame_tick),
        .hsync(Hsync), .vsync(Vsync),
        .red(vgaRed), .green(vgaGreen), .blue(vgaBlue)
    );
endmodule

`default_nettype wire
