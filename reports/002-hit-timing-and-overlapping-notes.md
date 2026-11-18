# Hit timing and overlapping notes

**Logged** November 18, 2026  
**Status** RTL changes verified in simulation. Board playtesting and post-route timing pending.

Players reported that slightly late presses received miss feedback and that
nearby notes sometimes appeared to disappear together.

The previous geometry placed a tile's bottom at y=404 at its target time.
For a 36-pixel tile, its center was y=386. The input pad spans y=410–455,
with a geometric center at y=433. At the configured speed of 5/16 pixel per
millisecond, the tile center reached the pad center about 150 ms after its
target time, beyond the previous ±100 ms hit window.

The previous candidate selector prioritized the nearest eligible note. When
windows overlapped, it could choose a newer note while an older note was
close to expiry. Their removals could then appear close together. The
original controller already limited a batch to one scored hit per lane.

The revised controller aligns the tile center with the pad center at the
chart target time and moves the purple line to y=433. The default hit
window is ±160 ms. Press timestamps are captured before frame processing,
so an eligible press survives the wait for the next VGA frame. Rising-edge
capture prevents a held input from consuming another note.

Each lane now selects its oldest eligible unresolved note. Chosen hits
resolve before the expiry pass. An eligible press consumes one note and
leaves another note within its own valid window available for a subsequent
press. Notes that pass their late deadline still expire through the miss
path.

Verification passed in `tests/hit_timing_tb.v` for centered geometry,
overlapping windows where the newer note is closer, a held input, a second
physical press, inclusive ±160 ms boundaries, a late-boundary press buffered
for 17 ms, and rejection outside the window. The 1,024-note game regression
also passed, including a maximum-density frame completed in 45,058 cycles
against the 150,000-cycle test budget. The empty/eight-note and keypad
regressions passed. Rebuild the bitstream and check post-route timing before
board playtesting.
