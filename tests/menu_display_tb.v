`timescale 1ns / 1ps
module menu_display_tb;
    reg clk=0, reset=1;
    reg [9:0] x=0,y=0;
    reg [1:0] screen=0,song=0;
    reg failed=0;
    wire [11:0] color;
    integer column,row,file;
    always #5 clk=~clk;
    wire hud_pixel;
    menu_display dut(.clk(clk),.reset(reset),.x(x),.y(y),.screen(screen),.song(song),.failed(failed),
        .hit_digits(16'h0843),.miss_digits(16'h0011),.misclick_digits(16'h0027),
        .score_digits(24'h123400),.combo_digits(16'h0042),.longest_digits(16'h0321),
        .hud_pixel(hud_pixel),.color(color));
    task check_pixel;
        input [9:0] px,py;
        input [11:0] expected;
        begin
            @(negedge clk); x=px; y=py;
            repeat(3) @(negedge clk);
            if(color !== expected) begin
                $display("FAIL menu pixel %0d,%0d: %h expected %h",px,py,color,expected);
                $stop;
            end
        end
    endtask
    task render;
        input [1:0] mode;
        input [511:0] path;
        begin
            screen=mode;
            file=$fopen(path,"w");
            $fwrite(file,"P3\n640 480\n15\n");
            for(row=0;row<480;row=row+1)
                for(column=0;column<640;column=column+1) begin
                    x=column; y=row;
                    repeat(4) @(negedge clk);
                    $fwrite(file,"%0d %0d %0d\n",color[11:8],color[7:4],color[3:0]);
                end
            $fclose(file);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        // Layout, character, and glyph each occupy a distinct clock stage.
        x=256; y=64;
        repeat(2) begin
            @(negedge clk);
            if(color !== 12'h012) begin
                $display("FAIL: menu pipeline collapsed before the third stage"); $stop;
            end
        end
        @(negedge clk);
        if(color !== 12'h6ef) begin
            $display("FAIL: menu pixel did not settle within three stages"); $stop;
        end
        check_pixel(256,64,12'h6ef); // V in VERIBEAT.
        check_pixel(260,64,12'h124); // Space between V's top strokes.
        check_pixel(112,180,12'h6ef); // Selection card edge.
        screen=1;
        check_pixel(64,15,12'hfff); // Live SCORE label.
        check_pixel(352,15,12'h6ef); // Live COMBO label.
        check_pixel(448,15,12'h6ef); // Combo digits use cyan.
        if(!hud_pixel) $stop;
        screen=2;
        check_pixel(112,160,12'hfff); // SCORE label.
        check_pixel(400,160,12'h124); // First score digit 1, top left is blank.
        check_pixel(404,160,12'hfff); // First score digit 1, top center is lit.
        check_pixel(480,160,12'hfff); // Sixth score digit 0.
        check_pixel(112,200,12'hfff); // HITS label.
        check_pixel(112,240,12'hfff); // MISSES label.
        check_pixel(112,280,12'hfff); // MISCLICKS label.
        check_pixel(112,320,12'hfff); // BEST STREAK label.
        check_pixel(480,320,12'h124); // Final best-streak digit 1, top left blank.
        check_pixel(484,320,12'hfff);
        if(hud_pixel) $stop;
        if($test$plusargs("render")) begin
            render(0,"/private/tmp/veribeat-home.ppm");
            render(2,"/private/tmp/veribeat-results.ppm");
        end
        $display("PASS: home menu, live score/combo HUD, six-digit score and all five result statistics");
        $finish;
    end
endmodule
