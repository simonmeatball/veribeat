# veribeat

## Veribeat game (Basys 3)

The home screen offers all three songs in one FPGA build. Press keypad `1`
for Yoru ni Kakeru (song 0), `2` for APT. (song 1), or `3` for Sunflower
(song 2). The selected song loads through the laptop audio player before
play starts. During play, the HUD shows the score and current combo. At the
end, the results screen shows score, hits, missed notes, misclicks, and the
longest streak. Press any keypad key or board button to return home, then make
a fresh song selection.

A hit is a successfully judged note. A miss is a note that passes its late
window. A misclick is a gameplay press without a matching note, including
keys outside the four gameplay lanes. Multiple missed notes count
individually even when they expire in the same frame. Menu selection,
loading, pause, and results navigation produce no gameplay penalties.
Misclick statistics saturate at the four-digit display limit of 9999.

The game accepts up to 1,024 tap notes from a text chart. Press the matching
bottom-row keypad key when the center of a cyan tile reaches the center of
its bottom pad, aligned with the purple timing line. The hit window is
±160 ms. A hit flashes white and advances the combo by one note. A missed
note or unmatched press flashes red and resets the combo to zero.

Each hit earns 100 base points with the following multiplier. The threshold
note uses the new multiplier, so the tenth consecutive hit earns 200 points.

| Current combo after the hit | Multiplier | Points per note |
| --- | ---: | ---: |
| 1–9 | 1× | 100 |
| 10–19 | 2× | 200 |
| 20–29 | 3× | 300 |
| 30 and above | 4× | 400 |

Each note in a chord advances the streak and receives its own multiplier.
Misses and misclicks reset the current combo while the longest streak is
retained for the results screen. Simultaneous successes and an error award
base points and reset the combo. Restarting or returning home clears the
run's score and streak records. A perfect 1,024-note run earns 403900 points;
the six-digit score display and four-digit streak display cover this range.

Each press consumes the oldest eligible note in its lane. When two windows
overlap, the later note stays available for another press. The judge stores
the press timestamp so waiting for the next VGA frame does not shorten the
late window. Holding a key produces one press. Expired notes are resolved
after the selected hits.

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
the repository root. This regenerates the TXT and its song-specific ROM.
Run `compile_songs.py` afterward to refresh the shared menu metadata.

```sh
python3 tools/match_song_chart.py audio/songs/song_0.mp3
```

### Additional track charts

Both additional charts were analyzed from the corresponding MP3 files in
`audio/songs/`. Their analysis records include the exact source hashes.

| Song ID | Track | Notes | Approximate BPM | Accent chords |
| --- | --- | ---: | ---: | ---: |
| 1 | [APT.](charts/song_1.txt) — ROSÉ & Bruno Mars | 540 | 149 | 12 |
| 2 | [Sunflower](charts/song_2.txt) — Post Malone & Swae Lee | 419 | 90 | 9 |

Each chart has its own `.mem` and `.analysis.json` alongside
the TXT. Compile all three charts together after editing their TXT files.

```sh
python3 tools/compile_songs.py
```

This refreshes the menu's three ROM banks and shared metadata. The keypad
selection controls both the chart bank and the song ID sent to the laptop.
These are automatically arranged rhythm charts and need listening/playtesting
and hardware latency calibration.

To regenerate an individual arrangement into its own chart files, specify
its song ID and output paths. For example, use the following for APT.

```sh
python3 tools/match_song_chart.py audio/songs/song_1.mp3 \
  --song-id 1 --title 'ROSÉ & Bruno Mars - APT.' --chart charts/song_1.txt \
  --memory charts/song_1.mem
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
python3 tools/compile_songs.py
```

This generates `charts/song_0.mem` through `charts/song_2.mem` and
`song_library_config.vh`. Each ROM contains 1,024
padded 40-bit words. The shared header holds each song's note count and
duration. Rebuild and program the FPGA after changing chart data. The
standalone `compile_chart.py` tool is also available for single-chart tests.

### Vivado project setup

Create an RTL project for Basys 3 part `xc7a35tcpg236-1`. Add these design
sources and set `veribeat` as the synthesis top.

```text
clock.v          vga.v          veribeat.v
keypad.v         notes.v        control.v
tile_mask.v      display.v      event_counter.v
combo_score.v
game_session.v   audio.v        song_library.v
menu_display.v
```

Add `song_library_config.vh`, `game_defs.vh`, and `font3x5.vh` as Verilog
headers and their directory to the project's Verilog include directories. Add all three `charts/song_N.mem`
files as Memory Initialization Files. The `SONG0_FILE`, `SONG1_FILE`, and
`SONG2_FILE` top-level parameters specify their paths. For simulation, run
from the repository root. If Vivado cannot resolve a memory path, set the
corresponding parameter to its absolute path. Verify that synthesis reads
all three ROMs successfully.

Use `basys3.xdc` as the constraint file for the game. It covers the clock,
JXADC keypad, VGA, UART, board buttons, and status LEDs.

If the Vivado project copied sources, update the active project copies.
Reset synthesis and implementation after updating the RTL. Check post-route
setup/hold timing and inferred ROM/RAM resources before generating a bitstream.
Testbench files belong under Simulation Sources.

### Keypad and audio controls

Connect the PmodKYPD to JXADC (JX). The scanner sends synchronized, debounced pulses.
The controller buffers pulses even while scanning the chart.

| Lane, left to right | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| Key | `0` | `F` | `E` | `D` |

Start the laptop player before resetting the FPGA.

```sh
python3 audio/audio_player.py
```

It uses the existing USB-UART protocol at 115200 baud to play the selected
`audio/songs/song_N.mp3`. Reset opens the home screen. Selecting a song
stops previous playback, loads its song ID, waits for the player's ready
response, and runs
a 1.4-second visual pre-roll before sending PLAY. The song clock uses the
100 MHz oscillator to count milliseconds. Audio startup latency needs
on-board calibration using `audio_offset_ms`.

| Board button | Action |
| --- | --- |
| Center | Reset to home |
| Up | Stop, reload, and restart the chart |
| Left | Pause chart time and audio |
| Right | Resume |
| Down | Stop and show results |

LEDs 0–10 show the binary hit count. LEDs 11–15 show running, paused, finished,
audio failure, and renderer deadline failure respectively. An audio failure
shows an error/results screen. Return home and select a song after correcting
the player or song file. Any button on the results screen returns home. The game ends
when the configured track duration has elapsed, all notes have resolved,
and the feedback tail has elapsed.

### Architecture and simulation

`song_library.v` selects one of three synchronous `notes.v` ROMs and its
metadata. `game_session.v` controls home, loading, play, pause, and results.
`menu_display.v` draws the home/loading/results screens with three 100 MHz
pipeline stages that settle within the existing four-cycle pixel interval.
`event_counter.v` instances count hits, individual missed notes, and misclick events.
`combo_score.v` tracks the current/longest streak and awards combo multipliers.
Its decimal score accumulator works in hundreds, avoiding division or a
long decimal carry chain in the VGA pixel path.
`control.v` scans the selected chart twice per
frame to judge notes and paint the next tile mask. `tile_mask.v` stores two
banks of four lane masks. A complete bank is published at VGA line 47,
before the playfield starts at line 48. An incomplete frame sets LED 15
and preserves the previous bank. The renderer uses distributed-memory row
reads, keeping the VGA timing interface's existing RGB/sync alignment.

Install Icarus Verilog, then run the maintained suite from the repository
root. `tools/run_tests.py` lists the design sources and test cases.

```sh
python3 tools/run_tests.py
```

Run selected tests during development by naming them.

```sh
python3 tools/run_tests.py combo_score_tb menu_display_tb
python3 tools/run_tests.py integration_song_1
```

Use `--simulator-dir /path/to/bin` when Icarus is installed outside PATH.
The runner also executes the Python chart-compiler checks. The full suite
covers direct clock/VGA timing, the keypad and session, 1,024-note gameplay,
hit-window edge cases, statistics, combo scoring, screen pixels, HUD alignment,
and the full flow for every song.

The integration simulation checks physical matrix song selection, UART
STOP/LOAD/ready, gameplay presses, score/combo changes, all three counters,
longest streak, results, and returning home while holding the return key.
It advances song time for the test. The runner exercises all three song
selections. The session simulation checks all menu selections, countdown, pause/resume,
finish, navigation, and error handling. Physical audio alignment and Vivado
timing closure require board/tool verification.

## VGA timing

All sequential logic uses the 100 MHz system clock. `clock.v` synchronizes
reset release and emits `pixel_tick` once every four cycles, giving a 25 MHz
pixel rate. `vga.v` generates a 640×480 raster with totals of 800×525 pixels,
approximately 59.52 frames per second. RGB, sync, and blanking are registered
on the same pixel enable.

`frame_tick` marks the end of the raster. The gameplay controller prepares
the next tile mask between that boundary and the playfield at line 48.
The menu's three register stages settle inside each four-cycle pixel interval.
The menu registers layout/coordinates, then character lookup, then glyph
color and HUD selection. Keep these timing relationships when changing rendering logic. The direct
`vga_tb`, `clock_tb`, and menu VGA tests cover alignment and reset behavior.

Check Vivado post-route setup/hold timing and board operation after RTL
changes. If the monitor requires standards-aligned VGA timing, the existing
25 MHz pixel enable will need a separately verified clocking change.

## Source cleanup

The playable top is `veribeat`. Keypad scanning lives in `keypad.v`, and the
generic decimal event accumulator lives in `event_counter.v`. `combo_score.v`
owns the point rules and streak state. `game_defs.vh` holds shared geometry
and screen identifiers; `font3x5.vh` holds the common static glyph table.

The laptop entry point is `audio/audio_player.py`. Editable charts, compiled
ROMs, and source-analysis records live under `charts/`. The tests exercise
hardware interfaces directly and the normal playable top. The cleanup plan
and verification record are in [plans/code-cleanup.md](plans/code-cleanup.md).

For an existing Vivado project, replace the `input.v` and `score.v` source
entries with `keypad.v` and `event_counter.v`, remove the legacy audio-test
source, and refresh the changed RTL copies. Add `game_defs.vh` and
`font3x5.vh` alongside the existing shared song header. Rebuild synthesis and
implementation using `veribeat` as the top.
