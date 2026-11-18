# veribeat

## Veribeat game (Basys 3)

The game accepts up to 1,024 tap notes from a text chart. Press the matching
bottom-row keypad key when a cyan tile reaches the purple line. The hit
window is ±100 ms. A hit adds one point and flashes white. A missed note or
unmatched press flashes red. The score supports 0–1024.

The supplied [song_0 chart](charts/song_0.txt) contains 854 notes matched to
spectral attacks in `audio/songs/song_0.mp3`, YOASOBI's Yoru ni Kakeru. Analysis
of this exact file found a tempo near 130 BPM and 262.177 seconds of decoded
audio. The chart follows beats, stronger eighth notes, and syncopated accents,
with 32 two-key chords. Same-key presses are separated by at least 220 ms.
Its current hardware calibration offset is zero. The arrangement is generated
from audio analysis and still benefits from a listening/playtesting pass.

The [analysis record](charts/song_0.analysis.json) stores the source MP3's
SHA-256 hash, timing statistics, and each selected attack. To regenerate the
arrangement, install the optional authoring dependencies `librosa`, `numpy`,
`scipy`, `soundfile`, and `imageio-ffmpeg`, then run the following command from
the repository root. This also regenerates the chart ROM and configuration.

```sh
python3 tools/match_song_chart.py audio/songs/song_0.mp3
```

### Edit and compile charts

```text
# target_ms lane, measured from audio playback start
song_id 0
duration_ms 262177
audio_offset_ms 0
1500 0
2000 1
2500 1
2500 2
```

Lane 0 is the leftmost lane. Equal times on different lanes form chords.
Keep times sorted. Positive `audio_offset_ms` moves notes later relative to
the FPGA's playback command. The compiler checks capacity, lane numbers,
duplicates, metadata, and adjusted note times.

Run from the repository root after editing a chart.

```sh
python3 tools/compile_chart.py charts/song_0.txt
```

This generates `notes_data.mem` (1,024 padded 40-bit words) and
`notes_config.vh` (note count, song ID, duration). `notes.v` reads the memory
at build time. Rebuild and program the FPGA after changing the chart.

### Vivado project setup

Create an RTL project for Basys 3 part `xc7a35tcpg236-1`. Add these design
sources and set `veribeat` as the synthesis top.

```text
clock.v          vga.v          veribeat.v
input.v          notes.v        control.v
tile_mask.v      display.v      score.v
game_session.v   audio.v
```

Add `notes_config.vh` as a Verilog header and its directory to the project's
Verilog include directories. Add `notes_data.mem` as a Memory Initialization
File. The top-level `CHART_FILE` parameter defaults to `notes_data.mem`.
For simulation, run from the repository root. If a Vivado flow cannot
resolve the memory file, set `CHART_FILE` to its absolute path or place the
file in the run directory. Verify the synthesis log successfully reads it.

Use **only `basys3.xdc`** as the active constraint file. UART, board buttons,
and status LED pins from `audio_test.xdc` have been consolidated into it.
The old audio-test XDC has been removed. The standalone test's switches
are unused by the integrated game and have no active constraints. The
legacy `audio_test.v` remains available as a standalone test design, which
requires a constraint set matching its own ports.

If the Vivado project copied sources, update the active project copies.
Reset synthesis and implementation after updating the RTL. Check post-route
setup/hold timing and inferred ROM/RAM resources before generating a bitstream.
Testbench files belong under Simulation Sources.

### Keypad and audio controls

Connect the PmodKYPD to JB. The scanner sends synchronized, debounced pulses.
The controller buffers pulses even while scanning the chart.

| Lane, left to right | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| Key | `0` | `F` | `E` | `D` |

Start the laptop player before resetting the FPGA.

```sh
python3 audio/audio_player.py
```

It uses the existing USB-UART protocol at 115200 baud to play
`audio/songs/song_0.mp3`. After reset, the FPGA stops previous playback,
loads the chart's song ID, waits for the player's ready response, and runs
a 1.4-second visual pre-roll before sending PLAY. The song clock uses the
100 MHz oscillator to count milliseconds. Audio startup latency needs
on-board calibration using `audio_offset_ms`.

| Board button | Action |
| --- | --- |
| Center | Reset the FPGA game and audio interface |
| Up | Stop, reload, and restart the chart |
| Left | Pause chart time and audio |
| Right | Resume |
| Down | Stop |

LEDs 0–10 show the binary score. LEDs 11–15 show running, paused, finished,
audio failure, and renderer deadline failure respectively. An audio failure
requires a restart after correcting the player or song file. The game ends
when the configured track duration has elapsed, all notes have resolved,
and the feedback tail has elapsed.

### Architecture and simulation

`notes.v` supplies synchronous chart ROM. `control.v` scans it twice per
frame to judge notes and paint the next tile mask. `tile_mask.v` stores two
banks of four lane masks. A complete bank is published at VGA line 47,
before the playfield starts at line 48. An incomplete frame sets LED 15
and preserves the previous bank. The renderer uses distributed-memory row
reads, keeping the VGA timing interface's existing RGB/sync alignment.

Run the following commands from the repository root with Icarus Verilog.
The large-chart test populates a synthetic ROM in simulation, including a
maximum-density 1,024-note frame and a full game scoring 1024.

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
iverilog -g2005 -Wall -s game_tb -o /tmp/veribeat-game-test \
  notes.v control.v tile_mask.v score.v display.v tests/game_tb.v
vvp -N /tmp/veribeat-game-test
iverilog -g2005 -Wall -s chart_sizes_tb -o /tmp/veribeat-sizes-test \
  notes.v control.v score.v tests/chart_sizes_tb.v
vvp -N /tmp/veribeat-sizes-test
iverilog -g2005 -Wall -s session_tb -o /tmp/veribeat-session-test \
  game_session.v tests/session_tb.v
vvp -N /tmp/veribeat-session-test
iverilog -g2005 -Wall -s integration_tb -o /tmp/veribeat-integration-test \
  clock.v vga.v veribeat.v input.v notes.v control.v tile_mask.v \
  score.v display.v audio.v game_session.v tests/integration_tb.v
vvp -N /tmp/veribeat-integration-test
iverilog -g2005 -Wall -s keypad_tb -o /tmp/veribeat-keypad-test input.v tests/keypad_tb.v
vvp -N /tmp/veribeat-keypad-test
```

The integration simulation checks UART STOP/LOAD/ready, a real scanned keypad
press, scoring, and publication using the VGA raster. It advances song time
for the test. The session simulation checks the countdown, pause/resume,
restart, finish, and error handling. Physical audio alignment and Vivado
timing closure require board/tool verification.

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
