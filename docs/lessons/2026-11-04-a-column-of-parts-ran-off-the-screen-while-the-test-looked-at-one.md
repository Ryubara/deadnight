# A column of parts ran off the screen while the test looked at one part

2026-11-04

- **Symptom:** with the fullest night report at 1536 x 864 the end board's Leave button sat at y 950, below the
  screen; the card's own fit test was green.
- **Cause:** the test asked whether the card was inside the screen and clear of Leave, not whether Leave was inside.
  The column grew past the screen (its parts are laid out in a box that grows with them), the card was still inside,
  and the card's room sum used a hand-written chrome of 150 against 239 real units, and a title that wrapped to a
  second line. The rows' floor (24) was below the type's own height (34), so shrinking them did nothing.
- **Fix:** the title's type fits one line, the card's rows and type step down together (`HudNightReport.show_report`
  measures the ticket, no constant), and the countdown's numerals step down after them. `test_end_board_fit.gd`
  checks every part of the column, with the fullest card, at every canvas, and fails on a part outside the screen.
- **Documented:** [HUD research](../research/hud.md).
