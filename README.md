# veribeat

## Veribeat VGA demo (Basys 3)

The default `veribeat` top runs an eight-note test chart, including a two-lane
chord. Press the matching lane when the bottom edge of a tile reaches the
purple line. Presses within six frames of the target count (about 100 ms
early or late). Each hit adds one point and sends a white ring out from the pad.
An expired note or an unmatched press sends a red ring. The center button
resets the score and restarts the chart. The chart runs on VGA frames and
has no song synchronization yet.

- `notes.v` supplies the demo chart.
- `control.v` buffers presses, times notes, and tracks one 12-frame pulse per lane.
- `display.v` draws the four lanes, labeled pads, tiles, score, and pulses.
- `score.v` counts successful notes.

### Vivado project setup

Create an RTL project for the Basys 3 part `xc7a35tcpg236-1`. For the game,
add `clock.v`, `vga.v`, `veribeat.v`, `input.v`, `notes.v`, `control.v`,
`score.v`, and `display.v` as Design Sources. Set `veribeat` as the synthesis
top and enable only `basys3.xdc` in the active constraint set.

For the standalone audio test, use `audio.v` and `audio_test.v` with
`audio_test` as the synthesis top and only `audio_test.xdc` enabled. The game
and audio test have different top-level ports. Loading both constraint
files into one run leaves some `get_ports` queries empty and produces
`set_property` warnings.

If you copied sources into the Vivado project, make sure the active
constraints use the updated copy. For an unsupported-command warning,
open the file and line shown in the synthesis log. Keep Tcl control flow
such as `if` in a separate Tcl script and keep pin assignments in the XDC.

### Numpad interface

Connect the PmodKYPD to header JB using the existing pin assignments in
`basys3.xdc`. Add `input.v` alongside the game and VGA sources in Vivado.
The default `veribeat` top scans the keypad and shows its bottom-row key
labels on the VGA pads.

| Lane (left to right) | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| Key | `0` | `F` | `E` | `D` |

The scanner and game share the 100 MHz clock and synchronized reset. The
scanner sends a one-cycle pulse per debounced press. The game buffers those
pulses until the next VGA frame and can judge presses on multiple lanes in
the same frame. At the default scan rate, two matching sweeps debounce each press. The
key column and scan phase affect when the pulse arrives.

```sh
iverilog -g2005 -Wall -s game_tb -o /tmp/veribeat-game-test \
  clock.v vga.v veribeat.v input.v notes.v control.v score.v display.v tests/game_tb.v
vvp -N /tmp/veribeat-game-test
iverilog -g2005 -Wall -s keypad_tb -o /tmp/veribeat-keypad-test input.v tests/keypad_tb.v
vvp -N /tmp/veribeat-keypad-test
```

## VGA diagnostic (Basys 3)

The diagnostic is selected with the `DIAGNOSTIC=1` top-level parameter.
The keypad column pins are high impedance in this mode.

The diagnostic displays eight vertical color bars, a stationary 64-pixel grid,
a one-pixel white border, and a bouncing 64x64 white square. The square moves
2 pixels horizontally and 1 pixel vertically per frame; the background stays fixed. The center button resets the display; releasing it restarts the raster.

- `clock.v`: exposes real `CLK_100MHz`, `CLK_50MHz`, and `CLK_25MHz` outputs,
  synchronizes reset release, and produces the 25 MHz `pixel_tick` enable.
  Simple counters toggle the outputs, following the lab clock-module style.
- `vga.v`: 640x480 timing, active-low sync, visible-area flag, frame enable,
  coordinates, and registered 4-bit-per-channel RGB blanking.
- `veribeat.v`: top module connecting the clock, game or diagnostic renderer, and timing.
- `basys3.xdc`: oscillator, center-button, and VGA pin constraints.

All sequential logic uses `posedge clk` at 100 MHz. `pixel_tick` is a clock
enable, not a separate clock. This avoids routing a logic divider as a clock.
The effective pixel rate is 25 MHz, matching the simple VGA example in the
[Digilent Basys 3 reference manual](https://digilent.com/reference/_media/basys3%3Abasys3_rm.pdf).
The named clocks are 50% duty-cycle waveforms, distinct from `pixel_tick`.
Divided clocks stop low during reset (after the next input edge), then restart.
`CLK_50MHz` toggles every input cycle; `CLK_25MHz` toggles every two input cycles.
To add an output, declare a counter and an output register, initialize/reset
both to zero, and toggle the output whenever the counter reaches `N - 1`.
The resulting frequency is `100,000,000 / (2 * N)` Hz. Give the counter enough
bits to hold `N - 1`.

The current top keeps all logic on 100 MHz with enables. If future logic uses
a divided output as its actual clock, add appropriate clock buffering, a
generated-clock constraint, and reset synchronization for that domain.
Non-integer division ratios require an MMCM/Clocking Wizard.

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

1. Follow the [Vivado project setup](#vivado-project-setup) for the game.
2. Set the top-level generic `DIAGNOSTIC=1` in the synthesis settings.
3. Run synthesis, implementation, and bitstream generation; check timing.
4. Connect the board's VGA port to the Dell's VGA input and select Analog/VGA
   on the monitor. Program the Basys 3 through Vivado Hardware Manager.
5. Expect white, yellow, cyan, green, magenta, red, blue, and black bars from
   left to right with a fixed grid and white border. A white square should move
   diagonally and bounce inside the border. Hold the center button to blank
   the display; release it to restart the pattern.

### VGA renderer timing

The renderer in `display.v` computes RGB from the **current** `x` and `y`; valid visible
coordinates are `x=0..639`, `y=0..479` when `video_on` is high. Coordinates
continue through the blanking intervals (`x=0..799`, `y=0..524`), and `vga.v`
registers RGB and both sync outputs together once per pixel. The connector
outputs have one pixel of latency relative to `x`/`y`; blanking and sync receive
that same delay, preserving alignment. Outputs hold between pixel updates,
preventing combinational decode glitches from reaching the connector.
A registered renderer or
synchronous ROM needs corresponding timing/coordinate pipeline alignment.

`frame_tick` is high for one 100 MHz cycle immediately before the raster wraps
from `(799,524)` to `(0,0)`. Use `if (frame_tick)` inside a `posedge clk` block
to update game state once per frame. Game state should remain stable during
the visible frame to avoid tearing.

### Simulation

The testbench uses Verilog-2005. With Icarus Verilog installed, run from this directory:

```sh
iverilog -g2005 -Wall -s vga_tb -o /tmp/veribeat-vga-test clock.v vga.v veribeat.v tests/vga_tb.v
vvp -N /tmp/veribeat-vga-test
iverilog -g2005 -Wall -s clock_tb -o /tmp/veribeat-clock-test clock.v tests/clock_tb.v
vvp -N /tmp/veribeat-clock-test
```

`vvp -N` makes a failing testbench `$stop` exit with a nonzero status.

The testbench checks startup, reset assertion/release, enable spacing,
coordinate progression, complete frame lengths, sync intervals, visible pixel
counts, named-clock waveforms, registered RGB/sync alignment, animation,
bounces, and RGB blanking over three complete frames including a
reset during an additional partial frame. The test starts the square near the
bottom-right corner to exercise both bounces without simulating hundreds of frames. Add `tests/vga_tb.v` as a simulation
source only if running the test in Vivado, selecting `vga_tb` as simulation top.
The separate `clock_tb` tests the 25/50/100 MHz outputs, pixel enable, and reset;
select it as simulation top to run that test.

Validated with Icarus Verilog 13.0: PASS across three complete frames and
5,052,352 system-clock cycles (counter-based clock implementation). The design sources and testbench compile in Verilog-2005
mode without warnings. Vivado synthesis, timing closure, and physical monitor
operation have not yet been verified.

### Checking jitter on the monitor

Rebuild and program the new bitstream. The fixed grid/border should stay still
while the square moves in uniform frame-sized steps. A split/discontinuity in
its edge suggests tearing; shimmer on stationary edges points toward signal or
monitor sampling issues. This visual test cannot measure electrical clock jitter.

First reseat both VGA connectors and tighten their screws; try another direct
VGA cable if available. Run the Dell's Auto Adjust, then adjust Image Settings >
Pixel Clock and Phase if necessary. Dell's manual specifically recommends these
controls for shaky/jittery video. The registered outputs remove a possible
logic-side source of glitches; they do not establish the cause of the observed
hardware symptom. The pixel rate remains 25 MHz (59.52 Hz frames). If jitter
persists after cable/monitor checks and Vivado timing passes, try a standards-
aligned 25.175/25.2 MHz MMCM pixel clock as the next controlled comparison.
