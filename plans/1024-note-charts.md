# Plan for text charts with up to 1,024 notes

**Created** November 18, 2026  
**Status** Proposed implementation

## Scope and loading workflow

Support 0–1,024 tap notes per chart across the existing four lanes. Preserve
white hit feedback, red miss feedback, simultaneous presses, and the relaxed
judgment window. A chart supplies timed input cues for a corresponding audio
track. The existing laptop audio player plays that track.

The initial workflow loads a text chart at build time. A Python compiler
validates the human-readable TXT and produces a memory initialization file
and chart metadata. `notes.v` loads the generated data with `$readmemh`, and
Vivado incorporates it into the bitstream. Changing the chart then requires
rebuilding and programming the board. Loading another TXT over USB while the
game is running would require a UART chart-upload protocol and writable
chart memory. That can be added after the build-time workflow works.

## Text chart format

Use `charts/song_0.txt`, paired with `audio/songs/song_0.mp3` or another audio
format supported by the player. Express note times as integer milliseconds
from the start of the audio track. Lane numbers 0–3 map left to right to
physical keys `0 F E D`.

```text
# Veribeat chart, version 1
song_id 0
duration_ms 180000
audio_offset_ms 0
# target_ms lane
1500 0
2000 1
2500 1
2500 2
3000 3
```

The two entries at 2500 ms form a chord. `audio_offset_ms` is a signed
calibration value added to chart target times, with a positive value making
notes arrive later relative to the FPGA playback-start reference.

The compiler will accept comments and blank lines and validate the following.

- At most 1,024 note entries, with lane values 0–3 and nonnegative times.
- Entries ordered by target time. Equal times on different lanes are allowed.
- Duplicate entries for the same time and lane produce a line-numbered error.
- Song ID matches the existing audio protocol's 0–9 range.
- Duration covers every target time after calibration.
- Time and duration calculations fit the hardware's chosen timestamp range.

Generate a fixed 1,024-word hexadecimal memory file, padding unused entries
with an invalid marker. Use a 40-bit word with a valid bit, five reserved bits,
a 32-bit target time, and a two-bit lane. Generate a small Verilog include
with the note count, song ID, duration, and audio offset. Use a 10-bit RAM
address and 11-bit counts so the value 1,024 is represented correctly.

## Hardware architecture

### Chart memory in `notes.v`

Replace the eight-note packed output buses with synchronous chart ROM.
Expose a read address, request enable, registered note data, and a valid
response. Document the one-cycle read latency. Expose chart metadata to the
controller. Keep the access pattern compatible with block RAM inference and
check the synthesis utilization report to confirm inference.

### Sequential gameplay engine in `control.v`

Replace the eight replicated note-state blocks with a finite-state machine
and a 1,024-bit resolved-note map. On each frame boundary, capture the song
time and buffered lane presses. Scan chart entries sequentially using the
100 MHz clock during the non-visible interval.

For each unresolved note, compare its target time with the captured song
time, find the closest eligible note in each pressed lane, detect expired
notes, and prepare visible geometry. Keep a note index with each candidate.
Commit results exactly once per frame. Resolve a successful hit before
expiring a note at the late boundary. Remove newly resolved notes before
publishing the next visible frame.

Use approximately ±100 ms as the initial hit window, matching the intent of
the current ±6-frame setting. Explicit millisecond timing avoids depending
on the monitor refresh rate. Keep press buffering active while the scanner
runs. Separate captured presses from presses received during processing so
new inputs survive for the next frame. Held keys continue to produce one
press through the existing keypad scanner.

Use a 32-bit millisecond song clock driven from the 100 MHz clock. Avoid
accumulating song time from rounded VGA frame durations. Stop, restart, and
pause must update the song clock, note state, and audio commands together.

### Rendering in `display.v`

A 1,024-entry combinational pixel search would create a large path into VGA
RGB. Instead, build a tile mask during the sequential chart scan. For each
of four lanes and each visible row, store separate tile-fill and tile-edge
bits. Two buffers require 4 × 480 × 2 × 2 = 7,680 bits. This supports all
1,024 chart entries even when many notes are visible together.

For each visible tile, mark its covered rows in the back buffer. Combine
overlapping masks so an edge remains visible. The renderer uses the row
mask and horizontal tile bounds to choose the cyan fill or bright edge.
Continue drawing pads, labels, timing line, and hit/miss rings above tiles.
Swap completed buffers before the visible region begins. The front buffer
stays stable throughout the visible frame.

Budget the worst case before coding the memory controller. A 36-pixel tile
requires at most 36 row updates. For 1,024 notes that is 36,864 updates,
plus buffer clearing, note reads, judgment, and commit passes. At 100 MHz,
the 48 lines above the playfield alone provide 153,600 cycles with the
current 800-pixel line timing and four system clocks per pixel. Require a
cycle budget below that deadline, including synchronous RAM read/write
latencies. An unfinished buffer must raise a simulation failure and retain
the previous complete frame in hardware.

Pipeline row-mask reads if synchronous memory is used. Align RGB, sync,
and blanking through any added pipeline stages, and verify the first and
last pixels of lines. Keep arithmetic and mask generation outside the
pixel-color path.

### Scoring and integration

Expand `score.v` to an 11-bit hit count, covering 0–1,024. Preserve one point
per successfully played note, including chords. Prepare four decimal digits
between frames so the display can show 1024 without division in the pixel
path. Update the top-level wiring and existing game testbench for the new
memory and controller interfaces.

Replace `LAST_FRAME = 340` with chart duration and note completion checks.
After the final note is judged, allow its feedback to finish. Keep audio
playing until the track's configured duration, then enter the finished
state. Reset restarts chart state and score consistently.

## Audio synchronization

Connect the existing `audio.v` command interface to the game. Load the
chart's song ID and wait for `audio_ready` before starting a countdown.
Use a pre-roll at least as long as a tile's travel time, so notes near the
start of the song have time to enter the field. Start laptop playback when
the countdown reaches song time zero.

The current `P` command starts playback without acknowledging the physical
audio onset. Use `audio_offset_ms` to calibrate the initial alignment and
measure alignment near the beginning and end of a track. If drift or
variable startup latency exceeds the hit window, extend the laptop/FPGA
protocol with playback timing feedback. Record the measured result before
calling music synchronization verified.

Use `audio/audio_player.py` as the documented player entry point and verify
that it loads the chart's matching song file. Confirm the intended root
entry point before changing the duplicate `audio_player.py`.

## Implementation order

1. Add the TXT compiler, format validation, generated memory, and a chart
   equivalent to the current eight-note demo.
2. Implement synchronous ROM reads and test counts of 0, 8, and 1,024.
3. Implement the sequential judge and resolved-note state. Verify boundary
   presses, closest-note selection, chords, and inputs arriving mid-scan.
4. Implement the double-buffered tile mask and VGA pipeline alignment.
   Measure worst-case cycles using a dense 1,024-note chart.
5. Expand scoring and end-of-song behavior, then connect load, playback,
   pause, resume, and restart to the audio interface.
6. Run synthesis and implementation. Inspect block RAM usage and post-route
   setup/hold results, then test the keypad, VGA, and audio together on board.

## Acceptance checks

- A valid TXT generates a playable chart, including a full 1,024-note game.
- Malformed entries and a 1,025th note produce clear compiler errors.
- The final memory address is read correctly and the score reaches 1024.
- Long tracks pass the old 10-bit frame-counter range without wrapping.
- Four-lane chords, closest-note judgments, held keys, and late-boundary
  hits behave consistently. Every note resolves once.
- Early-song notes receive a visible pre-roll. Pause and restart keep chart
  time and audio state consistent.
- Maximum-density chart processing completes before the visible playfield.
- VGA pixels and feedback remain stable, with matching RGB/sync alignment.
- Post-route setup and hold constraints pass at the existing 100 MHz clock.
- Board testing records audio alignment at the beginning and end of a track.
