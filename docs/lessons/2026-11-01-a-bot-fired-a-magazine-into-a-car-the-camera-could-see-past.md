# A bot fired a magazine into a car the camera could see past

2026-11-01

- **Symptom:** the autopilot emptied a magazine into a car cabin five metres away and killed nothing, though its line of
  sight to the zombie was clear (#158).
- **Cause:** in third person a shot leaves the barrel, which sits beside and below the camera; a corner can block the
  barrel and not the camera ray, and the bot only checked the camera's.
- **Fix:** the bot fires only when the line to the target is open from the eye **and** from the barrel
  (`Autopilot._clear`).
- **Documented:** [the autopilot](../design/slice.md#the-autopilot).
