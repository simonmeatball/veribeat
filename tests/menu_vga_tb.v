`timescale 1ns / 1ps
module menu_vga_tb #(parameter HUD=0, PAUSE_MENU=0, COUNTDOWN=0);
    reg clk=0,reset=1;
    wire [3:0] red,green,blue;
    reg [11:0] expected;
    reg check;
    integer checks=0;
    always #5 clk=~clk;
    veribeat dut(.clk(clk),.btnC(reset),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.btnD(1'b0),
        .RsRx(1'b1),.RsTx(),.rows(4'hf),.cols(),.led(),.Hsync(),.Vsync(),
        .vgaRed(red),.vgaGreen(green),.vgaBlue(blue));
    initial begin
        repeat(5) @(negedge clk); reset=0;
        if(HUD) begin
            force dut.screen=1;
            force dut.progress_pixels=10'd256;
        end else if(PAUSE_MENU) begin
            force dut.screen=4;
        end else if(COUNTDOWN) begin
            force dut.screen=5;
            force dut.countdown=2'd3;
        end
    end
    always @(posedge clk) begin
        check=0;
        if(!dut.reset && dut.pixel_tick && HUD && dut.screen==1) begin
            if(dut.y==6) begin
                case(dut.x)
                    62,577: begin expected=12'hb8f; check=1; end
                    64,319: begin expected=12'h6ef; check=1; end
                    320,575: begin expected=12'h235; check=1; end
                    default: begin end
                endcase
            end
            if(dut.y==15) begin
                case(dut.x)
                    64,160: begin expected=12'hfff; check=1; end
                    352,448: begin expected=12'h6ef; check=1; end
                    default: begin end
                endcase
            end
            if(dut.x==64 && dut.y==47) begin expected=12'h012; check=1; end
            if(dut.x==64 && dut.y==48) begin expected=12'h436; check=1; end
            if(dut.x==80 && dut.y==48) begin expected=12'h113; check=1; end
        end
        if(!dut.reset && dut.pixel_tick && PAUSE_MENU && dut.screen==4) begin
            if(dut.y==64 && dut.x==272) begin expected=12'h6ef; check=1; end
            if(dut.y==180 && (dut.x==112 || dut.x==527)) begin expected=12'h6ef; check=1; end
            if(dut.y==176 && dut.x==164) begin expected=12'hfff; check=1; end
            if(dut.y==256 && dut.x==160) begin expected=12'hfff; check=1; end
        end
        if(!dut.reset && dut.pixel_tick && COUNTDOWN && dut.screen==5) begin
            if(dut.y==224 && dut.x==308) begin expected=12'h6ef; check=1; end
            if(dut.y==224 && dut.x==331) begin expected=12'h6ef; check=1; end
            if(dut.y==224 && dut.x==332) begin expected=12'h124; check=1; end
        end
        if(!dut.reset && dut.pixel_tick && !HUD && !PAUSE_MENU && !COUNTDOWN && dut.screen==0) begin
            if(dut.y==180) begin
                case(dut.x)
                    111,528: begin expected=12'h113; check=1; end
                    112,527: begin expected=12'h6ef; check=1; end
                    113: begin expected=12'h235; check=1; end
                    default: begin end
                endcase
            end
            if(dut.y==64 && dut.x==256) begin expected=12'h6ef; check=1; end
            if(dut.y==64 && dut.x==260) begin expected=12'h124; check=1; end

        end
            if(check) begin
                #1;
                if({red,green,blue} !== expected) begin
                    $display("FAIL: menu pipeline and registered VGA pixel are misaligned"); $stop;
                end
                checks=checks+1;
                if(checks==(HUD ? 13 : PAUSE_MENU ? 5 : COUNTDOWN ? 3 : 7)) begin
                    $display("PASS: menu text/card boundaries align with registered VGA RGB"); $finish;
                end
            end
    end
    initial begin #10000000; $display("FAIL: menu VGA timeout"); $stop; end
endmodule
