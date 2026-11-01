# A `Callable` from a temporary object went invalid and the bot's sight said "clear"

2026-11-01

- **Symptom:** the bot's line-of-sight check answered "clear" for every shot, so it fired through walls (#158).
- **Cause:** `WorldProbe.new(space).callable()` holds the `RefCounted` by id, not by reference; the temporary object was
  freed at once and `Callable.is_valid()` was false (the check treated an invalid callable as open).
- **Fix:** keep the object in a member (`Night._sight`) and hand out `_sight.callable()`.
- **Documented:** [the autopilot](../design/slice.md#the-autopilot).
