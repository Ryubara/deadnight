# A width threshold hid a rule title cut on the narrowest phone

2026-11-05

- **Symptom:** the solo Play screen cut "Break between ro..." on a 667 x 375 phone page (960 x 540 units), and
  `test_phone_fold` said nothing: its solo case skipped every page narrower than 1688 px.
- **Cause:** #1243 kept whole titles only from 1100 units wide (`PlayScreen.WHOLE_TITLES_WIDTH`) because the whole title
  overflowed the card by 20 units, and the test was cut to the pages that passed: the fault was moved out of the test's
  sight instead of out of the layout. The widest row is 820 units, its scroll bar takes 48, and the card's column was left
  848.
- **Fix:** whole titles on every phone; the gaps of a phone's row are 16 units instead of 24 (`UIRow.set_tight`) and the
  Play screen keeps an 8 unit edge on every side. The solo case walks every page of `UiFitRun.PAGES`.
- **Documented:** [phone page scale](../research/phone-page-scale.md).
