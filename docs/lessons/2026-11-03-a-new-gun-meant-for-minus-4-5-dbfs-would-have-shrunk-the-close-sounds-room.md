# A new gun trimmed to the -4.5 dBFS rule would have shrunk the close sounds' room

2026-11-03

- **Symptom:** adding seven firearms (#790), the first trims left the .50 calibre peaking at -4.6 dBFS, which passes the
  -4.5 rule of `test_gun_audio_rules.gd`.
- **Cause:** `test_close_sound_levels.gd` takes the room for the dead's voices and the boards from the loudest gun's peak
  in `gun_levels.json` (the rifle's -4.9: `10^(-1/20) - 10^(-4.9/20)` is 0.32, -9.8 dBFS) and every measured close row
  must fit under it. A gun at -4.6 would leave 0.30, -10.4 dBFS, and rows measured at -9.9 would be over it. The -4.5
  line is a floor for each gun; the loudest gun in the table is what the rest of the mix is built on.
- **Fix:** a new firearm peaks no closer to full scale than the loudest existing one (-4.9, so -5.0 or lower in the
  table); read the table's maximum, not the rule's constant, when setting a trim.
- **Documented:** [gun audio](../research/gun-audio.md#the-second-batch-of-firearms-790).
