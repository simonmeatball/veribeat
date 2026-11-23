# Menu character setup timing

**Logged** November 23, 2026  
**Status** Pipeline fix implemented and simulated. Post-route timing verification pending.

## Reported failure

The supplied Vivado 2018.2 report, generated at 10:27:32 on November 23,
showed three setup violations at a 100 MHz clock. Worst setup slack was
−0.257 ns and total negative slack was −0.422 ns. Hold timing passed, with
worst hold slack of +0.108 ns.

The worst path ran from `video/v_count_reg[7]` to
`game.menus/character_reg[0]`. It had 15 logic levels and a 10.157 ns data
path delay. Menu row selection, local coordinate arithmetic, and character
lookup occupied the same register-to-register path. The cleanup changed
text storage and hierarchy while retaining that processing-stage boundary.

## RTL change

`menu_display.v` now uses three 100 MHz pipeline stages.

1. Decode the screen layout and register local coordinates, message ID,
   numeric value/digit index, visibility, colors, and HUD selection.
2. Look up the character using those registered values. Delay glyph
   coordinates, colors, and HUD selection with the character.
3. Resolve the glyph pixel and output its color and HUD selector together.

The character lookup starts from layout registers, breaking the reported
VGA-row-to-character path. The menu settles in three system-clock stages
within the existing four-clock pixel interval. The VGA raster, clock
constraint, and registered RGB/sync interface keep their current timing.

## Verification

- `menu_display_tb` passes, including a new check requiring three pipeline
  stages and checking score, combo, and all result statistics.
- `menu_vga_home` and `menu_vga_hud` pass against the actual VGA RGB outputs.
- An exhaustive simulation comparison against the prior renderer matched
  all 2,764,800 visible pixels and HUD selectors across home, gameplay HUD,
  results/loading for all three songs, and the audio-error screen.
- `integration_song_0` passes the full song-selection, UART, keypad, combo,
  results, and restart flow. The five Python compiler checks also pass.

Reset and rerun Vivado synthesis and implementation with the updated RTL.
Record the new post-route WNS, TNS, and failing endpoint count here before
closing this timing issue. Vivado and a connected board are unavailable in
this environment, so timing closure has not yet been measured.
