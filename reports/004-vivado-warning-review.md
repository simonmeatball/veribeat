# Vivado synthesis and implementation warnings

**Logged** November 23, 2026  
**Status** RTL fixes implemented and simulated. Vivado DRC, timing, and power review pending.

## RAMB18 asynchronous control (REQP-1840)

Vivado reported that `menus/character_reg/ADDRARDADDR[10]` was driven through
`menus/sel[6]` by `clocks/reset_pipe_reg[1]`, a register with asynchronous
reset. An asynchronous reset assertion could change the inferred menu ROM's
address/control between clock edges. The warning is actionable even though
simulation normally shows deterministic reset behavior.

`clock.v` now samples both edges of the external reset through two flip-flops.
The synchronizer has no asynchronous set/reset. The game sees reset after
two clock samples, so a raw pulse must last long enough to be sampled.
The existing initialized reset pipeline still supplies startup reset.
`vga.v` also uses synchronous reset for its output registers. Reset assertion
and release now travel through clocked logic throughout the RTL.

This follows AMD's guidance that registers associated with dedicated
synchronous memory resources use synchronous reset. No DRC suppression or
change from block ROM to distributed ROM was added.
[AMD synthesis coding guidelines](https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Coding-Guidelines).

## Zero replication and unused chart inputs

- **Synth 8-693:** `event_counter.v` used a replication count of
  `16-INPUT_BITS`, which becomes zero for a 16-bit input. An unsigned
  assignment now performs the same zero extension without replication.
- **Synth 8-3331, chart_data[38:34]:** these five bits are reserved padding
  in the chart format. `notes.v` now removes them at the ROM boundary.
  The gameplay interface is 35 bits: valid at bit 34, target milliseconds
  at bits 33:2, and lane at bits 1:0. The files and stored words remain
  40 bits. Update `notes.v`, `song_library.v`, `control.v`, and `veribeat.v`
  together in any project using imported source copies.

## Removed sequential elements (Synth 8-6014 and 8-3332)

These messages alone do not establish a functional failure. Synthesis can
remove constant bits, unused outputs, and registers absorbed into memory
resources. Known examples in this design include the disconnected keypad
`released` output and constant palette bits. Chart padding and upper bits
that are constant across a song can also be optimized.

The reported `character`, `data`, `delta`, layout, and row register messages
should be interpreted with their bit-level synthesized connectivity if a
behavioral issue remains. No preservation attributes were added merely to
retain hardware with no effect on outputs.

## Constraint export message (Constraints 18-5210)

The supplied message has no command or filename, and the preceding message
is Synth 8-3332. That is insufficient to establish whether an empty export
is expected or whether a project constraint setup is wrong.

A static check of the repository's `basys3.xdc` found a 10.000 ns `sys_clk`
constraint and exactly one pin assignment for each of the 46 top-level port
bits. This does not establish that the Windows Vivado project loaded it.
In the synthesized/implemented design, run `report_clocks` and confirm
`sys_clk` has a 10.000 ns period. Confirm `basys3.xdc` is enabled for both
synthesis and implementation, then review `check_timing` and
`report_timing_summary` for missing clocks or unexpectedly unconstrained
internal paths. Retain the surrounding Tcl transcript if 18-5210 persists.

## Power activity warning (Power 33-332)

This warning concerns reset switching/static-probability assumptions used
for power estimation. It does not by itself demonstrate that the physical
reset is stuck or that timing failed. Use Tools > Power Constraints Advisor
or `report_power -advisory`, then review the reset activity against realistic
game operation. Supply representative simulation activity when available.
Do not force arbitrary reset activity values solely to hide the warning.
[AMD Power Constraints Advisor](https://docs.amd.com/r/2023.2-English/ug907-vivado-power-analysis-optimization/Power-Constraints-Advisor).

## Verification and next run

- Five Python chart/compiler checks and all 15 RTL simulations pass.
- Reset tests now check synchronous assertion and two-sample release.
- VGA tests cover three frames and a reset during a partial frame.
- Chart, hit-window, 1,024-note, scoring, renderer, and all three full-song
  integration tests pass with the compact chart bus.
- Existing song memory files and library metadata are unchanged.
- No asynchronous set/reset sensitivity lists remain in the production RTL.

Reset and rerun Vivado synthesis and implementation using all changed RTL.
Confirm REQP-1840 and Synth 8-693 are gone, inspect the remaining warnings,
and record post-route timing. Vivado and a connected board are unavailable
in this environment, so DRC clearance and timing closure remain unmeasured.
