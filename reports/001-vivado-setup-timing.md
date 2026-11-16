# Vivado setup timing failure on the VGA game

**Logged** November 16, 2026  
**Status** RTL fix simulated. Vivado timing closure pending.

## Implementation result

The Basys 3 implementation failed setup timing on the 100 MHz `sys_clk`.
The original timing report showed the following results.

| Metric | Original result |
| --- | ---: |
| Clock period | 10.000 ns |
| Worst setup slack (WNS) | −4.610 ns |
| Total negative slack (TNS) | −115.431 ns |
| Failing setup endpoints | 43 |
| Worst hold slack (WHS) | +0.122 ns |
| Failing hold endpoints | 0 |

The worst path ran from `game.gameplay/frame_reg[0]/C` to
`video/red_reg[2]/D`. Its data path delay was 14.637 ns, split between
6.997 ns of logic delay and 7.640 ns of routing delay. The path crossed
20 logic levels, including 10 carry-chain blocks. All ten worst setup paths
listed for `sys_clk` started at the same frame-counter bit and ended at
VGA color registers.

## Cause and fix

The frame counter drove combinational tile-position calculations in
[`control.v`](../control.v). The renderer then used those positions to
decide which RGB values to send to [`vga.v`](../vga.v). Both operations
had to settle before the VGA color registers sampled their inputs.

The revised controller stores each tile's position in a register and advances
it by five pixels at each VGA frame boundary. The renderer reads those
registered positions directly. The controller also compares the frame count
against the hit-window bounds and uses a four-bit signed offset to rank
notes within the window. The 100 MHz clock and 10 ns constraint remain in
[`basys3.xdc`](../basys3.xdc).

## Verification and next run

- [`game_tb`](../tests/game_tb.v) passed in Icarus Verilog, covering keypad
  input, tile movement, the hit-window boundary, chords, and hit/miss effects.
- A before-and-after simulation matched visible tile positions, hit decisions,
  and feedback across two 360-frame runs.
- Rerun Vivado synthesis and implementation with the revised controller.
  Record the post-route WNS, TNS, failing setup endpoints, WHS, and failing
  hold endpoints here. Close this issue after the timing summary confirms
  that the constraints are met. If setup still fails, record the new worst
  path's source, destination, and data delay.
