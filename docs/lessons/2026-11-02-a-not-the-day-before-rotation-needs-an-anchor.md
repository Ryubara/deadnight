# A "never the same as the day before" rotation needs a chain with a start

2026-11-02

- **Symptom:** the daily challenges (#429) must never repeat the day before's pick.
- **Cause:** a rule that depends on the previous result is a chain: today's pick needs yesterday's, which needs the day
  before, back to a first day that does not exist.
- **Fix:** anchor the chain per 30-day block: the block's first day picks without the rule, and each later day is
  computed from the block's start, so the work per day is bounded.
- **Documented:** [Challenges](../research/challenges.md).
