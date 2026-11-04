# A new rules action failed three tests of the validation suite

2026-11-04

- **Symptom:** after `RulesAction.ARRIVAL` was added (#1057), `test_validation.gd` failed
  `test_every_action_type_has_a_sample`, `test_a_missing_field_is_rejected_for_every_type` and
  `test_a_wrong_type_is_rejected_for_every_field`, in a suite the change never touched.
- **Cause:** the suite loops over `RulesAction.REQUIRED` and wants one well formed action of each type in its
  `SAMPLES` table; a type with no sample fails all three. I had written tests for the action's behaviour and not run the
  suite that holds every action to its shape.
- **Fix:** a sample in `SAMPLES`. The three then pass for the new action: a missing field and a wrong type are rejected
  with the one `action_rejected` event and nothing changes.
- **Check next time:** a new key in `RulesAction.REQUIRED` (or a new `NetWire.Type`, a new snapshot key) is followed by
  `tests/rules` and `tests/net` run whole, not only the new suite.
- **Documented:** [the arrival](../research/arrival.md#what-went-wrong-on-the-way).
