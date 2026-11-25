`timescale 1ns / 1ps
`default_nettype none

// Small distributed RAMs give combinational pixel reads with no VGA latency.
// The controller clears and paints the back bank before publishing it.
module tile_mask (
    input wire clk,
    input wire front_bank,
    input wire write_enable,
    input wire clear_pixel,
    input wire [10:0] write_address,
    input wire [1:0] write_bits,
    input wire [10:0] read_address,
    output wire [1:0] pixel
);
    (* ram_style = "distributed" *) reg [1:0] bank0 [0:2047];
    (* ram_style = "distributed" *) reg [1:0] bank1 [0:2047];
    always @(posedge clk) begin
        if (write_enable) begin
            if (front_bank)
                bank0[write_address] <= clear_pixel ? 2'b0 : bank0[write_address] | write_bits;
            else
                bank1[write_address] <= clear_pixel ? 2'b0 : bank1[write_address] | write_bits;
        end
    end
    assign pixel = front_bank ? bank1[read_address] : bank0[read_address];
endmodule

`default_nettype wire
