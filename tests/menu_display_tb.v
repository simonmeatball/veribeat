`timescale 1ns / 1ps
module menu_display_tb;
    reg clk=0, reset=1;
    reg [9:0] x=0,y=0;
    reg [2:0] screen=0;
    reg [1:0] song=0,countdown=3;
    reg failed=0;
    reg [9:0] progress_pixels=0;
    reg [7:0] grade="S";
    reg [11:0] judgments=0;
    reg [19:0] judgment_ages={4{5'd31}};
    wire [11:0] color;
    integer column,row,file;
    always #5 clk=~clk;
    wire hud_pixel;
    menu_display dut(.clk(clk),.reset(reset),.x(x),.y(y),.screen(screen),.song(song),.failed(failed),
        .hit_digits(16'h0843),.miss_digits(16'h0011),.misclick_digits(16'h0027),
        .score_digits(24'h123400),.combo_digits(16'h0042),.longest_digits(16'h0321),
        .progress_pixels(progress_pixels),
        .countdown(countdown),
        .grade(grade),.judgments(judgments),.judgment_ages(judgment_ages),
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
        input [2:0] mode;
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
        check_pixel(62,6,12'hb8f); // Progress border.
        check_pixel(64,6,12'h235); // Empty at audio start.
        progress_pixels=256;
        check_pixel(319,6,12'h6ef); // Last filled pixel at halfway.
        check_pixel(320,6,12'h235); // First unfilled pixel at halfway.
        progress_pixels=512;
        check_pixel(575,6,12'h6ef); // Full at the end of the song.
        check_pixel(577,6,12'hb8f); // Right border stays visible.
        check_pixel(578,6,12'h012); // Outside the track.
        check_pixel(64,15,12'hfff); // Live SCORE label.
        check_pixel(352,15,12'h6ef); // Live COMBO label.
        check_pixel(448,15,12'h6ef); // Combo digits use cyan.
        if(!hud_pixel) $stop;
        judgments={`JUDGMENT_MISS,`JUDGMENT_GOOD,`JUDGMENT_GREAT,`JUDGMENT_PERFECT};
        judgment_ages=0;
        check_pixel(72,376,12'hfff); // PERFECT in lane 0.
        if(!hud_pixel) $stop;
        check_pixel(84,376,12'h113); // Character gap leaves the tile layer visible.
        if(hud_pixel) $stop;
        check_pixel(216,376,12'h6ef); // GREAT in lane 1.
        check_pixel(352,376,12'hb8f); // GOOD in lane 2.
        check_pixel(480,376,12'hf44); // MISS in lane 3.
        judgments[2:0]=`JUDGMENT_BAD;
        check_pixel(104,376,12'hf44);
        judgment_ages={4{5'd30}};
        check_pixel(104,376,12'h113);
        if(hud_pixel) $stop;
        screen=2;
        check_pixel(464,64,12'hfff); // GRADE label.
        check_pixel(492,96,12'h6ef); // Large S.
        grade="A";
        check_pixel(492,96,12'h124); // A starts with an empty top-left cell.
        check_pixel(500,96,12'h6ef);
        grade="F";
        check_pixel(492,96,12'hf44);
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
        screen=4;
        check_pixel(272,64,12'h6ef); // PAUSED title.
        check_pixel(112,180,12'h6ef); // Menu card outline.
        check_pixel(164,176,12'hfff); // Key 1: continue.
        check_pixel(160,256,12'hfff); // Key 2: restart.
        check_pixel(160,336,12'hfff); // Key 3: main menu.
        if(hud_pixel) $stop;
        screen=5;
        check_pixel(308,224,12'h6ef); // Large 3, top stroke.
        countdown=2;
        check_pixel(308,240,12'h6ef); // Large 2, middle stroke.
        countdown=1;
        check_pixel(308,224,12'h124); // Large 1, top-left blank.
        check_pixel(316,224,12'h6ef); // Large 1, center lit.
        if($test$plusargs("render")) begin
            render(0,"/private/tmp/veribeat-home.ppm");
            render(2,"/private/tmp/veribeat-results.ppm");
            render(4,"/private/tmp/veribeat-paused.ppm");
            render(5,"/private/tmp/veribeat-countdown.ppm");
        end
        $display("PASS: home menu, live score/combo HUD, six-digit score and all five result statistics");
        $finish;
    end
endmodule
