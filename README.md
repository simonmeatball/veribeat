# veribeat

## VGA bring-up (Basys 3)

The initial design displays eight vertical color bars with a one-pixel white
border. The center button resets the display; releasing it restarts the raster.

- `clock.v`: synchronizes reset release and produces `pixel_tick`, a one-cycle
  enable every four cycles of the board's 100 MHz oscillator.
- `vga.v`: 640x480 timing, active-low sync, visible-area flag, frame enable,
  coordinates, and 4-bit-per-channel RGB blanking.
- `veribeat.v`: top module connecting the clock, timing, and test pattern.
- `basys3.xdc`: oscillator, center-button, and VGA pin constraints.

All sequential logic uses `posedge clk` at 100 MHz. `pixel_tick` is a clock
enable, not a separate clock. This avoids routing a logic divider as a clock.
The effective pixel rate is 25 MHz, matching the simple VGA example in the
[Digilent Basys 3 reference manual](https://digilent.com/reference/_media/basys3%3Abasys3_rm.pdf).
This produces 31.25 kHz horizontal sync and approximately 59.52 Hz refresh.
The standard nominal VGA pixel clock is 25.175 MHz; if the particular monitor
does not lock to 25 MHz, use a Clocking Wizard/MMCM for 25.175 or 25.2 MHz,
run the VGA controller on that clock, and tie its `pixel_tick` high.
Synchronize reset release to that new clock and hold reset until the MMCM locks.

| Timing interval | Horizontal (pixels) | Vertical (lines) |
| --- | ---: | ---: |
| Visible | 640 | 480 |
| Front porch | 16 | 10 |
| Sync pulse (low) | 96 | 2 |
| Back porch | 48 | 33 |
| Total | 800 | 525 |

The supplied Dell part number appears to identify a 1907FP-series monitor;
confirm the model on its label. The
[Dell 1907FP manual](https://downloads.dell.com/manuals/all-products/esuprt_electronics/esuprt_display/dell-1907fp_user%27s%20guide_en-us.pdf)
lists 640x480 at 60 Hz as a supported mode (25.2 MHz rounded pixel clock).
Hardware compatibility with this specific unit still needs a board test.
Pin assignments follow
[Digilent's master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc).

### Program the board

1. Create a Vivado RTL project for Basys 3 (`xc7a35tcpg236-1`).
2. Add `clock.v`, `vga.v`, and `veribeat.v` as design sources and select
   `veribeat` as the top module. Add `basys3.xdc` as constraints.
3. Run synthesis, implementation, and bitstream generation; check timing.
4. Connect the board's VGA port to the Dell's VGA input and select Analog/VGA
   on the monitor. Program the Basys 3 through Vivado Hardware Manager.
5. Expect white, yellow, cyan, green, magenta, red, blue, and black bars from
   left to right, surrounded by a white border. Hold the center button to blank
   the display; release it to restart.

### Connect the game renderer

Replace the combinational color-bar logic in `veribeat.v` with the renderer in
`display.v`. Compute RGB from the **current** `x` and `y`; valid visible
coordinates are `x=0..639`, `y=0..479` when `video_on` is high. Coordinates
continue through the blanking intervals (`x=0..799`, `y=0..524`), and `vga.v`
forces RGB to zero outside the visible region. A registered renderer or
synchronous ROM needs corresponding timing/coordinate pipeline alignment.

`frame_tick` is high for one 100 MHz cycle immediately before the raster wraps
from `(799,524)` to `(0,0)`. Use `if (frame_tick)` inside a `posedge clk` block
to update game state once per frame. Game state should remain stable during
the visible frame to avoid tearing.

### Simulation

With Icarus Verilog installed, run from this directory:

```sh
iverilog -g2012 -Wall -s vga_tb -o /tmp/veribeat-vga-test clock.v vga.v veribeat.v tests/vga_tb.sv
vvp /tmp/veribeat-vga-test
```

The testbench checks startup, reset assertion/release, enable spacing,
coordinate progression, complete frame lengths, sync intervals, visible pixel
counts, color bars, and RGB blanking over three complete frames including a
reset during an additional partial frame. Add `tests/vga_tb.sv` as a simulation
source only if running the test in Vivado.

Validated with Icarus Verilog 13.0: PASS across three complete frames and
5,052,352 system-clock cycles. The design sources also compile in Verilog-2005
mode without warnings. Vivado synthesis, timing closure, and physical monitor
operation have not yet been verified.
