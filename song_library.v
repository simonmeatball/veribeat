`timescale 1ns / 1ps
`default_nettype none
`include "song_library_config.vh"

module song_library #(
    parameter SONG0_FILE = "charts/song_0.mem",
    parameter SONG1_FILE = "charts/song_1.mem",
    parameter SONG2_FILE = "charts/song_2.mem"
) (
    input wire clk,
    input wire [1:0] song,
    input wire enable,
    input wire [9:0] address,
    output reg [39:0] data,
    output reg [10:0] note_count,
    output reg [31:0] duration_ms
);
    wire [39:0] data0, data1, data2;
    notes #(.CHART_FILE(SONG0_FILE)) song0(clk,enable && song==0,address,data0);
    notes #(.CHART_FILE(SONG1_FILE)) song1(clk,enable && song==1,address,data1);
    notes #(.CHART_FILE(SONG2_FILE)) song2(clk,enable && song==2,address,data2);
    // Selection stays fixed for the entire run, including synchronous ROM reads.
    always @* begin
        case(song)
            1: begin
                data=data1;
                note_count=`SONG_1_NOTE_COUNT;
                duration_ms=`SONG_1_DURATION_MS;
            end
            2: begin
                data=data2;
                note_count=`SONG_2_NOTE_COUNT;
                duration_ms=`SONG_2_DURATION_MS;
            end
            default: begin
                data=data0;
                note_count=`SONG_0_NOTE_COUNT;
                duration_ms=`SONG_0_DURATION_MS;
            end
        endcase
    end
endmodule
`default_nettype wire
