`timescale 1ns / 1ps
module integration_tb;
    reg clk=0, reset=1, rx=1;
    wire tx;
    wire [15:0] led;
    wire [3:0] cols;
    reg [3:0] held=0;
    wire [3:0] rows={3'b111, !((held[0] && cols[3] === 1'b0) ||
        (held[1] && cols[2] === 1'b0) || (held[2] && cols[1] === 1'b0) ||
        (held[3] && cols[0] === 1'b0))};
    wire [7:0] command;
    wire command_valid;
    integer commands=0;
    reg [31:0] first_target;
    always #5 clk=~clk;
    veribeat #(.KEYPAD_COL_CYCLES(50),.UART_CLKS_PER_BIT(8),.CYCLES_PER_MS(100000)) dut (
        .clk(clk),.btnC(reset),.btnU(1'b0),.btnL(1'b0),.btnR(1'b0),.btnD(1'b0),
        .RsRx(rx),.RsTx(tx),.rows(rows),.cols(cols),.led(led)
    );
    uart_rx #(.CLKS_PER_BIT(8)) monitor(clk,reset,tx,command,command_valid);
    always @(negedge clk) if(command_valid) begin
        case(commands)
            0: if(command !== "S") $stop;
            1: if(command !== "L") $stop;
            2: if(command !== "0") $stop;
            default: begin end
        endcase
        commands=commands+1;
    end
    task send_ready;
        integer bit_index;
        reg [7:0] value;
        begin
            value="K";
            @(negedge clk); rx=0;
            repeat(8) @(negedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                rx=value[bit_index]; repeat(8) @(negedge clk);
            end
            rx=1; repeat(10) @(negedge clk);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); reset=0;
        wait(commands==3);
        if(dut.game.running) $stop;
        send_ready;
        wait(dut.game.running);
        // Advance to the first chart note while exercising the real VGA,
        // scanner, UART handshake and bank publish signals.
        first_target=dut.game.chart.chart[0][33:2]+32'd1400;
        force dut.game.elapsed_ms=first_target;
        held=4'b0001 << dut.game.chart.chart[0][1:0];
        wait(dut.game.points==1);
        held=0;
        wait(dut.game.front_valid);
        if(dut.game.overrun || dut.game.failed) $stop;
        $display("PASS: UART load/ready, real keypad input, VGA-frame scan/publish and score");
        $finish;
    end
    initial begin #40000000; $display("FAIL integration timeout"); $stop; end
endmodule
