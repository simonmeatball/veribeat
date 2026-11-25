# Hit-based grades and timing-weighted scores

**Logged** November 25, 2026  
**Status** Implemented. Python checks and all 22 RTL simulations pass.

## Reported issue

A Yoru ni Kakeru run showed 808 hits, 46 misses, 45 misclicks, a best streak
of 129, and a score of 197700, yet received F. The original grading compared
that combo score against a perfect 335900-point run. The resulting 58.86%
underrepresented the player's 94.61% hit rate because streak breaks reduced
the multiplier on later successful hits as well.

## Updated behavior

The letter grade now uses:

`100 * max(0, hits - factor * (misses + misclicks)) / chart_note_count`

The default factor is 0.25. `veribeat.GRADE_PENALTY_PERCENT` configures it as
an integer percentage: 25 means 0.25, 50 means 0.5, and 100 means 1. Grade
tiers remain S at 95%, A at 90%, B at 80%, C at 70%, D at 60%, and F below
60%. Empty charts receive F. The photographed result now earns 91.95%, A.
Integer threshold comparisons preserve fractional hit credit without a
divider, and signed arithmetic handles penalties exceeding the hit total.

Numeric score uses timing-weighted base points: Perfect 100, Great 80,
Good 60. Existing combo multipliers and streak statistics remain. Misses
and misclicks reset the combo. Each chord is drained in lane order with
the individual timing quality attached to each hit. Grades use the hit
and error counts independently of these timing and combo score bonuses.

`control.v` now publishes scoring quality alongside its hit pulse. This
is separate from the later display-feedback publication. `combo_score.v`
captures the frame's batch, applies weights and multipliers, and converts
a binary score snapshot to BCD over twenty clocks. Binary score and display
digits publish together. `result_grade.v` receives the hit/miss/misclick
counters instead of numeric score. Refresh these modules and `veribeat.v`
together in projects with imported RTL copies.

## Verification

- Weighted-score tests cover all timing weights, mixed-quality chords
  crossing combo tiers, penalty resets, coherent binary/BCD snapshots,
  and perfect and mixed-quality 1,024-note runs.
- Grade tests cover three penalty factors, exact tier boundaries, negative
  effective-hit totals, the photographed result, all song sizes, and reset.
- Timing tests exercise every millisecond from -161 through +161 ms and
  verify scoring receives the same timing classification as feedback.
- Five Python checks and all 22 RTL simulations pass, including all three
  song integration runs.
- Updated session and pause-menu simulations also pass after adding the
  Continue countdown. They verify each 3–2–1 step lasts one second, elapsed
  time stays fixed, no load/reset commands are issued, and audio resumes
  only when the countdown ends. Lead-in continuation keeps audio unstarted.

Vivado and a connected board are unavailable here. Rerun synthesis and
implementation to verify post-route timing and hardware operation.
