`timescale 1ns / 1ps
`default_nettype none

// Audio lifecycle and the millisecond timebase. Buttons are synchronized and
// accepted after ten milliseconds of a stable state.
module game_session #(
    parameter integer CYCLES_PER_MS = 100000,
    parameter integer PRE_ROLL_MS = 1400,
    parameter integer DURATION_MS = 10000,
    parameter integer NOTE_COUNT = 8
) (
    input wire clk, reset,
    input wire [3:0] buttons, // restart, pause, resume, stop
    input wire audio_ready, audio_error, audio_busy,
    input wire [10:0] resolved_count,
    output reg cmd_load, cmd_play, cmd_stop, cmd_pause, cmd_resume,
    output reg game_reset,
    output wire running,
    output reg [31:0] elapsed_ms,
    output wire paused,
    output wire finished,
    output wire failed
);
    localparam STOP_REQUEST=0, STOP_WAIT=1, LOAD_REQUEST=2, LOAD_WAIT=3,
               PLAYING=4, PAUSED=5, FINISHED=6, FAILED=7, STOPPED=8;
    reg [3:0] state;
    localparam DIVIDER_BITS = CYCLES_PER_MS > 1 ? $clog2(CYCLES_PER_MS) : 1;
    reg [DIVIDER_BITS-1:0] ms_divider;
    reg [DIVIDER_BITS-1:0] debounce_divider;
    (* ASYNC_REG = "TRUE" *) reg [3:0] buttons_meta, buttons_sync;
    reg [3:0] button_sample, button_stable;
    reg [3:0] button_pulse;
    reg [3:0] stable_ticks [0:3];
    reg [3:0] settle;
    integer button;
    assign running = state == PLAYING;
    assign paused = state == PAUSED;
    assign finished = state == FINISHED;
    assign failed = state == FAILED;

    always @(posedge clk) begin
        if (reset) begin
            buttons_meta <= 0; buttons_sync <= 0;
            button_sample <= 0; button_stable <= 0; button_pulse <= 0;
            debounce_divider <= 0;
            for (button=0; button<4; button=button+1) stable_ticks[button] <= 0;
        end else begin
            buttons_meta <= buttons;
            buttons_sync <= buttons_meta;
            button_pulse <= 0;
            if (debounce_divider == CYCLES_PER_MS-1) begin
                debounce_divider <= 0;
                for (button=0; button<4; button=button+1) begin
                    button_sample[button] <= buttons_sync[button];
                    if (button_sample[button] != buttons_sync[button]) stable_ticks[button] <= 0;
                    else if (stable_ticks[button] < 10) stable_ticks[button] <= stable_ticks[button] + 1'b1;
                    else begin
                        button_stable[button] <= button_sample[button];
                        button_pulse[button] <= button_sample[button] & ~button_stable[button];
                    end
                end
            end else debounce_divider <= debounce_divider + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= STOP_REQUEST;
            settle <= 0;
            elapsed_ms <= 0;
            ms_divider <= 0;
            cmd_load <= 0; cmd_play <= 0; cmd_stop <= 0;
            cmd_pause <= 0; cmd_resume <= 0;
            game_reset <= 1;
        end else begin
            cmd_load <= 0; cmd_play <= 0; cmd_stop <= 0;
            cmd_pause <= 0; cmd_resume <= 0; game_reset <= 0;
            case (state)
                STOP_REQUEST: begin
                    cmd_stop <= 1;
                    game_reset <= 1;
                    elapsed_ms <= 0;
                    ms_divider <= 0;
                    settle <= 0;
                    state <= STOP_WAIT;
                end
                STOP_WAIT: begin
                    if (settle < 8) settle <= settle + 1'b1;
                    else if (!audio_busy) state <= LOAD_REQUEST;
                end
                LOAD_REQUEST: begin cmd_load <= 1; settle <= 0; state <= LOAD_WAIT; end
                LOAD_WAIT: begin
                    if (settle < 8) settle <= settle + 1'b1;
                    else if (audio_error) state <= FAILED;
                    else if (audio_ready && !audio_busy) state <= PLAYING;
                end
                PLAYING: begin
                    if (button_pulse[1]) begin
                        state <= PAUSED;
                        if (elapsed_ms >= PRE_ROLL_MS) cmd_pause <= 1;
                    end else if (ms_divider == CYCLES_PER_MS-1) begin
                        ms_divider <= 0;
                        elapsed_ms <= elapsed_ms + 1'b1;
                        if (elapsed_ms == PRE_ROLL_MS-1) cmd_play <= 1;
                        if (elapsed_ms >= PRE_ROLL_MS + DURATION_MS + 250 &&
                            resolved_count == NOTE_COUNT) begin
                            cmd_stop <= 1;
                            state <= FINISHED;
                        end
                    end else ms_divider <= ms_divider + 1'b1;
                end
                PAUSED: if (button_pulse[2]) begin
                    state <= PLAYING;
                    if (elapsed_ms >= PRE_ROLL_MS) cmd_resume <= 1;
                end
                default: begin end
            endcase
            if (audio_error && (state == PLAYING || state == PAUSED)) begin
                cmd_stop <= 1;
                state <= FAILED;
            end
            if (button_pulse[3]) begin cmd_stop <= 1; state <= STOPPED; end
            if (button_pulse[0]) state <= STOP_REQUEST;
        end
    end
endmodule
`default_nettype wire
