`timescale 1ns / 1ps
module menu_display_tb;
    reg clk=0, reset=1;
    reg [9:0] x=0,y=0;
    reg [1:0] screen=0,song=0;
    reg failed=0;
    wire [11:0] color;
    integer column,row,file;
    always #5 clk=~clk;
    menu_display dut(clk,reset,x,y,screen,song,failed,16'h1234,16'h0056,16'h0789,color);
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
        check_pixel(256,64,12'h6ef); // V in VERIBEAT.
        check_pixel(260,64,12'h124); // Space between V's top strokes.
        check_pixel(112,180,12'h6ef); // Selection card edge.
        screen=2;
        check_pixel(144,176,12'hfff); // HITS label.
        check_pixel(400,176,12'h113); // First digit 1, top left is blank.
        check_pixel(404,176,12'hfff); // First digit 1, top center is lit.
        check_pixel(448,176,12'hfff); // Last digit 4.
        check_pixel(144,304,12'hfff); // MISCLICKS label.
        if($test$plusargs("render")) begin
            render(0,"/private/tmp/veribeat-home.ppm");
            render(2,"/private/tmp/veribeat-results.ppm");
        end
        $display("PASS: home menu labels, results labels and decimal statistics pixels");
        $finish;
    end
endmodule
