`timescale 1ns / 1ps
`default_nettype none

// Basys 3 VGA game, with the original diagnostic available at elaboration.
module veribeat #(
    parameter integer START_X = 1,
    parameter integer START_Y = 1,
    parameter DIAGNOSTIC = 0,
    parameter integer KEYPAD_COL_CYCLES = 100_000,
    parameter SONG0_FILE = "charts/song_0.mem",
    parameter SONG1_FILE = "charts/song_1.mem",
    parameter SONG2_FILE = "charts/song_2.mem",
    parameter integer CYCLES_PER_MS = 100000,
    parameter integer UART_CLKS_PER_BIT = 868
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
    wire reset;
    wire pixel_tick;
    wire [9:0] x;
    wire [9:0] y;
    wire video_on;
    wire frame_tick;
    reg [11:0] color;
    wire CLK_100MHz;
    wire CLK_50MHz;
    wire CLK_25MHz;
    reg [9:0] box_x;
    reg [9:0] box_y;
    reg move_left;
    reg move_up;

    // 64x64 square: 2 pixels horizontally and 1 vertically per frame.
    // Update only at the frame boundary, keeping every visible frame coherent.
    always @(posedge clk) begin
        if (reset) begin
            box_x <= START_X;
            box_y <= START_Y;
            move_left <= 1'b0;
            move_up <= 1'b0;
        end else if (frame_tick) begin
            if (!move_left) begin
                if (box_x >= 10'd573) begin
                    box_x <= 10'd575;
                    move_left <= 1'b1;
                end else box_x <= box_x + 10'd2;
            end else begin
                if (box_x <= 10'd3) begin
                    box_x <= 10'd1;
                    move_left <= 1'b0;
                end else box_x <= box_x - 10'd2;
            end
            if (!move_up) begin
                if (box_y >= 10'd414) begin
                    box_y <= 10'd415;
                    move_up <= 1'b1;
                end else box_y <= box_y + 10'd1;
            end else begin
                if (box_y <= 10'd2) begin
                    box_y <= 10'd1;
                    move_up <= 1'b0;
                end else box_y <= box_y - 10'd1;
            end
        end
    end

    clock clocks (
        .clk(clk), .reset(btnC),
        .reset_sync(reset), .pixel_tick(pixel_tick),
        .CLK_100MHz(CLK_100MHz), .CLK_50MHz(CLK_50MHz), .CLK_25MHz(CLK_25MHz)
    );

    always @* begin
        if      (x < 10'd80)  color = 12'hFFF; // White
        else if (x < 10'd160) color = 12'hFF0; // Yellow
        else if (x < 10'd240) color = 12'h0FF; // Cyan
        else if (x < 10'd320) color = 12'h0F0; // Green
        else if (x < 10'd400) color = 12'hF0F; // Magenta
        else if (x < 10'd480) color = 12'hF00; // Red
        else if (x < 10'd560) color = 12'h00F; // Blue
        else                 color = 12'h000; // Black

        // Fixed dark grid gives a stationary reference for image jitter.
        if ((x[5:0] == 0) || (y[5:0] == 0)) color = 12'h444;
        if ((x >= box_x) && (x < box_x + 10'd64) &&
            (y >= box_y) && (y < box_y + 10'd64)) color = 12'hFFF;

        if ((x == 10'd0) || (x == 10'd639) ||
            (y == 10'd0) || (y == 10'd479))
            color = 12'hFFF;
    end

    wire [11:0] video_color;
    generate
        if (DIAGNOSTIC) begin : diagnostic
            assign video_color = color;
            assign cols = 4'bzzzz;
            assign RsTx = 1'b1;
            assign led = 0;
        end else begin : game
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
            wire [23:0] score_digits;
            wire [10:0] combo, longest_streak;
            wire [15:0] combo_digits, longest_digits;
            reg [1:0] screen;
            wire [15:0] misclick_events;
            wire [9:0] chart_address;
            wire chart_enable;
            wire [39:0] chart_data;
            wire front_bank, front_valid, mask_write, mask_clear, overrun;
            wire [10:0] mask_address;
            wire [1:0] mask_bits, tile_pixel;
            wire [15:0] pulse_ages, digits;
            wire [3:0] pulse_hit, hits;
            wire [10:0] points, resolved_count;
            wire [31:0] elapsed_ms;
            wire cmd_load, cmd_play, cmd_stop, cmd_pause, cmd_resume;
            wire audio_ready, audio_error, audio_busy;
            wire game_reset, running, paused, finished, failed;
            assign misclick_events =
                (running ? key_pressed & ~16'hE001 : 16'b0) |
                {lane_misclicks[1],lane_misclicks[2],lane_misclicks[3],12'b0,lane_misclicks[0]};
            wire reset_game = reset | game_reset;
            wire [9:0] field_x = x - 10'd64;
            wire publish_tick = pixel_tick && x == 0 && y == 47;
            assign led = {overrun, failed, finished, paused, running, points};

            audio #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) soundtrack (
                .clk(clk), .rst(reset), .cmd_load(cmd_load), .song_id({2'b0,song_index}),
                .cmd_play(cmd_play), .cmd_stop(cmd_stop), .cmd_pause(cmd_pause),
                .cmd_resume(cmd_resume), .audio_ready(audio_ready), .audio_error(audio_error),
                .busy(audio_busy), .rx_data(), .rx_valid(), .RsRx(RsRx), .RsTx(RsTx)
            );
            always @(posedge clk) begin
                if (reset) screen <= 0;
                else if (frame_tick) begin
                    if (home) screen <= 0;
                    else if (finished || failed) screen <= 2;
                    else if (loading) screen <= 3;
                    else screen <= 1;
                end
            end
            assign video_color = screen == 1 && !hud_pixel ? game_color : menu_color;
            menu_display menus (
                .clk(clk), .reset(reset), .x(x), .y(y), .screen(screen),
                .song(song_index), .failed(failed), .hit_digits(digits),
                .miss_digits(miss_digits), .misclick_digits(misclick_digits),
                .score_digits(score_digits), .combo_digits(combo_digits), .longest_digits(longest_digits),
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
                .paused(paused), .finished(finished), .failed(failed)
            );

            keypad #(
                .COL_CYCLES(KEYPAD_COL_CYCLES),
                .LANE0_KEY(LANE_KEYS[3:0]), .LANE1_KEY(LANE_KEYS[7:4]),
                .LANE2_KEY(LANE_KEYS[11:8]), .LANE3_KEY(LANE_KEYS[15:12])
            ) numpad (
                .clk(clk), .reset(reset), .rows(rows), .cols(cols),
                .keys(), .pressed(key_pressed), .released(), .lane_press(lane_press)
            );
            song_library #(.SONG0_FILE(SONG0_FILE), .SONG1_FILE(SONG1_FILE),
                           .SONG2_FILE(SONG2_FILE)) chart (
                .clk(clk), .song(song_index), .enable(chart_enable), .address(chart_address),
                .data(chart_data), .note_count(chart_note_count), .duration_ms(chart_duration_ms)
            );
            control #(.DYNAMIC_CHART(1)) gameplay (
                .clk(clk), .reset(reset_game), .frame_tick(frame_tick),
                .publish_tick(publish_tick), .running(running), .elapsed_ms(elapsed_ms),
                .lane_press(lane_press), .chart_address(chart_address), .chart_enable(chart_enable),
                .chart_data(chart_data), .chart_note_count(chart_note_count), .front_bank(front_bank), .front_valid(front_valid),
                .mask_write(mask_write), .mask_clear(mask_clear), .mask_address(mask_address),
                .mask_bits(mask_bits), .pulse_ages(pulse_ages), .pulse_hit(pulse_hit),
                .hits(hits), .resolved_count(resolved_count), .overrun(overrun),
                .note_miss(note_miss), .misclicks(lane_misclicks)
            );
            tile_mask mask (
                .clk(clk), .front_bank(front_bank), .write_enable(mask_write),
                .clear_pixel(mask_clear), .write_address(mask_address), .write_bits(mask_bits),
                .read_address({field_x[8:7],y[8:0]}), .pixel(tile_pixel)
            );
            combo_score scoring (
                .clk(clk), .reset(reset_game), .hits(hits), .note_miss(note_miss),
                .misclicks(misclick_events), .total_score(total_score), .score_digits(score_digits),
                .combo(combo), .combo_digits(combo_digits),
                .longest_streak(longest_streak), .longest_digits(longest_digits)
            );
            score tally (.clk(clk), .reset(reset_game), .hits(hits), .points(points), .digits(digits));
            score misses (.clk(clk), .reset(reset_game), .hits({3'b0,note_miss}),
                          .points(miss_count), .digits(miss_digits));
            score #(.WIDTH(14), .LIMIT(9999), .INPUT_BITS(16)) misclicks (
                .clk(clk), .reset(reset_game), .hits(misclick_events),
                .points(misclick_count), .digits(misclick_digits)
            );
            display #(.LANE_KEYS(LANE_KEYS)) renderer (
                .x(x), .y(y), .tile_pixel(front_valid ? tile_pixel : 2'b0),
                .pulse_ages(pulse_ages), .pulse_hit(pulse_hit), .digits(digits), .color(game_color)
            );
        end
    endgenerate

    vga video (
        .clk(clk), .reset(reset), .pixel_tick(pixel_tick),
        .red_in(video_color[11:8]), .green_in(video_color[7:4]), .blue_in(video_color[3:0]),
        .x(x), .y(y), .video_on(video_on), .frame_tick(frame_tick),
        .hsync(Hsync), .vsync(Vsync),
        .red(vgaRed), .green(vgaGreen), .blue(vgaBlue)
    );
endmodule

`default_nettype wire
