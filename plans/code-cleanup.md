# Gameplay code cleanup plan

**Prepared** November 23, 2026  
**Status** Implemented and verified in simulation. Vivado timing and physical board verification pending.

## Intended result

Make the source easier to walk through in a lab demonstration. A reader
should be able to follow keypad input, song selection, note judgment,
scoring, and rendering without first understanding the old hardware demos.
Preserve the three songs, home/loading/game/results screens, audio controls,
centered ±160 ms hit window, one-note-per-press behavior, combo multipliers,
and end-of-game statistics.

Implement this in small passes. Keep the 100 MHz clock, pixel-enable timing,
registered graphics, and sequential chart scans as the timing foundation.
Each pass should have its own reviewable diff and relevant passing tests.

## Starting gameplay dependencies

| Responsibility | Current files |
| --- | --- |
| Board wiring and integration | `veribeat.v`, `basys3.xdc` |
| Reset, pixel enable, VGA raster and outputs | `clock.v`, `vga.v` |
| Keypad scanning and debouncing | `input.v` |
| Home, loading, playback, pause, results | `game_session.v` |
| Three-song chart storage and metadata | `song_library.v`, `notes.v`, `song_library_config.vh`, `charts/song_0.mem` through `song_2.mem` |
| Note judgment and visible tile preparation | `control.v`, `tile_mask.v` |
| Playfield, menu, results and HUD pixels | `display.v`, `menu_display.v` |
| Event counts and combo scoring | `score.v`, `combo_score.v` |
| Audio commands and serial transport | `audio.v`, including its `uart_tx` and `uart_rx` modules |
| Laptop playback and music assets | `audio/audio_player.py`, `audio/songs/song_0.mp3` through `song_2.mp3` |

These active modules all contribute to gameplay. The cleanup focuses on
obsolete entry points, unnecessary compatibility paths, and confusing
representations inside the active modules.

## Pass 1 — remove obsolete entry points and chart outputs

| Candidate | Proposed action | Dependency to handle first |
| --- | --- | --- |
| Root `audio_player.py` | Delete the duplicate and document `audio/audio_player.py` as the playback entry point. The two copies currently match byte for byte. | Update command examples and comments that imply the root script is the primary player. |
| `audio_test.v`, including `audio_test_btn` | Delete the standalone audio demo after confirming the integrated audio checks cover its useful behavior. | Preserve load/play/pause/resume/stop checks and the board controls in `game_session.v`. |
| Root `notes_data.mem` | Delete the old single-chart build output. | Change `notes.v`'s default filename and update unit fixtures that currently instantiate `notes` with that default. Use explicit chart files or test-only fixtures. |
| Root `notes_config.vh` | Delete the old single-chart metadata header. | Confirm all current sources and test commands use the song library's metadata. |
| `charts/song_0_config.vh` through `song_2_config.vh` | Stop generating and delete the redundant per-song headers. | Refactor the compiler so `compile_songs.py` receives validated metadata directly, then writes `song_library_config.vh`. It currently parses these headers as intermediate files. |
| Production diagnostic pattern in `veribeat.v` | Remove its color bars, grid, bouncing square, `START_X`, `START_Y`, and `DIAGNOSTIC` branch. | Port the timing and RGB-alignment coverage from `tests/vga_tb.v` to a direct `clock`/`vga` test fixture. Remove assertions specific to the bouncing demo. |

Keep the three TXT charts as editable source, the MP3s as playback assets,
and the three menu ROMs plus shared metadata as reproducible Vivado inputs.
Keep generated ROMs checked in during this cleanup so a fresh clone can
still build without first running Python.

The analysis JSON files and `tools/match_song_chart.py` support chart
creation and traceability. Keep them with the authoring tools, outside the
Vivado design-source list. Preserve `reports/` and historical `plans/` as
project records. Tests remain part of the verification workflow.

Update `.gitignore` to cover fallback tracks in `audio/songs/test_*.wav`.

## Pass 2 — make generation and the build list straightforward

1. Extract TXT parsing and validation into a function that returns metadata
   and note records. Preserve the existing `compile_chart` entry point for
   callers that use it.
2. Have `compile_songs.py` validate all three charts and generate their ROMs
   plus one shared header directly from those records. Preserve its staged
   validation so an invalid chart leaves the previous library usable.
3. Set authoring-tool output paths explicitly by song. Remove the dependency
   on old root-level chart outputs and update the documented commands.
4. Maintain one explicit Vivado source list and one test command list in the
   README. Include the three memory files and shared header.
5. Add a small test runner if it removes duplicated command maintenance.
   Keep existing testbenches focused on their current responsibilities.

Keep the current root RTL layout for this pass. A directory migration would
also require Vivado source-path changes and can be handled independently.

## Pass 3 — clarify module names and the top-level wiring

- Rename `input.v` to `keypad.v`, matching its existing module name.
- Rename `score.v` and module `score` to `event_counter.v` and
  `event_counter`. It counts events and produces decimal digits. The weighted
  score remains the responsibility of `combo_score.v`.
- Rename ambiguous wires in `veribeat.v`, particularly `points` to
  `hit_count` and `digits` to `hit_digits`.
- After removing the diagnostic, organize the top into short labeled groups
  for timing, input, session/audio, chart/judgment, statistics, and display.
  Keep integration wiring in this file.
- Replace repeated numeric screen IDs with named constants. Introduce one
  small shared constants include for values genuinely shared across the
  renderer and judge, including pad center, tile height, and screen IDs.
  Keep module-local state encodings local.
- Keep the serial transmitter and receiver alongside `audio` with a concise
  command table explaining the UART protocol.

Update module instantiations, Vivado source lists, test commands, and file
references in the same pass as each rename. Preserve Verilog-2005 support.

## Pass 4 — simplify active logic while preserving behavior

### Timing and clocking

Replace the named 25/50/100 MHz convenience outputs with a two-bit phase
counter that supplies the existing one-cycle-in-four `pixel_tick`. Retain
the reset synchronizer. The current `pixel_tick` depends on the internal
25 MHz divider, so this is a functional rewrite with reset/phase tests.
Keep all sequential logic on the board's 100 MHz clock.

### Gameplay controller

Use `chart_note_count` as the single note-count interface. Remove the static
`NOTE_COUNT` and `DYNAMIC_CHART` compatibility parameters after updating
unit tests to drive the count explicitly.

Organize the controller around its existing phases: capture presses, clear
the back buffer, scan for hits, commit selected hits, resolve misses and
paint tiles, publish feedback, then publish the frame. Give each state a
short explanation of its inputs and state updates. Explain the note word's
valid bit, target time, and lane fields in one place.

Keep the per-lane press timestamps, oldest-eligible-note selection, and
separate hit/miss/misclick events. Keep the small sequential scan and double
buffer, which support 1,024 notes without a long pixel-color path.

### Scoring

Keep reusable event counters and the combo scorer as separate components.
Name the queue and penalty state by their behavior, including the rule that
an error cancels combo growth for pending hits. Explain scoring in hundreds,
then the conversion to the displayed score. Keep the binary score output
as a useful verification interface.

Preserve per-note chord scoring, immediate combo resets, the longest streak,
queued event counts, decimal digits, and saturation behavior. Limit shared
BCD helpers to clear reductions in duplicated logic.

### Display and menu code

The live HUD is rendered by `menu_display.v`. Remove the obsolete hit-count
header from `display.v` and remove its `digits` port after updating callers.
Keep the playfield renderer focused on lanes, tiles, pads, and feedback.

Replace the menu's hundreds of per-character case entries with named,
fixed-width text constants and one character lookup. Give text origins,
stat rows, numeric widths, colors, and message IDs descriptive names.
Replace dense multi-assignment lines with readable blocks.

Retain the two menu pipeline stages and the current four-cycle pixel
interval. Keep font data static. Share the small glyph definitions where
that makes both renderers easier to read while preserving their timing.

## Verification and completion criteria

Before the first pass, record the existing relevant simulation results and
any available post-route timing report. After each pass, run checks affected
by its changes. At the final checkpoint, verify the following.

- All three keypad song selections load the matching chart and audio ID.
- Home, loading, pause/resume, results, and any-button return still work.
- Overlapping windows, held keys, buffered late hits, and ±160 ms boundaries
  preserve one-note-per-press behavior.
- Hits plus missed notes equal the chart count at normal completion.
  Misclicks remain a separate statistic.
- Combo thresholds, chords crossing thresholds, penalty resets, best streak,
  and the 403900-point perfect 1,024-note score pass.
- Dense chart preparation stays within its frame deadline.
- Reset, raster timing, blanking, RGB/sync alignment, and HUD alignment pass.
- Invalid charts leave generated library inputs consistent.
- A clean checkout builds with the documented source and memory files.
- Vivado synthesis and implementation meet setup/hold constraints at 100 MHz,
  followed by keypad, VGA, and audio checks on the board.

The first implementation pass should remove the duplicate audio player and
standalone audio demo, then retire obsolete chart outputs with their compiler
and test dependencies updated. Handle the production diagnostic and clock
rewrite as separate passes so timing changes are easy to review.


## Implementation record

The source cleanup was completed on November 23, 2026.

- Removed the duplicate root audio player, standalone audio test, old root
  chart ROM/header, and three intermediate per-song headers.
- Renamed `input.v` to `keypad.v` and `score.v` to `event_counter.v`, including
  callers and test/source lists.
- Reduced `veribeat.v` to gameplay wiring and removed its diagnostic branch.
  Replaced the convenience clock outputs with a phase counter and pixel enable.
- Switched the controller to its runtime chart-count input and documented its
  processing phases. Kept the sequential scan and double buffering.
- Shared geometry/screen constants and the static font. Replaced menu character
  cases with named fixed-width strings and readable result-layout constants.
- Removed the hidden hit-count header from the playfield renderer.
- Made chart compilation consume parsed metadata directly. Authoring defaults
  now derive chart and ROM output paths from the selected song.
- Added `tools/run_tests.py` as the maintained simulation entry point.

Verification completed with five Python checks and all 15 simulations,
including direct clock/VGA tests, menu/HUD alignment, centered hit timing,
1,024-note gameplay, combo scoring, and the full flow for each of the three
songs. Every menu character and font glyph was also compared with the
pre-cleanup source. The three chart ROMs and library metadata are unchanged.

Vivado synthesis/implementation and physical keypad, monitor, and audio checks
remain the final hardware checkpoint. This environment has no Vivado runner
or connected Basys 3 board.

After the cleanup, the menu pipeline was extended to three stages to split
the reported menu-character setup path. See
[the timing issue record](../reports/003-menu-character-setup-timing.md).
