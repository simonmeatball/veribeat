`timescale 1ns / 1ps
// =============================================================================
// audio.v - UART audio-control interface for veribeat
//
// The FPGA tells a Python program on the laptop (audio_player.py) when to
// load / play / stop / pause / resume a song, over the Basys 3 USB-UART.
//
// UART format: 8N1 (1 start bit, 8 data bits LSB first, 1 stop bit), idle high.
// Default 115200 baud with a 100 MHz clock -> 868 clocks per bit.
//
// Protocol (single ASCII bytes):
//   FPGA -> PC : 'L' <'0'..'9'>  load song N   (PC replies 'K' when ready)
//                'P'             play from start
//                'S'             stop
//                'H'             hold (pause)
//                'R'             resume
//   PC -> FPGA : 'K'             song loaded, ready to play
//                'E'             error (e.g. song file missing)
//
// Modules in this file:
//   uart_tx - serializes one byte
//   uart_rx - deserializes one byte
//   audio   - command layer used by the rest of the game
// =============================================================================


// -----------------------------------------------------------------------------
// uart_tx: pulse tx_start for one cycle with tx_data valid (while !tx_busy).
// tx_done pulses for one cycle when the stop bit has finished.
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output wire       tx_busy,
    output reg        tx_done
);
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    assign tx_busy = (state != IDLE);
    wire bit_end = (clk_cnt == CLKS_PER_BIT - 1);

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            tx      <= 1'b1;          // line idles high
            clk_cnt <= 0;
            bit_idx <= 0;
            shreg   <= 8'd0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (tx_start) begin
                        shreg <= tx_data;
                        state <= START;
                    end
                end
                START: begin
                    tx <= 1'b0;
                    if (bit_end) begin
                        clk_cnt <= 0;
                        state   <= DATA;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                DATA: begin
                    tx <= shreg[bit_idx];   // LSB first
                    if (bit_end) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                STOP: begin
                    tx <= 1'b1;
                    if (bit_end) begin
                        clk_cnt <= 0;
                        tx_done <= 1'b1;
                        state   <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule


// -----------------------------------------------------------------------------
// uart_rx: rx_valid pulses for one cycle when rx_data holds a new byte.
// The asynchronous rx input is passed through a 2-FF synchronizer, and each
// bit is sampled in its middle.
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    // 2-flop synchronizer (reset to idle-high)
    reg rx_s1, rx_s2;
    always @(posedge clk) begin
        if (rst) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= rx;
            rx_s2 <= rx_s1;
        end
    end

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            shreg    <= 8'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_s2 == 1'b0)          // falling edge = start bit
                        state <= START;
                end
                START: begin                    // go to middle of start bit
                    if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        clk_cnt <= 0;
                        if (rx_s2 == 1'b0)
                            state <= DATA;      // real start bit
                        else
                            state <= IDLE;      // glitch, ignore
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                DATA: begin                     // sample middle of each bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt         <= 0;
                        shreg[bit_idx]  <= rx_s2;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
                STOP: begin                     // middle of stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= IDLE;
                        if (rx_s2 == 1'b1) begin // valid stop bit
                            rx_data  <= shreg;
                            rx_valid <= 1'b1;
                        end
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule


// -----------------------------------------------------------------------------
// audio: command layer for the game.
//
// Drive the cmd_* inputs with ONE-CYCLE pulses (e.g. from control.v state
// transitions). Requests are latched, so pulses that arrive while a byte is
// still being sent are queued, not dropped. If several are pending at once
// they are sent in the order: stop, load, play, pause, resume.
//
// audio_ready goes high when the laptop answers 'K' to a load, and is cleared
// when a new load is requested. audio_error goes high on 'E'.
// -----------------------------------------------------------------------------
module audio #(
    parameter CLKS_PER_BIT = 868            // 100 MHz / 115200 baud
)(
    input  wire       clk,
    input  wire       rst,

    // commands from the game (1-cycle pulses)
    input  wire       cmd_load,
    input  wire [3:0] song_id,              // 0-9, sampled when cmd_load pulses
    input  wire       cmd_play,
    input  wire       cmd_stop,
    input  wire       cmd_pause,
    input  wire       cmd_resume,

    // status back to the game
    output reg        audio_ready,
    output reg        audio_error,
    output wire       busy,                 // a command is pending or sending

    // raw receive (for debugging / extra commands)
    output wire [7:0] rx_data,
    output wire       rx_valid,

    // UART pins
    input  wire       RsRx,
    output wire       RsTx
);
    // ASCII command bytes
    localparam [7:0] CH_L = "L", CH_P = "P", CH_S = "S", CH_H = "H",
                     CH_R = "R", CH_K = "K", CH_E = "E", CH_0 = "0";

    // ---------------- UART instances ----------------
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy, tx_done;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(RsTx), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst),
        .rx(RsRx), .rx_data(rx_data), .rx_valid(rx_valid)
    );

    // ---------------- pending request latches ----------------
    reg       pend_load, pend_play, pend_stop, pend_pause, pend_resume;
    reg [3:0] pend_song;

    // ---------------- send FSM ----------------
    localparam S_IDLE  = 3'd0,
               S_SEND1 = 3'd1,   // pulse tx_start for first byte
               S_WAIT1 = 3'd2,   // wait for tx_done
               S_SEND2 = 3'd3,   // second byte (song id for 'L')
               S_WAIT2 = 3'd4;

    reg [2:0] state;
    reg [7:0] byte1, byte2;
    reg       two_bytes;

    wire any_pending = pend_load | pend_play | pend_stop | pend_pause | pend_resume;
    assign busy = any_pending | (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            pend_load   <= 1'b0;
            pend_play   <= 1'b0;
            pend_stop   <= 1'b0;
            pend_pause  <= 1'b0;
            pend_resume <= 1'b0;
            pend_song   <= 4'd0;
            state       <= S_IDLE;
            tx_start    <= 1'b0;
            tx_data     <= 8'd0;
            byte1       <= 8'd0;
            byte2       <= 8'd0;
            two_bytes   <= 1'b0;
            audio_ready <= 1'b0;
            audio_error <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            // ---- receive side ----
            if (rx_valid) begin
                if (rx_data == CH_K) audio_ready <= 1'b1;
                if (rx_data == CH_E) audio_error <= 1'b1;
            end

            // ---- send FSM ----
            case (state)
                S_IDLE: begin
                    // pick one pending command (stop has highest priority)
                    if (pend_stop) begin
                        pend_stop <= 1'b0; byte1 <= CH_S; two_bytes <= 1'b0; state <= S_SEND1;
                    end else if (pend_load) begin
                        pend_load <= 1'b0; byte1 <= CH_L; byte2 <= CH_0 + pend_song;
                        two_bytes <= 1'b1; state <= S_SEND1;
                    end else if (pend_play) begin
                        pend_play <= 1'b0; byte1 <= CH_P; two_bytes <= 1'b0; state <= S_SEND1;
                    end else if (pend_pause) begin
                        pend_pause <= 1'b0; byte1 <= CH_H; two_bytes <= 1'b0; state <= S_SEND1;
                    end else if (pend_resume) begin
                        pend_resume <= 1'b0; byte1 <= CH_R; two_bytes <= 1'b0; state <= S_SEND1;
                    end
                end
                S_SEND1: begin
                    tx_data  <= byte1;
                    tx_start <= 1'b1;
                    state    <= S_WAIT1;
                end
                S_WAIT1: if (tx_done) state <= two_bytes ? S_SEND2 : S_IDLE;
                S_SEND2: begin
                    tx_data  <= byte2;
                    tx_start <= 1'b1;
                    state    <= S_WAIT2;
                end
                S_WAIT2: if (tx_done) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase

            // ---- latch new requests (after the FSM so a new pulse in the
            //      same cycle a request is consumed is not lost) ----
            if (cmd_stop)   pend_stop   <= 1'b1;
            if (cmd_play)   pend_play   <= 1'b1;
            if (cmd_pause)  pend_pause  <= 1'b1;
            if (cmd_resume) pend_resume <= 1'b1;
            if (cmd_load) begin
                pend_load   <= 1'b1;
                pend_song   <= (song_id > 4'd9) ? 4'd9 : song_id;
                audio_ready <= 1'b0;      // must wait for new 'K'
                audio_error <= 1'b0;
            end
        end
    end
endmodule
