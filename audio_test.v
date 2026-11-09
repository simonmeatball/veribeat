`timescale 1ns / 1ps
// =============================================================================
// audio_test.v - standalone Basys 3 hardware test for audio.v
//
// Use with audio_test.xdc as the top module. Run audio_player.py on the
// laptop, then:
//
//   sw[3:0]  song id (0-9)
//   sw[15]   reset (up = held in reset)
//
//   btnU     LOAD    -> sends 'L' + id, laptop answers 'K'
//   btnC     PLAY    -> 'P'
//   btnD     STOP    -> 'S'
//   btnL     PAUSE   -> 'H'
//   btnR     RESUME  -> 'R'
//
//   led[7:0] last byte received from the laptop (ASCII 'K' = 0100_1011)
//   led[12]  toggles every time a byte is received
//   led[13]  "playing" (local guess: set on PLAY/RESUME, cleared on STOP/PAUSE)
//   led[14]  audio_error (laptop sent 'E', e.g. missing file)
//   led[15]  audio_ready (laptop sent 'K')
// =============================================================================
module audio_test (
    input  wire        clk,        // 100 MHz
    input  wire [15:0] sw,
    input  wire        btnC, btnU, btnD, btnL, btnR,
    output wire [15:0] led,
    input  wire        RsRx,
    output wire        RsTx
);
    wire rst = sw[15];

    // ---------------- buttons -> clean 1-cycle pulses ----------------
    wire p_load, p_play, p_stop, p_pause, p_resume;

    audio_test_btn u_bu (.clk(clk), .rst(rst), .btn(btnU), .pulse(p_load));
    audio_test_btn u_bc (.clk(clk), .rst(rst), .btn(btnC), .pulse(p_play));
    audio_test_btn u_bd (.clk(clk), .rst(rst), .btn(btnD), .pulse(p_stop));
    audio_test_btn u_bl (.clk(clk), .rst(rst), .btn(btnL), .pulse(p_pause));
    audio_test_btn u_br (.clk(clk), .rst(rst), .btn(btnR), .pulse(p_resume));

    // ---------------- device under test ----------------
    wire       audio_ready, audio_error, busy;
    wire [7:0] rx_data;
    wire       rx_valid;

    audio #(.CLKS_PER_BIT(868)) u_audio (
        .clk(clk), .rst(rst),
        .cmd_load(p_load), .song_id(sw[3:0]),
        .cmd_play(p_play), .cmd_stop(p_stop),
        .cmd_pause(p_pause), .cmd_resume(p_resume),
        .audio_ready(audio_ready), .audio_error(audio_error), .busy(busy),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .RsRx(RsRx), .RsTx(RsTx)
    );

    // ---------------- status LEDs ----------------
    reg [7:0] last_rx;
    reg       rx_toggle;
    reg       playing;

    always @(posedge clk) begin
        if (rst) begin
            last_rx   <= 8'd0;
            rx_toggle <= 1'b0;
            playing   <= 1'b0;
        end else begin
            if (rx_valid) begin
                last_rx   <= rx_data;
                rx_toggle <= ~rx_toggle;
            end
            if (p_play | p_resume)               playing <= 1'b1;
            if (p_stop | p_pause | p_load)       playing <= 1'b0;
        end
    end

    assign led[7:0]  = last_rx;
    assign led[11:8] = 4'd0;
    assign led[12]   = rx_toggle;
    assign led[13]   = playing;
    assign led[14]   = audio_error;
    assign led[15]   = audio_ready;
endmodule


// -----------------------------------------------------------------------------
// audio_test_btn: synchronize + debounce a pushbutton, output a 1-cycle pulse
// on press. ~10 ms debounce at 100 MHz.
// -----------------------------------------------------------------------------
module audio_test_btn #(
    parameter DEBOUNCE_CYCLES = 1_000_000
)(
    input  wire clk,
    input  wire rst,
    input  wire btn,
    output reg  pulse
);
    reg        s1, s2;        // synchronizer
    reg        stable;        // debounced level
    reg [19:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            s1 <= 1'b0; s2 <= 1'b0;
            stable <= 1'b0;
            cnt    <= 0;
            pulse  <= 1'b0;
        end else begin
            s1    <= btn;
            s2    <= s1;
            pulse <= 1'b0;
            if (s2 == stable) begin
                cnt <= 0;
            end else if (cnt == DEBOUNCE_CYCLES - 1) begin
                cnt    <= 0;
                stable <= s2;
                if (s2) pulse <= 1'b1;   // rising edge of debounced button
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
